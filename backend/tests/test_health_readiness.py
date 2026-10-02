"""
/health/live and /health/ready.

Readiness is the deploy gate: in staging/production it is 200 only when the
database answers, Supabase token verification is usable and every required
provider setting is present. Responses name checks only, never secrets,
hosts or error details.
"""

import asyncio
import os

import pytest
from fastapi.testclient import TestClient

import backend.app.db.session as session_module
from backend.app.config import settings
from backend.app.main import app
from backend.tests.test_postgres_guest_integration import database  # noqa: F401  (migrated test database)

PG_URL = os.environ.get("TEST_POSTGRES_URL")
DB_PASSWORD = "SENTINEL-db-password-0123"


@pytest.fixture
def fresh_engine():
    session_module._engine = None
    session_module._session_factory = None
    yield
    engine = session_module._engine
    if engine is not None:
        loop = asyncio.new_event_loop()
        try:
            loop.run_until_complete(engine.dispose())
        finally:
            loop.close()
    session_module._engine = None
    session_module._session_factory = None


def _configure_production(monkeypatch, database_url):
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "database_url", database_url)
    monkeypatch.setattr(settings, "db_ssl_mode", "disable")
    monkeypatch.setattr(settings, "readiness_timeout_seconds", 2.0)
    monkeypatch.setattr(settings, "db_connect_timeout_seconds", 2.0)
    monkeypatch.setattr(settings, "supabase_url", "https://project-ref.supabase.co")
    monkeypatch.setattr(settings, "supabase_jwt_secret", "legacy-hs256-secret-that-is-long-enough-123")
    monkeypatch.setattr(settings, "vision_provider", "openai")
    monkeypatch.setattr(settings, "openai_api_key", "sk-proj-SENTINEL-openai")
    monkeypatch.setattr(settings, "numista_api_key", "SENTINEL-numista")
    monkeypatch.setattr(settings, "guest_quota_hmac_secret", "SENTINEL-guest-hmac-0123456789-0123456789")
    monkeypatch.setattr(settings, "revenuecat_webhook_secret", "SENTINEL-revenuecat")
    monkeypatch.setattr(settings, "supabase_secret_key", "sb_secret_SENTINEL-admin-0123456789")


def test_liveness_is_minimal():
    resp = TestClient(app).get("/health/live")
    assert resp.status_code == 200
    assert resp.json() == {"status": "alive"}


def test_readiness_in_tests_without_a_database():
    resp = TestClient(app).get("/health/ready")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ready"
    assert resp.json()["checks"]["database"] == "not_configured"


def test_production_readiness_names_every_missing_requirement(monkeypatch, fresh_engine):
    monkeypatch.setattr(settings, "app_env", "production")
    for name in ("database_url", "supabase_url", "supabase_jwt_secret", "supabase_jwt_public_key",
                 "supabase_jwks_url", "openai_api_key", "gemini_api_key", "numista_api_key",
                 "guest_quota_hmac_secret", "revenuecat_webhook_secret",
                 "supabase_secret_key", "supabase_service_role_key"):
        monkeypatch.setattr(settings, name, None)

    resp = TestClient(app).get("/health/ready")

    assert resp.status_code == 503
    assert resp.json() == {
        "status": "not_ready",
        "checks": {
            "database": "not_configured",
            "schema": "not_configured",
            "auth": "missing",
            "vision": "missing",
            "catalogue": "missing",
            "guest_quota": "missing",
            "revenuecat_webhook": "missing",
            "account_deletion": "missing",
        },
    }


def test_unreachable_database_is_reported_without_connection_details(monkeypatch, fresh_engine):
    _configure_production(monkeypatch, f"postgresql://coinscan:{DB_PASSWORD}@127.0.0.1:1/postgres")

    resp = TestClient(app).get("/health/ready")

    assert resp.status_code == 503
    checks = resp.json()["checks"]
    assert checks["database"] == "unavailable"
    assert checks["schema"] == "unavailable"
    assert all(v == "ok" for k, v in checks.items() if k not in ("database", "schema"))
    for leaked in (DB_PASSWORD, "127.0.0.1", "postgresql", "SENTINEL"):
        assert leaked not in resp.text


@pytest.mark.skipif(not PG_URL, reason="TEST_POSTGRES_URL is not set: PostgreSQL integration tests were not run")
def test_production_ready_with_real_database_and_configuration(monkeypatch, fresh_engine, database):
    # `database` is a fresh PostgreSQL database with every migration applied.
    _configure_production(monkeypatch, database)

    resp = TestClient(app).get("/health/ready")

    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "ready"
    assert set(resp.json()["checks"].values()) == {"ok"}


@pytest.mark.skipif(not PG_URL, reason="TEST_POSTGRES_URL is not set: PostgreSQL integration tests were not run")
def test_database_without_migrations_is_not_ready(monkeypatch, fresh_engine, caplog):
    """A deployment against a database whose migrations were not run never goes live."""
    _configure_production(monkeypatch, PG_URL)  # reachable, but no CoinScan tables

    with caplog.at_level("ERROR", logger="coinscan.db"):
        resp = TestClient(app).get("/health/ready")

    assert resp.status_code == 503
    assert resp.json()["checks"]["database"] == "ok"
    assert resp.json()["checks"]["schema"] == "missing"
    assert "guest_scan_usage" not in resp.text  # names are logged, never returned
    assert "guest_scan_usage" in caplog.text
