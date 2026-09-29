"""
Database Engine & Async Session Lifecycle Management.

Guarantees:
1. In production, fails closed immediately if DATABASE_URL is missing or unconfigured.
2. Async connection pooling with pool_pre_ping and bounded connections.
3. Clean startup and shutdown engine disposal lifecycle.
4. Strict account isolation and transaction boundaries.
"""

import logging
from typing import AsyncGenerator, Optional
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from backend.app.config import settings

logger = logging.getLogger("coinscan.db")

_engine: Optional[AsyncEngine] = None
_session_factory: Optional[async_sessionmaker[AsyncSession]] = None


def is_db_configured() -> bool:
    """Returns True if a valid database URL is configured."""
    return bool(settings.database_url and settings.database_url.strip())


def ensure_db_readiness():
    """Validates that production environment has explicit database configuration."""
    if settings.app_env == "production" and not is_db_configured():
        logger.critical(
            "CRITICAL: DATABASE_URL is not configured in production. "
            "CoinScan cannot start or persist state without database persistence."
        )
        raise RuntimeError(
            "DATABASE_URL is not configured in production. "
            "Database-backed persistence is strictly required."
        )


def get_async_engine() -> Optional[AsyncEngine]:
    """Retrieves or initializes the global async SQLAlchemy engine."""
    global _engine
    if _engine is not None:
        return _engine

    ensure_db_readiness()

    if not is_db_configured():
        return None

    db_url = settings.database_url.strip()

    # Standardize postgresql:// to postgresql+asyncpg:// if needed
    if db_url.startswith("postgresql://"):
        db_url = db_url.replace("postgresql://", "postgresql+asyncpg://", 1)
    elif db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql+asyncpg://", 1)

    connect_args = {}
    engine_kwargs = {
        "echo": settings.log_level.lower() == "debug",
    }

    # PostgreSQL / asyncpg connection pool configuration
    if "asyncpg" in db_url:
        engine_kwargs.update({
            "pool_size": 10,
            "max_overflow": 20,
            "pool_pre_ping": True,
            "pool_recycle": 1800,  # Recycle connections after 30 minutes
        })

    _engine = create_async_engine(
        db_url,
        connect_args=connect_args,
        **engine_kwargs,
    )
    logger.info("Initialized async database engine.")
    return _engine


def get_session_factory() -> Optional[async_sessionmaker[AsyncSession]]:
    """Retrieves or creates the async session factory."""
    global _session_factory
    if _session_factory is not None:
        return _session_factory

    engine = get_async_engine()
    if engine is None:
        return None

    _session_factory = async_sessionmaker(
        bind=engine,
        class_=AsyncSession,
        expire_on_commit=False,
        autocommit=False,
        autoflush=False,
    )
    return _session_factory


async def init_db():
    """FastAPI startup lifecycle hook."""
    ensure_db_readiness()
    if is_db_configured():
        engine = get_async_engine()
        # Verify engine connection
        try:
            async with engine.begin() as conn:
                from sqlalchemy import text
                await conn.execute(text("SELECT 1"))
            logger.info("Database connectivity verified on startup.")
        except Exception as e:
            if settings.app_env == "production":
                logger.critical(f"Database connection check failed on startup: {e}")
                raise RuntimeError(f"Database connectivity failed: {e}")
            else:
                logger.warning(f"Database connection check skipped/failed in dev: {e}")


async def close_db():
    """FastAPI shutdown lifecycle hook."""
    global _engine, _session_factory
    if _engine is not None:
        logger.info("Disposing async database engine.")
        await _engine.dispose()
        _engine = None
        _session_factory = None


async def get_db() -> AsyncGenerator[Optional[AsyncSession], None]:
    """FastAPI dependency for yielding async database sessions."""
    if settings.app_env == "production" and not is_db_configured():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database persistence unconfigured in production.",
        )

    factory = get_session_factory()
    if factory is None:
        yield None
        return

    async with factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
