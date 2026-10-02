"""
P0 regression tests: AI provider credentials must never reach API clients.

Covers:
- Gemini API key is sent in a header, never in the request URL.
- Provider HTTP / transport failures return a generic client message that
  contains no credential, URL or raw exception text, and do not consume quota.
- Legacy static API keys (API_SECRET / API_KEYS_JSON) are refused in production.
"""

import io

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image

from backend.app.config import settings
from backend.app.main import app
from backend.app.security.auth import UnifiedAuthenticator
from backend.app.security.quota_service import quota_engine
from backend.app.security.guest_quota import guest_allowance
from backend.app.services.recognition import vision_provider as vp
from backend.app.services.recognition.vision_provider import (
    GeminiVisionProvider,
    OpenAIVisionProvider,
    VisionProviderError,
)

FAKE_GEMINI_KEY = "AIzaTEST_FAKE_KEY_should_never_leak_123"


def _jpeg_bytes(size: int = 400) -> bytes:
    img = Image.new("RGB", (size, size), color=(120, 110, 90))
    # Add structure so the blur check passes
    for x in range(0, size, 8):
        for y in range(size):
            img.putpixel((x, y), (250, 250, 250))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=92)
    return buf.getvalue()


class _CapturingTransport:
    """Builds an httpx.AsyncClient replacement that answers with a fixed status."""

    def __init__(self, status_code: int = 429, raise_exc: Exception = None):
        self.status_code = status_code
        self.raise_exc = raise_exc
        self.requests = []

    def client_class(self):
        outer = self
        original = httpx.AsyncClient

        def handler(request: httpx.Request) -> httpx.Response:
            outer.requests.append(request)
            if outer.raise_exc is not None:
                raise outer.raise_exc
            return httpx.Response(outer.status_code, json={"error": {"message": "quota"}})

        class _Client(original):
            def __init__(self, *args, **kwargs):
                kwargs["transport"] = httpx.MockTransport(handler)
                super().__init__(*args, **kwargs)

        return _Client


def test_gemini_endpoint_never_contains_api_key():
    provider = GeminiVisionProvider(api_key=FAKE_GEMINI_KEY)
    assert FAKE_GEMINI_KEY not in provider.endpoint
    assert "key=" not in provider.endpoint


@pytest.mark.asyncio
async def test_gemini_sends_key_in_header_only(monkeypatch):
    transport = _CapturingTransport(status_code=500)
    monkeypatch.setattr(vp.httpx, "AsyncClient", transport.client_class())
    provider = GeminiVisionProvider(api_key=FAKE_GEMINI_KEY)

    with pytest.raises(VisionProviderError) as exc_info:
        await provider.analyze_coin_images(front_b64="AAAA")

    sent = transport.requests[0]
    assert FAKE_GEMINI_KEY not in str(sent.url)
    assert sent.headers.get("x-goog-api-key") == FAKE_GEMINI_KEY
    # The sanitized error itself must not carry the key or the URL
    assert FAKE_GEMINI_KEY not in str(exc_info.value)
    assert "googleapis" not in str(exc_info.value)
    assert exc_info.value.status_code == 500


@pytest.mark.asyncio
async def test_transport_error_is_sanitized(monkeypatch):
    boom = httpx.ConnectError(f"connect failed for https://x/?key={FAKE_GEMINI_KEY}")
    transport = _CapturingTransport(raise_exc=boom)
    monkeypatch.setattr(vp.httpx, "AsyncClient", transport.client_class())

    with pytest.raises(VisionProviderError) as exc_info:
        await GeminiVisionProvider(api_key=FAKE_GEMINI_KEY).analyze_coin_images(front_b64="AAAA")
    assert FAKE_GEMINI_KEY not in str(exc_info.value)


@pytest.mark.asyncio
async def test_openai_error_is_sanitized(monkeypatch):
    transport = _CapturingTransport(status_code=401)
    monkeypatch.setattr(vp.httpx, "AsyncClient", transport.client_class())
    with pytest.raises(VisionProviderError) as exc_info:
        await OpenAIVisionProvider(api_key="sk-test-secret").analyze_coin_images(front_b64="AAAA")
    assert "sk-test-secret" not in str(exc_info.value)
    assert exc_info.value.status_code == 401


@pytest.mark.parametrize("status_code", [400, 429, 500, 503])
def test_recognition_provider_failure_does_not_leak_key_or_charge_quota(monkeypatch, status_code):
    transport = _CapturingTransport(status_code=status_code)
    monkeypatch.setattr(vp.httpx, "AsyncClient", transport.client_class())
    monkeypatch.setattr(settings, "vision_provider", "gemini")
    monkeypatch.setattr(settings, "gemini_api_key", FAKE_GEMINI_KEY)
    quota_engine.reset_usage_for_test()

    client = TestClient(app)
    resp = client.post(
        "/v1/recognition",
        files={"front_image": ("front.jpg", _jpeg_bytes(), "image/jpeg")},
    )

    assert resp.status_code == 200
    body_text = resp.text
    assert FAKE_GEMINI_KEY not in body_text
    assert "googleapis" not in body_text
    assert "key=" not in body_text
    body = resp.json()
    assert body["status"] == "error"
    assert body["candidates"] == []
    # Failed scans must not consume the guest allowance (the reserved slot is given back)
    assert all(v == 0 for v in guest_allowance.store._local.values())


def test_missing_provider_credentials_in_staging_releases_quota(monkeypatch):
    monkeypatch.setattr(settings, "app_env", "staging")
    monkeypatch.setattr(settings, "gemini_api_key", None)
    monkeypatch.setattr(settings, "openai_api_key", None)
    # Guests on staging need the guest-quota key, so the request reaches the
    # vision-provider check this test is about.
    monkeypatch.setattr(settings, "guest_quota_hmac_secret", "staging-test-secret")
    quota_engine.reset_usage_for_test()

    client = TestClient(app)
    resp = client.post(
        "/v1/recognition",
        files={"front_image": ("front.jpg", _jpeg_bytes(), "image/jpeg")},
    )
    assert resp.status_code == 503
    assert "not configured on this staging service" in str(resp.json())
    # The reserved guest slot was given back
    assert all(v == 0 for v in guest_allowance.store._local.values())


class _Req:
    def __init__(self, headers):
        self.headers = headers
        self.client = type("C", (), {"host": "127.0.0.1"})()


def test_legacy_static_api_key_rejected_in_production(monkeypatch):
    monkeypatch.setattr(settings, "api_secret", "legacy_static_secret_value")
    auth = UnifiedAuthenticator()  # loads the static key map

    monkeypatch.setattr(settings, "app_env", "production")
    with pytest.raises(HTTPException) as exc_info:
        auth.resolve_caller(_Req({"X-API-Secret": "legacy_static_secret_value"}))
    assert exc_info.value.status_code == 401


def test_legacy_static_api_key_still_works_in_local_development(monkeypatch):
    monkeypatch.setattr(settings, "api_secret", "legacy_static_secret_value")
    monkeypatch.setattr(settings, "app_env", "development")
    auth = UnifiedAuthenticator()
    caller = auth.resolve_caller(_Req({"X-API-Secret": "legacy_static_secret_value"}))
    assert caller.is_authenticated is True
    assert caller.auth_method == "api_key"
