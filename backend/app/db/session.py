"""
Database Engine & Async Session Lifecycle Management.
Guarantees:
1. In production, fails closed immediately if DATABASE_URL is missing or unconfigured.
2. Async connection pooling with pool_pre_ping and bounded connections.
3. Clean startup and shutdown engine disposal lifecycle.
4. Strict account isolation and transaction boundaries.

Supabase notes:
- Hosts without outbound IPv6 (e.g. Railway) must use Supabase's IPv4
  connection pooler (Supavisor) rather than the IPv6-only direct host.
- Session mode (port 5432 on the pooler) behaves like a direct connection.
  Transaction mode (port 6543) cannot keep prepared statements, so the
  statement caches are disabled and statement names made unique.
- TLS is required by default in staging and production.
- libpq-style `sslmode=` in the URL is translated to asyncpg's `ssl=`
  (asyncpg does not accept `sslmode` and would fail to connect).
"""

import asyncio
import logging
import re
import uuid
from typing import AsyncGenerator, Dict, Optional, Tuple

from fastapi import HTTPException, status
from sqlalchemy import inspect, text
from sqlalchemy.engine import URL, make_url
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

_SSL_MODES = {"disable", "allow", "prefer", "require", "verify-ca", "verify-full"}
_CREDENTIALS_IN_URL = re.compile(r"(?P<scheme>[a-z][a-z0-9+.\-]*://)[^@/\s]+@", re.IGNORECASE)


def redact(text_value: str) -> str:
    """Removes credentials from any connection URL inside a message."""
    return _CREDENTIALS_IN_URL.sub(r"\g<scheme>***@", text_value or "")


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


def build_engine_options(raw_url: str) -> Tuple[URL, Dict, Dict]:
    """Returns (url, connect_args, engine_kwargs) for create_async_engine."""
    url = make_url(raw_url.strip())
    if url.drivername in ("postgres", "postgresql"):
        url = url.set(drivername="postgresql+asyncpg")

    # SQL echo logs statement parameters (user ids, collection data): local only.
    engine_kwargs: Dict = {"echo": settings.dev_features_enabled and settings.log_level.lower() == "debug"}
    connect_args: Dict = {}

    if url.drivername == "postgresql+asyncpg":
        query = dict(url.query)
        url_ssl = query.pop("ssl", None) or query.pop("sslmode", None)
        query.pop("sslmode", None)
        pgbouncer_flag = str(query.pop("pgbouncer", "")).lower() == "true"
        url = url.set(query=query)

        ssl_mode = (settings.db_ssl_mode or url_ssl or ("require" if settings.is_hardened else "")).strip().lower()
        ssl_mode = {"true": "require", "1": "require", "false": "disable", "0": "disable"}.get(ssl_mode, ssl_mode)
        if ssl_mode:
            if ssl_mode not in _SSL_MODES:
                raise RuntimeError("DB_SSL_MODE / sslmode must be one of: " + ", ".join(sorted(_SSL_MODES)))
            connect_args["ssl"] = ssl_mode

        connect_args["timeout"] = settings.db_connect_timeout_seconds
        connect_args["command_timeout"] = settings.db_command_timeout_seconds

        transaction_pooler = settings.db_transaction_pooler
        if transaction_pooler is None:
            transaction_pooler = url.port == 6543 or pgbouncer_flag
        if transaction_pooler:
            # Supavisor / PgBouncer transaction mode: no statement caching, and
            # unique statement names so pooled server connections never collide.
            connect_args["statement_cache_size"] = 0
            connect_args["prepared_statement_cache_size"] = 0
            connect_args["prepared_statement_name_func"] = lambda: f"__asyncpg_{uuid.uuid4().hex}__"

        engine_kwargs.update({
            "pool_size": settings.db_pool_size,
            "max_overflow": settings.db_max_overflow,
            "pool_timeout": settings.db_pool_timeout_seconds,
            "pool_pre_ping": True,
            "pool_recycle": settings.db_pool_recycle_seconds,
        })

    return url, connect_args, engine_kwargs


def get_async_engine() -> Optional[AsyncEngine]:
    """Retrieves or initializes the global async SQLAlchemy engine."""
    global _engine
    if _engine is not None:
        return _engine

    ensure_db_readiness()

    if not is_db_configured():
        return None

    url, connect_args, engine_kwargs = build_engine_options(settings.database_url)
    _engine = create_async_engine(url, connect_args=connect_args, **engine_kwargs)
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


def _describe(exc: BaseException) -> str:
    return f"{type(exc).__name__}: {redact(str(exc))}"[:300]


async def init_db():
    """FastAPI startup lifecycle hook."""
    ensure_db_readiness()
    if is_db_configured():
        engine = get_async_engine()
        # Verify engine connection
        try:
            async with engine.begin() as conn:
                await conn.execute(text("SELECT 1"))
            logger.info("Database connectivity verified on startup.")
        except Exception as e:
            if settings.is_hardened:
                logger.critical(f"Database connection check failed on startup: {_describe(e)}")
                raise RuntimeError("Database connectivity failed on startup (see log above).") from None
            logger.warning(f"Database connection check skipped/failed in {settings.app_env}: {_describe(e)}")


async def check_database(timeout: float) -> str:
    """Readiness probe: 'ok', 'unavailable' or 'not_configured'. Never raises."""
    if not is_db_configured():
        return "not_configured"
    try:
        engine = get_async_engine()

        async def _ping():
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))

        await asyncio.wait_for(_ping(), timeout=timeout)
        return "ok"
    except Exception as e:
        logger.warning(f"Database readiness check failed: {type(e).__name__}")
        return "unavailable"


async def check_schema(timeout: float) -> str:
    """Readiness probe for the migrations: 'ok' when every table the API uses
    exists, 'missing' otherwise (names are logged, never returned),
    'unavailable' or 'not_configured'. Never raises."""
    if not is_db_configured():
        return "not_configured"
    from backend.app.db.models import Base  # local import: models import this module's settings

    required = set(Base.metadata.tables)
    try:
        engine = get_async_engine()

        async def _existing():
            async with engine.connect() as conn:
                return await conn.run_sync(lambda sync_conn: set(inspect(sync_conn).get_table_names()))

        missing = sorted(required - await asyncio.wait_for(_existing(), timeout=timeout))
    except Exception as e:
        logger.warning(f"Database schema check failed: {type(e).__name__}")
        return "unavailable"
    if missing:
        logger.error(
            "Database migrations not applied: missing table(s) " + ", ".join(missing)
            + " (see backend/migrations)."
        )
        return "missing"
    return "ok"


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
