"""
P0 regression tests: authentication and per-user data isolation.

- Development bearer shortcuts (usr_*/dev_*/jwt_token_*), the mock vision
  provider and the offline catalogue fixture exist only when APP_ENV is
  development or test. APP_ENV alone decides: it defaults to production, and
  hosting-platform variables (Cloud Run's K_SERVICE, Render's RENDER, Railway,
  Fly.io) have no effect either way.
- A user cannot read or modify another user's collection, scan history,
  quota, profile, consent or entitlement by manipulating IDs.
"""

import io
import uuid

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from backend.app.api import recognition as recognition_module
from backend.app.api.account import account_store
from backend.app.api.webhooks import webhook_state
from fastapi import HTTPException

from backend.app.config import Settings, settings
from backend.app.main import app
from backend.app.security.jwt_auth import JwtAuthVerifier
from backend.app.security.rate_limit import SubscriptionTier

client = TestClient(app)


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _jpeg_bytes(size: int = 400) -> bytes:
    img = Image.new("RGB", (size, size), color=(120, 110, 90))
    for x in range(0, size, 8):
        for y in range(size):
            img.putpixel((x, y), (250, 250, 250))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=92)
    return buf.getvalue()


# ─── Development shortcuts are local-only ────────────────────────────────────

def test_dev_tokens_work_in_local_development(monkeypatch):
    monkeypatch.setattr(settings, "app_env", "development")
    user = JwtAuthVerifier().verify_token("Bearer usr_local_dev")
    assert user is not None and user.user_id == "usr_local_dev"


@pytest.mark.parametrize("app_env", ["staging", "production"])
def test_dev_tokens_rejected_outside_development(monkeypatch, app_env):
    # Staging is hardened like production: an unverifiable token is a 401, not
    # a silent downgrade to guest.
    monkeypatch.setattr(settings, "app_env", app_env)
    monkeypatch.setattr(settings, "supabase_jwt_secret", "a-real-secret-that-is-long-enough-123456")
    verifier = JwtAuthVerifier()
    with pytest.raises(HTTPException) as exc:
        verifier.verify_token("Bearer usr_attacker")
    assert exc.value.status_code == 401


PLATFORM_VARIABLES = {
    "K_SERVICE": "coinscan-backend",           # Cloud Run
    "RENDER": "true",                          # Render
    "RAILWAY_ENVIRONMENT": "production",       # Railway
    "FLY_APP_NAME": "coinscan-api",            # Fly.io
}


def _default_app_env() -> str:
    """The APP_ENV a deployment gets when it does not set one."""
    return Settings(_env_file=None).app_env


def test_app_env_defaults_to_production_when_unset(monkeypatch):
    monkeypatch.delenv("APP_ENV", raising=False)
    assert _default_app_env() == "production"
    for name, value in PLATFORM_VARIABLES.items():
        monkeypatch.setenv(name, value)
    assert _default_app_env() == "production"


@pytest.mark.parametrize("platform_var", sorted(PLATFORM_VARIABLES))
def test_dev_tokens_rejected_when_app_env_is_unset_on_any_platform(monkeypatch, platform_var):
    """A deployment that forgets APP_ENV is hardened, whatever platform it runs on."""
    monkeypatch.delenv("APP_ENV", raising=False)
    monkeypatch.setenv(platform_var, PLATFORM_VARIABLES[platform_var])
    monkeypatch.setattr(settings, "app_env", _default_app_env())
    monkeypatch.setattr(settings, "supabase_jwt_secret", "a-real-secret-that-is-long-enough-123456")
    assert settings.dev_features_enabled is False

    with pytest.raises(HTTPException) as exc:
        JwtAuthVerifier().verify_token("Bearer usr_attacker")
    assert exc.value.status_code == 401
    resp = client.get("/v1/account/me", headers=_bearer("usr_attacker"))
    assert resp.status_code == 401


@pytest.mark.parametrize("app_env", ["development", "staging", "production"])
def test_platform_variables_never_change_the_security_mode(monkeypatch, app_env):
    for name, value in PLATFORM_VARIABLES.items():
        monkeypatch.setenv(name, value)
    monkeypatch.setattr(settings, "app_env", app_env)
    assert settings.dev_features_enabled is (app_env == "development")
    assert settings.is_hardened is (app_env != "development")


@pytest.mark.parametrize("app_env", ["staging", "production"])
def test_mock_vision_provider_unavailable_when_hardened(monkeypatch, app_env):
    monkeypatch.setattr(settings, "app_env", app_env)
    monkeypatch.setattr(settings, "gemini_api_key", None)
    monkeypatch.setattr(settings, "openai_api_key", None)
    with pytest.raises(HTTPException) as exc:
        recognition_module.get_vision_provider()
    assert exc.value.status_code == 503

    # Staging end-to-end (production additionally needs a database to serve guests).
    if app_env == "staging":
        monkeypatch.setattr(settings, "guest_quota_hmac_secret", "staging-test-secret-0123456789abcdef")
        resp = client.post("/v1/recognition", files={"front_image": ("f.jpg", _jpeg_bytes(), "image/jpeg")})
        assert resp.status_code == 503


@pytest.mark.parametrize("app_env", ["staging", "production"])
def test_offline_catalogue_fixture_is_ignored_when_hardened(monkeypatch, app_env):
    monkeypatch.setattr(settings, "app_env", app_env)
    monkeypatch.setattr(settings, "numista_offline_fixture", True)
    assert (settings.numista_offline_fixture and settings.dev_features_enabled) is False


# ─── Per-user isolation (ID manipulation) ────────────────────────────────────

def _accept_terms(token: str):
    resp = client.post(
        "/v1/account/legal/consent",
        json={"terms_version": settings.required_terms_version, "privacy_version": settings.required_privacy_version},
        headers=_bearer(token),
    )
    assert resp.status_code == 200


@pytest.fixture
def two_users(monkeypatch):
    monkeypatch.delenv("K_SERVICE", raising=False)
    monkeypatch.delenv("RENDER", raising=False)
    account_store.reset_for_test()
    webhook_state.reset_for_test()
    alice, bob = f"usr_alice_{uuid.uuid4().hex[:8]}", f"usr_bob_{uuid.uuid4().hex[:8]}"
    _accept_terms(alice)
    _accept_terms(bob)
    return alice, bob


def test_collection_items_cannot_be_read_or_deleted_by_another_user(two_users):
    alice, bob = two_users
    created = client.post(
        "/v1/collection",
        json={"coin_name": "Alice coin", "country": "France", "denomination": "5 Francs", "user_id": bob},
        headers=_bearer(alice),
    )
    assert created.status_code == 200
    item_id = created.json()["id"]
    # A user_id smuggled into the body is ignored; ownership comes from the token
    assert created.json()["user_id"] == alice

    assert client.get("/v1/collection", headers=_bearer(bob)).json() == []
    assert client.delete(f"/v1/collection/{item_id}", headers=_bearer(bob)).status_code == 404
    assert len(client.get("/v1/collection", headers=_bearer(alice)).json()) == 1


def test_bob_cannot_overwrite_alices_item_by_reusing_its_id(two_users):
    alice, bob = two_users
    item_id = client.post(
        "/v1/collection",
        json={"coin_name": "Alice coin", "country": "France", "denomination": "5 Francs"},
        headers=_bearer(alice),
    ).json()["id"]

    client.post(
        "/v1/collection",
        json={"id": item_id, "coin_name": "Bob overwrite", "country": "X", "denomination": "Y"},
        headers=_bearer(bob),
    )
    alice_items = client.get("/v1/collection", headers=_bearer(alice)).json()
    assert [i["coin_name"] for i in alice_items] == ["Alice coin"]


def test_scan_history_is_isolated(two_users, monkeypatch):
    alice, bob = two_users

    class _Catalogue(recognition_module.NumistaClient):
        def __init__(self):
            super().__init__(offline_fixture=True)

        async def search_types(self, query, category="coin", count=5):
            return self._get_fallback_catalog("morgan")

    monkeypatch.setattr(recognition_module, "numista_client", _Catalogue())
    scan = client.post(
        "/v1/recognition",
        files={"front_image": ("f.jpg", _jpeg_bytes(), "image/jpeg")},
        headers=_bearer(alice),
    )
    assert scan.status_code == 200

    assert len(client.get("/v1/account/history", headers=_bearer(alice)).json()) == 1
    assert client.get("/v1/account/history", headers=_bearer(bob)).json() == []


def test_profile_quota_consent_and_entitlement_are_per_token(two_users):
    alice, bob = two_users
    webhook_state.set_user_tier(alice, SubscriptionTier.PRO)

    assert client.get("/v1/account/me", headers=_bearer(bob)).json()["id"] == bob
    assert client.get("/v1/account/me", headers=_bearer(bob)).json()["tier"] == "free"
    assert client.get("/v1/account/quota", headers=_bearer(bob)).json()["user_id"] == bob
    assert client.get("/v1/account/quota", headers=_bearer(bob)).json()["tier"] == "free"
    assert client.get("/v1/account/legal/consent", headers=_bearer(bob)).json()["user_id"] == bob
    # Query parameters naming another user are ignored
    assert client.get(f"/v1/account/me?user_id={alice}", headers=_bearer(bob)).json()["id"] == bob


def test_export_contains_only_own_data(two_users):
    alice, bob = two_users
    client.post(
        "/v1/collection",
        json={"coin_name": "Alice only", "country": "France", "denomination": "1 Franc"},
        headers=_bearer(alice),
    )
    export = client.get("/v1/account/export", headers=_bearer(bob)).json()
    assert export["user_profile"]["id"] == bob
    assert export["collection_items"] == []
    assert "Alice only" not in str(export)


def test_deleting_one_account_does_not_touch_another(two_users):
    alice, bob = two_users
    client.post(
        "/v1/collection",
        json={"coin_name": "Alice keeps this", "country": "France", "denomination": "1 Franc"},
        headers=_bearer(alice),
    )
    resp = client.post("/v1/account/delete", json={"confirm_phrase": "DELETE MY ACCOUNT"}, headers=_bearer(bob))
    assert resp.status_code == 200
    assert resp.json()["user_id"] == bob
    assert len(client.get("/v1/collection", headers=_bearer(alice)).json()) == 1


@pytest.mark.parametrize(
    "method,path",
    [
        ("get", "/v1/collection"),
        ("get", "/v1/account/me"),
        ("get", "/v1/account/quota"),
        ("get", "/v1/account/history"),
        ("get", "/v1/account/export"),
        ("post", "/v1/account/delete"),
    ],
)
def test_protected_endpoints_reject_anonymous_callers(method, path):
    resp = getattr(client, method)(path)
    assert resp.status_code == 401


def test_webhook_cannot_be_called_without_secret():
    original = settings.revenuecat_webhook_secret
    settings.revenuecat_webhook_secret = "configured-secret"
    try:
        resp = client.post(
            "/v1/webhooks/revenuecat",
            json={"event": {"id": "evt_forged", "type": "INITIAL_PURCHASE", "app_user_id": "usr_x",
                            "entitlement_ids": ["pro"]}},
            headers={"Authorization": "Bearer wrong"},
        )
        assert resp.status_code == 401
        assert webhook_state.get_user_tier("usr_x") == SubscriptionTier.FREE
    finally:
        settings.revenuecat_webhook_secret = original
