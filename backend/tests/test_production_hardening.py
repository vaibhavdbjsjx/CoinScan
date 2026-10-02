"""
Phase 3 production-readiness regressions.

- httpx request lines (which can carry API keys in query strings) never reach the logs.
- CORS: ALLOWED_ORIGINS parsing, preflight, credentials and startup advice.
- The rate limiter honours RATE_LIMIT_PER_MINUTE and forgets idle callers.
- Collection item ids that are not UUIDs never reach the UUID-typed columns.
- The OpenAI request carries an output-token ceiling.
- A RevenueCat event is retried (500, not recorded) when the subscriber's event
  history cannot be read, rather than possibly overwriting newer state.
"""

import asyncio
import logging
import time
import uuid

import httpx
import pytest
from fastapi.testclient import TestClient
from starlette.applications import Starlette
from starlette.middleware.cors import CORSMiddleware
from starlette.responses import PlainTextResponse
from starlette.routing import Route

import backend.app.api.webhooks as webhooks_module
from backend.app.api.account import account_store
from backend.app.api.webhooks import webhook_state
from backend.app.config import settings
from backend.app.main import app
from backend.app.runtime_checks import cors_warnings, parse_allowed_origins, run_startup_checks
from backend.app.security import rate_limit as rate_limit_module
from backend.app.security.rate_limit import InMemoryRateLimiter, SubscriptionTier
from backend.app.services.recognition import vision_provider as vision_module


def _run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


# ── Logging ──────────────────────────────────────────────────────────────────

def test_http_client_request_urls_are_never_logged(caplog):
    """metals-api takes its key as ?access_key=; httpx logs request URLs at INFO."""
    async def fetch():
        transport = httpx.MockTransport(lambda request: httpx.Response(200, json={}))
        async with httpx.AsyncClient(transport=transport) as client:
            await client.get("https://metals-api.example/api/latest",
                             params={"access_key": "PLANTED-metals-key-0123"})

    with caplog.at_level(logging.DEBUG):
        _run(fetch())
    assert "PLANTED-metals-key-0123" not in caplog.text
    assert logging.getLogger("httpx").getEffectiveLevel() >= logging.WARNING
    assert logging.getLogger("httpcore").getEffectiveLevel() >= logging.WARNING


# ── CORS ─────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("raw,expected", [
    ("", ["*"]),
    ("*", ["*"]),
    ("https://app.example.com, *", ["*"]),
    ("https://app.example.com/", ["https://app.example.com"]),
    (" https://app.example.com ,https://www.example.com/,https://app.example.com",
     ["https://app.example.com", "https://www.example.com"]),
    ("http://localhost:5173", ["http://localhost:5173"]),
])
def test_allowed_origins_parsing(raw, expected):
    assert parse_allowed_origins(raw) == expected


def _cors_app(raw_origins):
    origins = parse_allowed_origins(raw_origins)
    inner = Starlette(routes=[Route("/v1/recognition", lambda r: PlainTextResponse("ok"), methods=["POST"])])
    return CORSMiddleware(inner, allow_origins=origins, allow_credentials=origins != ["*"],
                          allow_methods=["*"], allow_headers=["*"])


def _preflight(client, origin):
    return client.options("/v1/recognition", headers={
        "Origin": origin,
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "authorization,content-type,x-coinscan-install-id",
    })


def test_preflight_allows_only_configured_origins():
    client = TestClient(_cors_app("https://app.example.com/"))  # trailing slash as typed in a dashboard
    ok = _preflight(client, "https://app.example.com")
    assert ok.status_code == 200
    assert ok.headers["access-control-allow-origin"] == "https://app.example.com"
    assert "authorization" in ok.headers["access-control-allow-headers"].lower()

    for other in ("https://evil.example", "http://app.example.com", "https://app.example.com.evil.example"):
        denied = _preflight(client, other)
        assert denied.status_code == 400
        assert "access-control-allow-origin" not in denied.headers


def test_wildcard_never_allows_credentials():
    resp = _preflight(TestClient(app), "https://anything.example")  # test settings use "*"
    assert resp.status_code == 200
    assert resp.headers["access-control-allow-origin"] == "*"
    assert "access-control-allow-credentials" not in resp.headers


def test_hardened_startup_warns_about_wildcard_and_plain_http_origins(monkeypatch, caplog):
    monkeypatch.setattr(settings, "allowed_origins", "*")
    assert cors_warnings() and "every website" in cors_warnings()[0]
    monkeypatch.setattr(settings, "allowed_origins", "https://app.example.com,http://insecure.example.com")
    assert cors_warnings() == ["ALLOWED_ORIGINS entry http://insecure.example.com is not https."]
    monkeypatch.setattr(settings, "allowed_origins", "https://app.example.com")
    assert cors_warnings() == []

    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "database_url", "postgresql://u@db.invalid/postgres")
    monkeypatch.setattr(settings, "supabase_url", "https://project-ref.supabase.co")
    monkeypatch.setattr(settings, "allowed_origins", "*")
    with caplog.at_level(logging.WARNING, logger="coinscan.startup"):
        run_startup_checks()
    assert "ALLOWED_ORIGINS allows every website" in caplog.text


# ── Rate limiting ────────────────────────────────────────────────────────────

def test_rate_limit_setting_is_honoured():
    assert rate_limit_module.rate_limiter.default_rpm == max(1, settings.rate_limit_per_minute)


def test_rate_limiter_forgets_idle_callers(monkeypatch):
    limiter = InMemoryRateLimiter(default_rpm=5)
    clock = {"now": 1_000_000.0}
    monkeypatch.setattr(rate_limit_module.time, "time", lambda: clock["now"])
    for i in range(500):
        limiter.check_rate_limit(f"2001:db8::{i:x}", user_id=f"user-{i}", tier=SubscriptionTier.FREE)
    assert len(limiter._ip_history) == 500

    clock["now"] += limiter.window + 1
    limiter.check_rate_limit("198.51.100.7", tier=SubscriptionTier.ANONYMOUS)
    assert list(limiter._ip_history) == ["198.51.100.7"]
    assert len(limiter._user_history) == 0


def test_rate_limiter_still_limits_after_sweeping(monkeypatch):
    limiter = InMemoryRateLimiter(default_rpm=3)
    clock = {"now": 1_000_000.0}
    monkeypatch.setattr(rate_limit_module.time, "time", lambda: clock["now"])
    for _ in range(3):
        limiter.check_rate_limit("198.51.100.7")
        clock["now"] += 1
    with pytest.raises(Exception) as exc:
        limiter.check_rate_limit("198.51.100.7")
    assert getattr(exc.value, "status_code", None) == 429


# ── Collection ids ───────────────────────────────────────────────────────────

def test_collection_create_ignores_non_uuid_client_ids(monkeypatch):
    client = TestClient(app)
    headers = {"Authorization": "Bearer usr_phase3_ids"}
    client.post("/v1/account/legal/consent", headers=headers,
                json={"terms_version": settings.required_terms_version,
                      "privacy_version": settings.required_privacy_version})
    bogus = "x" * 36
    resp = client.post("/v1/collection", headers=headers,
                       json={"id": bogus, "coin_name": "Coin", "country": "France", "denomination": "1 Franc"})
    assert resp.status_code == 200, resp.text
    assert resp.json()["id"] != bogus
    uuid.UUID(resp.json()["id"])

    chosen = str(uuid.uuid4())
    resp = client.post("/v1/collection", headers=headers,
                       json={"id": chosen, "coin_name": "Coin", "country": "France", "denomination": "1 Franc"})
    assert resp.json()["id"] == chosen


def test_deleting_a_non_uuid_collection_id_is_not_found(monkeypatch):
    calls = []
    monkeypatch.setattr("backend.app.api.account.is_db_configured", lambda: True)
    monkeypatch.setattr("backend.app.api.account.get_session_factory", lambda: calls.append("db") or None)
    assert _run(account_store.delete_collection_item_async("usr_x", "../../etc/passwd")) is False
    assert calls == []  # the database was never asked


# ── OpenAI request ───────────────────────────────────────────────────────────

def test_openai_request_has_an_output_token_ceiling(monkeypatch):
    sent = {}

    async def fake_post(provider, url, payload, headers, timeout):
        sent.update(provider=provider, url=url, payload=payload, headers=headers, timeout=timeout)
        return {"choices": [{"message": {"content": '{"country": "France"}'}}]}

    monkeypatch.setattr(vision_module, "_post_to_provider", fake_post)
    provider = vision_module.OpenAIVisionProvider(api_key="sk-proj-PLANTED-openai-0123")
    obs = _run(provider.analyze_coin_images(front_b64="AAAA"))

    assert obs.country == "France"
    assert sent["url"] == "https://api.openai.com/v1/chat/completions"
    assert sent["payload"]["max_completion_tokens"] == vision_module.OPENAI_MAX_COMPLETION_TOKENS <= 2000
    assert sent["payload"]["response_format"] == {"type": "json_object"}
    assert "store" not in sent["payload"] or sent["payload"]["store"] is False
    assert sent["timeout"] <= 30
    assert "PLANTED" not in sent["url"]


# ── RevenueCat ordering fails safe ───────────────────────────────────────────

class _BrokenSession:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        return False

    async def execute(self, *args, **kwargs):
        raise RuntimeError("database unavailable: SENTINEL-sql-params")

    async def get(self, *args, **kwargs):
        return None


def test_unreadable_event_history_makes_revenuecat_retry(monkeypatch, caplog):
    secret = "test_phase3_rc_secret"
    monkeypatch.setattr(settings, "revenuecat_webhook_secret", secret)
    webhook_state.reset_for_test()
    monkeypatch.setattr(webhooks_module, "is_db_configured", lambda: True)
    monkeypatch.setattr(webhooks_module, "get_session_factory", lambda: (lambda: _BrokenSession()))

    async def not_processed(event_id):
        return False

    # Only the history read fails here (an unreadable idempotency check is a 500 as well).
    monkeypatch.setattr(webhook_state, "is_processed_async", not_processed)
    event_id = f"evt_{uuid.uuid4()}"
    now = int(time.time() * 1000)
    event = {"id": event_id, "type": "RENEWAL", "app_user_id": str(uuid.uuid4()),
             "event_timestamp_ms": now, "product_id": "com.coinscan.pro.monthly",
             "entitlement_ids": ["pro"], "expiration_at_ms": now + 86_400_000}

    with caplog.at_level(logging.DEBUG):
        resp = TestClient(app).post("/v1/webhooks/revenuecat", json={"event": event},
                                    headers={"Authorization": f"Bearer {secret}"})

    assert resp.status_code == 500
    assert not webhook_state.is_processed(event_id)
    assert "SENTINEL-sql-params" not in caplog.text
    webhook_state.reset_for_test()


# ── Vision provider selection ────────────────────────────────────────────────

@pytest.mark.parametrize("raw,expected", [("OpenAI", "openai"), (" openai ", "openai"), ("", "openai"),
                                          ("GEMINI", "gemini")])
def test_vision_provider_is_normalised(raw, expected):
    from backend.app.config import Settings
    assert Settings(_env_file=None, vision_provider=raw).vision_provider == expected


def test_unknown_vision_provider_is_refused_at_startup():
    from pydantic import ValidationError
    from backend.app.config import Settings
    with pytest.raises(ValidationError):
        Settings(_env_file=None, vision_provider="mock")


def test_mixed_case_provider_selects_openai_not_a_503(monkeypatch):
    from backend.app.api.recognition import get_vision_provider
    from backend.app.config import Settings
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "vision_provider", Settings(_env_file=None, vision_provider="OpenAI").vision_provider)
    monkeypatch.setattr(settings, "openai_api_key", "sk-proj-PLANTED-openai-0123")
    monkeypatch.setattr(settings, "gemini_api_key", "AIzaPLANTED-gemini-key-000000000000000000")
    assert type(get_vision_provider()).__name__ == "OpenAIVisionProvider"


def test_hardened_startup_warns_when_gemini_is_selected_or_configured(monkeypatch, caplog):
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "database_url", "postgresql://u@db.invalid/postgres")
    monkeypatch.setattr(settings, "supabase_url", "https://project-ref.supabase.co")
    monkeypatch.setattr(settings, "gemini_api_key", "AIzaPLANTED-gemini-key-000000000000000000")
    monkeypatch.setattr(settings, "vision_provider", "gemini")
    with caplog.at_level(logging.WARNING, logger="coinscan.startup"):
        run_startup_checks()
    assert "legacy provider is selected" in caplog.text

    caplog.clear()
    monkeypatch.setattr(settings, "vision_provider", "openai")
    with caplog.at_level(logging.WARNING, logger="coinscan.startup"):
        run_startup_checks()
    assert "GEMINI_API_KEY is set but unused" in caplog.text
    assert "AIzaPLANTED" not in caplog.text
