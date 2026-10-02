"""
Account deletion: Flutter -> POST/DELETE /v1/account/delete -> Supabase Auth
Admin API -> database cleanup.

- Only the caller's own account, identified by the verified token subject, can
  be deleted; ids in the request are ignored and developer API keys are refused.
- The Supabase login is deleted first. If that fails, or the admin credential is
  missing in staging/production, nothing is deleted and the user can retry.
- New sb_secret_ keys go in the apikey header only; the legacy service_role
  JWT is also sent as the bearer token.
- Neither the admin key nor the Admin API response body is ever logged or returned.
"""

import asyncio
import logging
import time
import uuid

import httpx
import jwt
import pytest
from fastapi.testclient import TestClient

import backend.app.api.account as account_module
from backend.app.api.account import (
    SupabaseAuthDeletionError,
    _supabase_admin_headers,
    account_store,
    delete_supabase_auth_user,
)
from backend.app.config import settings
from backend.app.main import app
from backend.app.security.api_key_service import api_key_service

SUPABASE_URL = "https://project-ref.supabase.co"
ISSUER = f"{SUPABASE_URL}/auth/v1"
JWT_SECRET = "legacy-hs256-secret-that-is-long-enough-123"
SECRET_KEY = "sb_secret_SENTINEL-admin-key-0123456789"
LEGACY_SERVICE_ROLE_KEY = "eyJSENTINEL.service-role.jwt-0123456789"
CONFIRM = {"confirm_phrase": "DELETE MY ACCOUNT"}

client = TestClient(app)


def _run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def _token(sub, **overrides):
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated",
              "exp": int(time.time()) + 3600, "iat": int(time.time())}
    claims.update(overrides)
    claims = {k: v for k, v in claims.items() if v is not None}
    return {"Authorization": "Bearer " + jwt.encode(claims, JWT_SECRET, algorithm="HS256")}


class AdminApi:
    """Stands in for httpx.AsyncClient inside account.py and records every call."""

    def __init__(self):
        self.calls = []
        self.status = 204
        self.body = ""
        self.error = None

    def client_class(self):
        api = self

        class _Client:
            def __init__(self, *args, **kwargs):
                pass

            async def __aenter__(self):
                return self

            async def __aexit__(self, *args):
                return False

            async def delete(self, url, headers=None):
                api.calls.append({"url": url, "headers": dict(headers or {})})
                if api.error is not None:
                    raise api.error
                return httpx.Response(api.status, text=api.body)

        return _Client


@pytest.fixture
def admin_api(monkeypatch):
    api = AdminApi()
    monkeypatch.setattr(account_module.httpx, "AsyncClient", api.client_class())
    return api


@pytest.fixture
def staging(monkeypatch):
    """Hardened (staging) with legacy HS256 verification and the new secret key."""
    monkeypatch.setattr(settings, "app_env", "staging")
    monkeypatch.setattr(settings, "supabase_url", SUPABASE_URL)
    monkeypatch.setattr(settings, "supabase_jwt_secret", JWT_SECRET)
    for name in ("supabase_jwt_public_key", "supabase_jwt_algorithm", "supabase_jwt_issuer",
                 "supabase_jwks_url", "supabase_service_role_key"):
        monkeypatch.setattr(settings, name, None)
    monkeypatch.setattr(settings, "supabase_jwt_audience", "authenticated")
    monkeypatch.setattr(settings, "supabase_secret_key", SECRET_KEY)
    account_store.reset_for_test()
    yield
    account_store.reset_for_test()


def _seed(user_id):
    account_store.add_collection_item(user_id, {"id": str(uuid.uuid4()), "coin_name": "Kept coin",
                                                "country": "France", "denomination": "1 Franc"})
    account_store.record_consent(user_id, "1.0.0", "1.0.0")


def _data_intact(user_id):
    return (len(account_store.get_collection_items(user_id)) == 1
            and account_store.get_consent(user_id) is not None)


# ─── Admin API request shape ─────────────────────────────────────────────────

def test_new_secret_key_is_sent_only_in_the_apikey_header():
    assert _supabase_admin_headers(SECRET_KEY) == {"apikey": SECRET_KEY}


def test_legacy_service_role_key_is_also_sent_as_bearer():
    assert _supabase_admin_headers(LEGACY_SERVICE_ROLE_KEY) == {
        "apikey": LEGACY_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {LEGACY_SERVICE_ROLE_KEY}",
    }


def test_new_secret_key_is_preferred_over_the_legacy_key(monkeypatch, admin_api):
    monkeypatch.setattr(settings, "supabase_url", SUPABASE_URL)
    monkeypatch.setattr(settings, "supabase_secret_key", SECRET_KEY)
    monkeypatch.setattr(settings, "supabase_service_role_key", LEGACY_SERVICE_ROLE_KEY)
    user_id = str(uuid.uuid4())

    assert _run(delete_supabase_auth_user(user_id)) is True
    assert admin_api.calls == [{"url": f"{ISSUER}/admin/users/{user_id}", "headers": {"apikey": SECRET_KEY}}]


def test_non_uuid_user_id_never_reaches_the_admin_api(monkeypatch, admin_api):
    monkeypatch.setattr(settings, "supabase_url", SUPABASE_URL)
    monkeypatch.setattr(settings, "supabase_secret_key", SECRET_KEY)
    for bad in ("usr_alice", "../../admin/users", f"{uuid.uuid4()}/factors", ""):
        with pytest.raises(SupabaseAuthDeletionError):
            _run(delete_supabase_auth_user(bad))
    assert admin_api.calls == []


def test_missing_credential_outside_hardened_mode_is_an_explicit_skip(monkeypatch, admin_api):
    monkeypatch.setattr(settings, "supabase_secret_key", None)
    monkeypatch.setattr(settings, "supabase_service_role_key", None)
    assert _run(delete_supabase_auth_user(str(uuid.uuid4()))) is False
    assert admin_api.calls == []


# ─── Endpoint: own account only ──────────────────────────────────────────────

def test_user_deletes_own_login_and_data(staging, admin_api):
    user_id = str(uuid.uuid4())
    _seed(user_id)

    resp = client.post("/v1/account/delete", json=CONFIRM, headers=_token(user_id))

    assert resp.status_code == 200, resp.text
    assert resp.json()["user_id"] == user_id
    assert resp.json()["items_purged"]["supabase_auth_users"] == 1
    assert resp.json()["items_purged"]["collection_items"] == 1
    assert [c["url"] for c in admin_api.calls] == [f"{ISSUER}/admin/users/{user_id}"]
    assert account_store.get_collection_items(user_id) == []


def test_ids_in_the_request_are_ignored(staging, admin_api):
    caller, victim = str(uuid.uuid4()), str(uuid.uuid4())
    _seed(victim)

    resp = client.request(
        "DELETE", "/v1/account/delete",
        json={**CONFIRM, "user_id": victim, "id": victim, "sub": victim},
        params={"user_id": victim},
        headers=_token(caller),
    )

    assert resp.status_code == 200, resp.text
    assert resp.json()["user_id"] == caller
    assert [c["url"] for c in admin_api.calls] == [f"{ISSUER}/admin/users/{caller}"]
    assert _data_intact(victim)


def test_developer_api_key_cannot_delete_an_account(staging, admin_api):
    owner = str(uuid.uuid4())
    _seed(owner)
    key = api_key_service.generate_key(owner, name="test key").raw_api_key

    resp = client.post("/v1/account/delete", json=CONFIRM, headers={"X-API-Key": key})

    assert resp.status_code == 403
    assert admin_api.calls == []
    assert _data_intact(owner)


@pytest.mark.parametrize(
    "overrides",
    [
        {"role": "service_role"},                      # legacy service-role JWT as a session
        {"role": "anon"},                              # anon key JWT
        {"is_anonymous": True},                        # Supabase anonymous sign-in
        {"exp": int(time.time()) - 60},                # expired
        {"iss": "https://attacker.example/auth/v1"},   # wrong issuer
        {"aud": "service"},                            # wrong audience
    ],
)
def test_non_user_sessions_are_rejected(staging, admin_api, overrides):
    user_id = str(uuid.uuid4())
    _seed(user_id)

    resp = client.post("/v1/account/delete", json=CONFIRM, headers=_token(user_id, **overrides))

    assert resp.status_code == 401
    assert admin_api.calls == []
    assert _data_intact(user_id)


def test_signed_out_caller_is_rejected(staging, admin_api):
    assert client.post("/v1/account/delete", json=CONFIRM).status_code == 401
    assert admin_api.calls == []


# ─── Endpoint: nothing is deleted unless the login is deleted ────────────────

def test_missing_admin_credential_in_hardened_mode_deletes_nothing(staging, admin_api, monkeypatch):
    # Production (which also needs a database) is covered in test_postgres_guest_integration.py.
    monkeypatch.setattr(settings, "supabase_secret_key", None)
    monkeypatch.setattr(settings, "supabase_service_role_key", None)
    user_id = str(uuid.uuid4())
    _seed(user_id)

    resp = client.post("/v1/account/delete", json=CONFIRM, headers=_token(user_id))

    assert resp.status_code == 503
    assert "Nothing was deleted" in resp.json()["detail"]
    assert admin_api.calls == []
    assert _data_intact(user_id)


@pytest.mark.parametrize("status_code", [400, 401, 403, 500, 503])
def test_admin_api_failure_deletes_nothing(staging, admin_api, caplog, status_code):
    admin_api.status = status_code
    admin_api.body = '{"msg":"SENTINEL-response-body"}'
    user_id = str(uuid.uuid4())
    _seed(user_id)

    with caplog.at_level(logging.DEBUG):
        resp = client.post("/v1/account/delete", json=CONFIRM, headers=_token(user_id))

    assert resp.status_code == 502
    assert "Nothing was deleted" in resp.json()["detail"]
    assert _data_intact(user_id)
    for leaked in (SECRET_KEY, "SENTINEL-response-body"):
        assert leaked not in resp.text
        assert leaked not in caplog.text


def test_unreachable_admin_api_deletes_nothing(staging, admin_api, caplog):
    admin_api.error = httpx.ConnectError(f"connection refused apikey={SECRET_KEY}")
    user_id = str(uuid.uuid4())
    _seed(user_id)

    with caplog.at_level(logging.DEBUG):
        resp = client.post("/v1/account/delete", json=CONFIRM, headers=_token(user_id))

    assert resp.status_code == 502
    assert _data_intact(user_id)
    assert SECRET_KEY not in caplog.text


def test_already_deleted_login_counts_as_deleted(staging, admin_api):
    """A retry after a partial failure finds the login gone (404) and finishes the cleanup."""
    admin_api.status = 404
    user_id = str(uuid.uuid4())
    _seed(user_id)

    resp = client.post("/v1/account/delete", json=CONFIRM, headers=_token(user_id))

    assert resp.status_code == 200
    assert resp.json()["items_purged"]["supabase_auth_users"] == 1
    assert account_store.get_collection_items(user_id) == []


def test_wrong_confirmation_phrase_deletes_nothing(staging, admin_api):
    user_id = str(uuid.uuid4())
    _seed(user_id)

    resp = client.post("/v1/account/delete", json={"confirm_phrase": "delete"}, headers=_token(user_id))

    assert resp.status_code == 400
    assert admin_api.calls == []
    assert _data_intact(user_id)
