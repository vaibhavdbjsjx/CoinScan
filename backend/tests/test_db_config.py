"""
Database connection settings for Supabase PostgreSQL (direct, session pooler,
transaction pooler) as seen from asyncpg / SQLAlchemy.
"""

import asyncio
import os

import asyncpg
import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from backend.app.config import settings
from backend.app.db.session import build_engine_options, redact

PG_URL = os.environ.get("TEST_POSTGRES_URL")
SESSION_POOLER = "postgresql://postgres.project-ref:pw@aws-0-eu-west-1.pooler.supabase.com:5432/postgres"
TRANSACTION_POOLER = "postgresql://postgres.project-ref:pw@aws-0-eu-west-1.pooler.supabase.com:6543/postgres"


def _run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


@pytest.fixture(autouse=True)
def _defaults(monkeypatch):
    monkeypatch.setattr(settings, "db_ssl_mode", None)
    monkeypatch.setattr(settings, "db_transaction_pooler", None)


def test_postgres_urls_use_the_asyncpg_driver():
    for raw in ("postgres://u:p@h:5432/db", "postgresql://u:p@h:5432/db"):
        url, _, _ = build_engine_options(raw)
        assert url.drivername == "postgresql+asyncpg"


def test_asyncpg_itself_does_not_accept_sslmode():
    """Why translation is needed: a Supabase URL with ?sslmode=require would fail."""
    with pytest.raises(TypeError):
        _run(asyncpg.connect(host="127.0.0.1", port=1, sslmode="require"))


@pytest.mark.parametrize("raw", [SESSION_POOLER + "?sslmode=require", SESSION_POOLER + "?ssl=require"])
def test_libpq_style_ssl_options_are_translated(raw):
    url, connect_args, _ = build_engine_options(raw)
    assert connect_args["ssl"] == "require"
    assert "sslmode" not in url.query and "ssl" not in url.query


@pytest.mark.parametrize("app_env", ["staging", "production"])
def test_hardened_environments_require_tls_by_default(monkeypatch, app_env):
    monkeypatch.setattr(settings, "app_env", app_env)
    _, connect_args, _ = build_engine_options(SESSION_POOLER)
    assert connect_args["ssl"] == "require"


def test_development_leaves_tls_to_the_url(monkeypatch):
    monkeypatch.setattr(settings, "app_env", "development")
    _, connect_args, _ = build_engine_options(SESSION_POOLER)
    assert "ssl" not in connect_args


def test_explicit_ssl_mode_wins_and_invalid_values_are_refused(monkeypatch):
    monkeypatch.setattr(settings, "db_ssl_mode", "verify-full")
    _, connect_args, _ = build_engine_options(SESSION_POOLER + "?sslmode=require")
    assert connect_args["ssl"] == "verify-full"
    monkeypatch.setattr(settings, "db_ssl_mode", "sometimes")
    with pytest.raises(RuntimeError):
        build_engine_options(SESSION_POOLER)


@pytest.mark.parametrize("raw,expected", [
    (TRANSACTION_POOLER, True),
    (SESSION_POOLER + "?pgbouncer=true", True),
    (SESSION_POOLER, False),
])
def test_transaction_pooler_disables_prepared_statement_caching(raw, expected):
    url, connect_args, _ = build_engine_options(raw)
    assert "pgbouncer" not in url.query
    if expected:
        assert connect_args["statement_cache_size"] == 0
        assert connect_args["prepared_statement_cache_size"] == 0
        name_func = connect_args["prepared_statement_name_func"]
        assert name_func() != name_func()
    else:
        assert "statement_cache_size" not in connect_args


def test_transaction_pooler_detection_can_be_overridden(monkeypatch):
    monkeypatch.setattr(settings, "db_transaction_pooler", False)
    _, connect_args, _ = build_engine_options(TRANSACTION_POOLER)
    assert "statement_cache_size" not in connect_args
    monkeypatch.setattr(settings, "db_transaction_pooler", True)
    _, connect_args, _ = build_engine_options(SESSION_POOLER)
    assert connect_args["statement_cache_size"] == 0


def test_pool_and_timeouts_come_from_configuration(monkeypatch):
    monkeypatch.setattr(settings, "db_pool_size", 3)
    monkeypatch.setattr(settings, "db_max_overflow", 2)
    monkeypatch.setattr(settings, "db_command_timeout_seconds", 12.0)
    _, connect_args, engine_kwargs = build_engine_options(SESSION_POOLER)
    assert engine_kwargs["pool_size"] == 3 and engine_kwargs["max_overflow"] == 2
    assert engine_kwargs["pool_pre_ping"] is True
    assert connect_args["command_timeout"] == 12.0


def test_one_process_stays_well_inside_supabase_connection_limits():
    _, _, engine_kwargs = build_engine_options(SESSION_POOLER)
    assert engine_kwargs["pool_size"] + engine_kwargs["max_overflow"] <= 10


def test_non_postgres_urls_are_left_alone():
    url, connect_args, engine_kwargs = build_engine_options("sqlite+aiosqlite:///:memory:")
    assert url.drivername == "sqlite+aiosqlite"
    assert connect_args == {} and "pool_size" not in engine_kwargs


def test_redact_removes_credentials_from_messages():
    message = "could not connect to postgresql+asyncpg://postgres.ref:SuperSecret@host:5432/postgres"
    assert "SuperSecret" not in redact(message)
    assert "postgresql+asyncpg://***@host:5432/postgres" in redact(message)


@pytest.mark.skipif(not PG_URL, reason="TEST_POSTGRES_URL is not set: PostgreSQL integration tests were not run")
@pytest.mark.parametrize("transaction_mode", [False, True])
def test_engine_options_work_against_real_postgres(monkeypatch, transaction_mode):
    monkeypatch.setattr(settings, "db_ssl_mode", "disable")
    monkeypatch.setattr(settings, "db_transaction_pooler", transaction_mode)
    url, connect_args, engine_kwargs = build_engine_options(PG_URL + "&sslmode=disable")

    async def exercise():
        engine = create_async_engine(url, connect_args=connect_args, **engine_kwargs)
        try:
            for i in range(5):
                async with engine.begin() as conn:
                    value = (await conn.execute(text("SELECT :n + 1"), {"n": i})).scalar_one()
                    assert value == i + 1
        finally:
            await engine.dispose()

    _run(exercise())
