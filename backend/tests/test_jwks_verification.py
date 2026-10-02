"""
Supabase JWT signing keys (JWKS) and strict token verification.

Uses a real ES256 key pair and a mocked JWKS endpoint, so PyJWT's actual
signature checks run. Hardened environments (staging, production) must reject
every token that is not a valid, unexpired, correctly issued user session.
"""

import asyncio
import base64
import hashlib
import hmac
import json
import time
import uuid

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException
from fastapi.testclient import TestClient

from backend.app.config import settings
from backend.app.main import app
from backend.app.runtime_checks import readiness
from backend.app.security.jwt_auth import (
    AuthenticatedUser,
    JwtAuthVerifier,
    SupabaseSigningKeys,
    signing_keys,
)

SUPABASE_URL = "https://project-ref.supabase.co"
ISSUER = f"{SUPABASE_URL}/auth/v1"
KID = "signing-key-1"
USER_ID = str(uuid.uuid4())


def _run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def _b64(n: int) -> str:
    return base64.urlsafe_b64encode(n.to_bytes(32, "big")).rstrip(b"=").decode()


@pytest.fixture(scope="module")
def ec_key():
    return ec.generate_private_key(ec.SECP256R1())


def _jwk(private_key, kid=KID, **extra):
    numbers = private_key.public_key().public_numbers()
    return {"kty": "EC", "crv": "P-256", "x": _b64(numbers.x), "y": _b64(numbers.y),
            "kid": kid, "alg": "ES256", "use": "sig", **extra}


@pytest.fixture
def jwks(monkeypatch, ec_key):
    """Staging configured for Supabase signing keys only (no legacy secret)."""
    monkeypatch.setattr(settings, "app_env", "staging")
    monkeypatch.setattr(settings, "supabase_url", SUPABASE_URL)
    for name in ("supabase_jwt_secret", "supabase_jwt_public_key", "supabase_jwt_algorithm",
                 "supabase_jwt_issuer", "supabase_jwks_url"):
        monkeypatch.setattr(settings, name, None)
    monkeypatch.setattr(settings, "supabase_jwt_audience", "authenticated")

    state = {"document": {"keys": [_jwk(ec_key)]}, "status": 200, "calls": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        state["calls"] += 1
        assert str(request.url) == f"{ISSUER}/.well-known/jwks.json"
        return httpx.Response(state["status"], json=state["document"])

    signing_keys.transport = httpx.MockTransport(handler)
    return state


def _claims(**overrides):
    claims = {"sub": USER_ID, "aud": "authenticated", "iss": ISSUER, "role": "authenticated",
              "email": "collector@example.com", "exp": int(time.time()) + 3600, "iat": int(time.time())}
    claims.update(overrides)
    return {k: v for k, v in claims.items() if v is not None}


def _token(private_key, kid=KID, **overrides):
    return jwt.encode(_claims(**overrides), private_key, algorithm="ES256", headers={"kid": kid})


def _segment(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _hand_made(header: dict, claims: dict, hmac_key: bytes = None) -> str:
    """Builds a token manually (PyJWT refuses to create these on purpose)."""
    signing_input = f"{_segment(json.dumps(header).encode())}.{_segment(json.dumps(claims).encode())}"
    signature = ""
    if hmac_key is not None:
        signature = _segment(hmac.new(hmac_key, signing_input.encode(), hashlib.sha256).digest())
    return f"{signing_input}.{signature}"


def _rejected(token: str) -> HTTPException:
    with pytest.raises(HTTPException) as exc:
        JwtAuthVerifier().verify_token(f"Bearer {token}")
    assert exc.value.status_code == 401
    return exc.value


# ── Accepting real Supabase sessions ─────────────────────────────────────────

def test_es256_session_verified_through_jwks(jwks, ec_key):
    assert _run(signing_keys.refresh()) is True
    user = JwtAuthVerifier().verify_token(f"Bearer {_token(ec_key)}")
    assert user.user_id == USER_ID and user.is_authenticated and user.auth_method == "jwt"


def test_api_fetches_signing_keys_on_demand(jwks, ec_key):
    """The request path loads the key asynchronously before verifying."""
    client = TestClient(app)
    ok = client.get("/v1/guest/quota", headers={"Authorization": f"Bearer {_token(ec_key)}"})
    assert ok.status_code == 400  # authenticated: guests-only endpoint says use the account quota
    assert jwks["calls"] == 1

    bad = client.get("/v1/guest/quota", headers={"Authorization": f"Bearer {_token(ec_key)}x"})
    assert bad.status_code == 401


def test_legacy_secret_and_signing_keys_work_side_by_side(jwks, ec_key, monkeypatch):
    monkeypatch.setattr(settings, "supabase_jwt_secret", "legacy-hs256-secret-that-is-long-enough-123")
    _run(signing_keys.refresh())
    legacy = jwt.encode(_claims(), "legacy-hs256-secret-that-is-long-enough-123", algorithm="HS256")
    assert JwtAuthVerifier().verify_token(legacy).user_id == USER_ID
    assert JwtAuthVerifier().verify_token(_token(ec_key)).user_id == USER_ID


# ── Rejections ───────────────────────────────────────────────────────────────

def test_unknown_key_id_is_rejected_and_refetching_is_rate_limited(jwks, ec_key):
    client = TestClient(app)
    other = ec.generate_private_key(ec.SECP256R1())
    for _ in range(3):
        resp = client.get("/v1/guest/quota", headers={"Authorization": f"Bearer {_token(other, kid='made-up')}"})
        assert resp.status_code == 401
    assert jwks["calls"] == 1  # one fetch, then the minimum refresh interval applies


def test_tampered_signature_is_rejected(jwks, ec_key):
    _run(signing_keys.refresh())
    forged = _token(ec.generate_private_key(ec.SECP256R1()))  # right kid, wrong key
    assert "Invalid token signature" in _rejected(forged).detail


@pytest.mark.parametrize("overrides", [
    {"exp": int(time.time()) - 60},        # expired
    {"exp": None},                         # never expires
    {"aud": "anon"},                       # wrong audience
    {"aud": None},                         # no audience
    {"iss": "https://evil.example/auth/v1"},  # wrong issuer
    {"role": "anon"},                      # anon key style
    {"role": "service_role"},              # service-role key style
    {"is_anonymous": True},                # anonymous sign-in session
    {"sub": None},                         # no subject
    {"sub": "not-a-uuid"},                 # non-UUID subject
])
def test_invalid_sessions_are_rejected(jwks, ec_key, overrides):
    _run(signing_keys.refresh())
    _rejected(_token(ec_key, **overrides))


def test_unsigned_token_is_rejected(jwks):
    _rejected(_hand_made({"alg": "none", "typ": "JWT"}, _claims()))


@pytest.mark.parametrize("static_public_key", [False, True])
def test_hmac_tokens_are_rejected_without_the_legacy_secret(jwks, ec_key, monkeypatch, static_public_key):
    _run(signing_keys.refresh())
    public_pem = ec_key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    if static_public_key:
        monkeypatch.setattr(settings, "supabase_jwt_public_key", public_pem.decode())
    # An attacker-chosen HMAC secret, and the classic algorithm confusion:
    # HS256 "signed" with the server's public key.
    _rejected(jwt.encode(_claims(), "attacker-chosen-secret-value-0123456789", algorithm="HS256"))
    _rejected(_hand_made({"alg": "HS256", "typ": "JWT", "kid": KID}, _claims(), hmac_key=public_pem))


def test_symmetric_keys_published_in_jwks_are_ignored(jwks, ec_key):
    jwks["document"] = {"keys": [{"kty": "oct", "kid": KID, "k": "c2VjcmV0", "alg": "HS256"}]}
    _run(signing_keys.refresh())
    assert signing_keys.has_keys is False
    _rejected(jwt.encode(_claims(), "symmetric-secret-published-in-jwks-0123456789", algorithm="HS256", headers={"kid": KID}))


def test_jwks_outage_fails_closed_and_reports_not_ready(jwks, ec_key):
    jwks["status"] = 503
    assert _run(signing_keys.refresh()) is False
    _rejected(_token(ec_key))
    fresh = SupabaseSigningKeys(min_refresh_interval=0)
    fresh.transport = signing_keys.transport
    assert _run(fresh.refresh()) is False

    ready, checks = _run(readiness())
    assert ready is False and checks["auth"] == "unavailable"


@pytest.mark.parametrize("app_env", ["staging", "production"])
def test_development_shortcuts_are_unavailable_with_real_keys(jwks, monkeypatch, app_env):
    monkeypatch.setattr(settings, "app_env", app_env)
    verifier = JwtAuthVerifier()
    verifier.register_dev_user("registered-dev-token", AuthenticatedUser(user_id="dev-user"))
    for token in ("usr_attacker", "dev_attacker", f"jwt_token_{USER_ID}", "registered-dev-token"):
        with pytest.raises(HTTPException) as exc:
            verifier.verify_token(f"Bearer {token}")
        assert exc.value.status_code == 401


# ── Key rotation ─────────────────────────────────────────────────────────────

def _after_min_refresh_interval():
    """Pretends the last JWKS fetch happened longer ago than the refetch limit."""
    signing_keys._last_attempt = time.monotonic() - signing_keys.min_refresh_interval - 1


def test_rotated_in_signing_key_is_fetched_and_accepted(jwks, ec_key):
    client = TestClient(app)
    assert client.get("/v1/guest/quota", headers={"Authorization": f"Bearer {_token(ec_key)}"}).status_code == 400
    assert jwks["calls"] == 1

    # Supabase publishes the new key (rotation); the old one stays listed for a while.
    new_key = ec.generate_private_key(ec.SECP256R1())
    jwks["document"] = {"keys": [_jwk(ec_key), _jwk(new_key, kid="signing-key-2")]}
    _after_min_refresh_interval()

    resp = client.get("/v1/guest/quota", headers={"Authorization": f"Bearer {_token(new_key, kid='signing-key-2')}"})
    assert resp.status_code == 400  # authenticated (guests-only endpoint)
    assert jwks["calls"] == 2       # the unknown key id triggered exactly one refetch
    assert client.get("/v1/guest/quota", headers={"Authorization": f"Bearer {_token(ec_key)}"}).status_code == 400


def test_revoked_signing_key_is_rejected_once_the_cache_expires(jwks, ec_key, monkeypatch):
    client = TestClient(app)
    assert client.get("/v1/guest/quota", headers={"Authorization": f"Bearer {_token(ec_key)}"}).status_code == 400

    new_key = ec.generate_private_key(ec.SECP256R1())
    jwks["document"] = {"keys": [_jwk(new_key, kid="signing-key-2")]}  # old key revoked
    monkeypatch.setattr(settings, "supabase_jwks_cache_seconds", 0)
    _after_min_refresh_interval()

    resp = client.get("/v1/guest/quota", headers={"Authorization": f"Bearer {_token(ec_key)}"})
    assert resp.status_code == 401
    assert jwks["calls"] == 2


# ── Supabase API keys are never user sessions ────────────────────────────────

LEGACY_SECRET = "legacy-hs256-secret-that-is-long-enough-123"


@pytest.mark.parametrize("role", ["service_role", "anon"])
def test_legacy_supabase_api_keys_signed_with_the_real_secret_are_rejected(jwks, monkeypatch, role):
    """The legacy anon/service_role keys are JWTs signed with the project's own
    JWT secret. Neither may be used as a signed-in user's session."""
    monkeypatch.setattr(settings, "supabase_jwt_secret", LEGACY_SECRET)
    now = int(time.time())
    legacy_api_key = jwt.encode(
        {"iss": "supabase", "ref": "project-ref", "role": role, "iat": now, "exp": now + 10 * 365 * 86400},
        LEGACY_SECRET, algorithm="HS256",
    )
    _rejected(legacy_api_key)
    # Even with the right issuer and audience, a service-role or anon role is refused.
    _rejected(jwt.encode(_claims(role=role), LEGACY_SECRET, algorithm="HS256"))

    resp = TestClient(app).get("/v1/account/me", headers={"Authorization": f"Bearer {legacy_api_key}"})
    assert resp.status_code == 401


@pytest.mark.parametrize("value", [
    "sb_secret_SENTINEL-fake-0123456789abcdef",
    "sb_publishable_SENTINEL-fake-0123456789abcdef",
])
def test_new_supabase_api_keys_are_rejected_as_sessions(jwks, value):
    _rejected(value)
    resp = TestClient(app).post("/v1/account/delete", json={"confirm_phrase": "DELETE MY ACCOUNT"},
                                headers={"Authorization": f"Bearer {value}"})
    assert resp.status_code == 401
    assert value not in resp.text
