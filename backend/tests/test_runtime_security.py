"""
Production security is decided by explicit configuration (APP_ENV) and fails closed.

- APP_ENV is validated; unset means production.
- Development-only static API keys never authenticate in staging or production.
- A staging/production process refuses to start without its required settings,
  and its logs name missing settings without ever printing secret values.
- Interactive API docs and the OpenAPI schema are off in production.
- No unauthenticated response echoes configured secrets.
"""

import asyncio
import json
import logging
import os
import subprocess
import sys
from pathlib import Path

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError

import backend.app.db.session as session_module
from backend.app.config import Settings, settings
from backend.app.main import app
from backend.app.runtime_checks import run_startup_checks
from backend.app.security.auth import UnifiedAuthenticator

REPO_ROOT = Path(__file__).resolve().parents[2]

SECRET_SENTINELS = {
    "openai_api_key": "sk-proj-SENTINEL-openai-0123456789",
    "numista_api_key": "SENTINEL-numista-0123456789",
    "metals_api_key": "SENTINEL-metals-0123456789",
    "supabase_service_role_key": "SENTINEL-service-role-0123456789",
    "supabase_secret_key": "sb_secret_SENTINEL-admin-0123456789",
    "supabase_jwt_secret": "SENTINEL-jwt-secret-0123456789-0123456789",
    "guest_quota_hmac_secret": "SENTINEL-guest-hmac-0123456789-0123456789",
    "revenuecat_webhook_secret": "SENTINEL-revenuecat-0123456789",
}


def _run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


class _Req:
    def __init__(self, headers):
        self.headers = headers
        self.client = type("C", (), {"host": "127.0.0.1"})()


@pytest.fixture
def fresh_engine():
    """The database engine is created from settings; start and end without one."""
    session_module._engine = None
    session_module._session_factory = None
    yield
    engine = session_module._engine
    if engine is not None:
        _run(engine.dispose())
    session_module._engine = None
    session_module._session_factory = None


# ── APP_ENV ──────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("raw,expected", [
    ("production", "production"), ("Production ", "production"), ("STAGING", "staging"),
    ("development", "development"), ("test", "test"), ("", "production"),
])
def test_app_env_is_normalised(monkeypatch, raw, expected):
    monkeypatch.setenv("APP_ENV", raw)
    assert Settings(_env_file=None).app_env == expected


@pytest.mark.parametrize("raw", ["prod", "dev", "live", "productoin"])
def test_unknown_app_env_refuses_to_load(monkeypatch, raw):
    monkeypatch.setenv("APP_ENV", raw)
    with pytest.raises(ValidationError):
        Settings(_env_file=None)


# ── Development-only static API keys ─────────────────────────────────────────

@pytest.mark.parametrize("app_env", ["development", "test"])
def test_static_dev_keys_work_only_for_development(monkeypatch, app_env):
    monkeypatch.setattr(settings, "api_secret", "static-dev-secret-value")
    monkeypatch.setattr(settings, "app_env", app_env)
    caller = UnifiedAuthenticator().resolve_caller(_Req({"X-API-Secret": "static-dev-secret-value"}))
    assert caller.is_authenticated is True


@pytest.mark.parametrize("app_env", ["staging", "production"])
@pytest.mark.parametrize("header", ["X-API-Secret", "X-API-Key"])
def test_static_dev_keys_never_authenticate_when_hardened(monkeypatch, app_env, header):
    monkeypatch.setattr(settings, "api_secret", "static-dev-secret-value")
    monkeypatch.setattr(settings, "api_keys_json", json.dumps({"static-json-key": "pro"}))
    auth = UnifiedAuthenticator()  # loads the static key map
    monkeypatch.setattr(settings, "app_env", app_env)
    for key in ("static-dev-secret-value", "static-json-key"):
        with pytest.raises(HTTPException) as exc:
            auth.resolve_caller(_Req({header: key}))
        assert exc.value.status_code == 401


# ── Startup refuses incomplete hardened configuration ────────────────────────

def _clear_required(monkeypatch):
    for name in ("database_url", "supabase_url", "supabase_jwt_issuer", "supabase_jwks_url",
                 "supabase_jwt_secret", "supabase_jwt_public_key"):
        monkeypatch.setattr(settings, name, None)


@pytest.mark.parametrize("app_env", ["staging", "production"])
def test_startup_refuses_without_database_or_token_verification(monkeypatch, caplog, app_env):
    _clear_required(monkeypatch)
    monkeypatch.setattr(settings, "app_env", app_env)
    caplog.set_level(logging.INFO)

    with pytest.raises(RuntimeError, match="refuses to start"):
        run_startup_checks()
    assert "DATABASE_URL is not set" in caplog.text
    assert "SUPABASE_URL is not set" in caplog.text


def test_startup_refusal_happens_in_the_app_lifespan(monkeypatch, fresh_engine):
    _clear_required(monkeypatch)
    monkeypatch.setattr(settings, "app_env", "production")

    async def start():
        async with app.router.lifespan_context(app):
            pass

    with pytest.raises(RuntimeError):
        _run(start())


def test_startup_logs_name_settings_but_never_print_secret_values(monkeypatch, caplog):
    monkeypatch.setattr(settings, "app_env", "production")
    for name, value in SECRET_SENTINELS.items():
        monkeypatch.setattr(settings, name, value)
    monkeypatch.setattr(settings, "database_url", "postgresql://user:SENTINEL-db-password@db.example/postgres")
    monkeypatch.setattr(settings, "supabase_url", "https://project.supabase.co")
    monkeypatch.setattr(settings, "api_secret", "SENTINEL-static-dev-key")
    monkeypatch.setattr(settings, "numista_api_key", None)
    caplog.set_level(logging.DEBUG)

    run_startup_checks()  # complete enough to start

    assert "API_SECRET is set but ignored in production" in caplog.text
    assert "NUMISTA_API_KEY" in caplog.text  # reported as missing for readiness
    for value in list(SECRET_SENTINELS.values()) + ["SENTINEL-db-password", "SENTINEL-static-dev-key"]:
        assert value not in caplog.text


def test_unreachable_database_stops_a_hardened_startup_without_leaking_the_password(monkeypatch, caplog, fresh_engine):
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "database_url", "postgresql://coinscan:SENTINEL-db-password@127.0.0.1:1/postgres")
    monkeypatch.setattr(settings, "db_ssl_mode", "disable")
    monkeypatch.setattr(settings, "db_connect_timeout_seconds", 2.0)
    caplog.set_level(logging.DEBUG)

    with pytest.raises(RuntimeError) as exc:
        _run(session_module.init_db())
    assert "SENTINEL-db-password" not in str(exc.value)
    assert "Database connection check failed on startup" in caplog.text
    assert "SENTINEL-db-password" not in caplog.text


def test_development_startup_warns_that_development_aids_are_on(monkeypatch, caplog):
    monkeypatch.setattr(settings, "app_env", "development")
    caplog.set_level(logging.WARNING)
    run_startup_checks()
    assert "development aids are ENABLED" in caplog.text


# ── No docs, no schema, no secrets on the public surface ─────────────────────

def test_production_process_has_no_api_docs_or_schema():
    """Imports the app in a fresh production process (settings are read at import)."""
    env = {k: v for k, v in os.environ.items() if k not in ("APP_ENV", "DATABASE_URL")}
    env["PYTHONPATH"] = str(REPO_ROOT)
    code = (
        "from backend.app.main import app\n"
        "print(app.docs_url, app.redoc_url, app.openapi_url)\n"
        "from fastapi.testclient import TestClient\n"
        "c = TestClient(app)\n"
        "print(c.get('/docs').status_code, c.get('/openapi.json').status_code)\n"
    )
    out = subprocess.run([sys.executable, "-c", code], env=env, cwd=REPO_ROOT,
                         capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stderr
    lines = out.stdout.strip().splitlines()
    assert lines[-2] == "None None None"
    assert lines[-1] == "404 404"


def test_public_endpoints_never_echo_configured_secrets(monkeypatch):
    for name, value in SECRET_SENTINELS.items():
        monkeypatch.setattr(settings, name, value)
    client = TestClient(app)
    for path in ("/", "/health", "/health/live", "/health/ready"):
        body = client.get(path).text
        for value in SECRET_SENTINELS.values():
            assert value not in body, (path, value)
