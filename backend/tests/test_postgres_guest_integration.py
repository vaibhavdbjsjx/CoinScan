"""
PostgreSQL integration tests for guest scanning and account isolation.

These run against a real PostgreSQL server using the repository's migrations
(UUID primary keys, foreign keys to auth.users, the guest_scan_usage table), so
they catch the class of failure SQLite cannot: a non-UUID identity reaching a
UUID column. Set TEST_POSTGRES_URL to an asyncpg URL to run them, e.g.

    TEST_POSTGRES_URL="postgresql+asyncpg://postgres@/postgres?host=/path/to/socket-dir"

Supabase provides the `auth` schema and the `anon`/`authenticated` roles; a
minimal stand-in (auth.users, auth.uid(), the roles and Supabase's default table
grants) is created here so the real foreign keys, RLS policies and grants load. The two
`CREATE EXTENSION` lines are skipped: gen_random_uuid() is built into
PostgreSQL 13+, and both extensions are preinstalled on Supabase.
"""

import asyncio
import io
import logging
import os
import re
import uuid
from pathlib import Path

import asyncpg
import httpx
import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool
from starlette.requests import Request

import backend.app.db.session as session_module
from backend.app.api import recognition as recognition_module
from backend.app.config import settings
from backend.app.main import app
from backend.app.security.guest_quota import INSTALL_ID_HEADER, guest_allowance
from backend.app.services.numista.client import NumistaClient, NumistaTypeDetail
from backend.app.services.recognition.vision_provider import VisionProvider, VisionProviderError

PG_URL = os.environ.get("TEST_POSTGRES_URL")
pytestmark = pytest.mark.skipif(
    not PG_URL, reason="TEST_POSTGRES_URL is not set: PostgreSQL integration tests were not run"
)

MIGRATIONS = sorted((Path(__file__).resolve().parents[1] / "migrations").glob("*.sql"))
AUTH_STUB = """
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (id uuid PRIMARY KEY);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS 'select null::uuid';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END
$$;
GRANT USAGE ON SCHEMA public TO anon, authenticated;
-- Like Supabase: new tables in public are granted to the client roles by default.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;
"""
DB_NAME = f"coinscan_it_{uuid.uuid4().hex[:8]}"


def _conn_kwargs(database: str) -> dict:
    url = make_url(PG_URL)
    kwargs = {"user": url.username or "postgres", "database": database}
    host = url.query.get("host") or url.host
    if host:
        kwargs["host"] = host
    if url.port:
        kwargs["port"] = url.port
    if url.password:
        kwargs["password"] = url.password
    return kwargs


def _run(coro):
    """Runs a coroutine on a private loop. Unlike asyncio.run() this leaves the
    thread's current event loop alone, which later tests rely on (Python 3.9)."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


async def _admin(sql: str) -> None:
    conn = await asyncpg.connect(**_conn_kwargs(make_url(PG_URL).database or "postgres"))
    try:
        await conn.execute(sql)
    finally:
        await conn.close()


async def _fetch(sql: str, *args):
    conn = await asyncpg.connect(**_conn_kwargs(DB_NAME))
    try:
        return await conn.fetch(sql, *args)
    finally:
        await conn.close()


def fetch(sql: str, *args):
    return _run(_fetch(sql, *args))


def scalar(sql: str, *args):
    rows = fetch(sql, *args)
    return rows[0][0] if rows else None


@pytest.fixture(scope="module")
def database():
    async def create():
        await _admin(f'DROP DATABASE IF EXISTS "{DB_NAME}"')
        await _admin(f'CREATE DATABASE "{DB_NAME}"')
        conn = await asyncpg.connect(**_conn_kwargs(DB_NAME))
        try:
            await conn.execute(AUTH_STUB)
            for path in MIGRATIONS:
                sql = re.sub(r'CREATE EXTENSION IF NOT EXISTS "[^"]+";', "", path.read_text())
                await conn.execute(sql)
        finally:
            await conn.close()

    _run(create())
    yield str(make_url(PG_URL).set(database=DB_NAME))
    _run(_admin(f'DROP DATABASE IF EXISTS "{DB_NAME}" WITH (FORCE)'))


@pytest.fixture
def pg(database, monkeypatch):
    """Points the app at the test database with a NullPool engine (safe across event loops)."""
    fetch(
        "TRUNCATE auth.users, public.guest_scan_usage, public.subscription_events, "
        "public.security_events, public.feedback RESTART IDENTITY CASCADE"
    )
    engine = create_async_engine(database, poolclass=NullPool)
    monkeypatch.setattr(settings, "database_url", database)
    monkeypatch.setattr(settings, "app_env", "development")
    monkeypatch.setattr(settings, "trusted_proxy_hops", 0)
    monkeypatch.delenv("K_SERVICE", raising=False)
    monkeypatch.delenv("RENDER", raising=False)
    monkeypatch.setattr(session_module, "_engine", engine)
    monkeypatch.setattr(
        session_module,
        "_session_factory",
        async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False),
    )
    monkeypatch.setattr(recognition_module, "numista_client", _Catalogue())
    guest_allowance.store.reset_for_test()
    yield
    _run(engine.dispose())


class _Catalogue(NumistaClient):
    def __init__(self):
        super().__init__(api_key="unused")

    async def search_types(self, query, category="coin", count=5):
        return [NumistaTypeDetail(id=1492, title="1 Dollar", country="United States",
                                  denomination="1 Dollar", min_year=1878, max_year=1921)]


class _FailingVision(VisionProvider):
    async def analyze_coin_images(self, front_b64, reverse_b64=None, edge_b64=None, detected_text_hints=None):
        raise VisionProviderError("Gemini", "provider returned an error", 503)


def _jpeg() -> bytes:
    img = Image.new("RGB", (400, 400), color=(120, 110, 90))
    for x in range(0, 400, 8):
        for y in range(400):
            img.putpixel((x, y), (250, 250, 250))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=92)
    return buf.getvalue()


IMAGE = _jpeg()


def _scan(client, headers=None):
    return client.post(
        "/v1/recognition",
        files={"front_image": ("f.jpg", IMAGE, "image/jpeg")},
        headers=headers or {},
    )


def _guest(install_id: str) -> dict:
    return {INSTALL_ID_HEADER: install_id}


def _succeeded(resp) -> bool:
    return resp.status_code == 200 and resp.json()["status"] not in ("error", "unavailable")


def _add_auth_user() -> str:
    user_id = str(uuid.uuid4())
    fetch("INSERT INTO auth.users (id) VALUES ($1)", uuid.UUID(user_id))
    return user_id


def _bearer(user_id: str) -> dict:
    # Local-development token form resolving to this UUID (see jwt_auth.py).
    return {"Authorization": f"Bearer jwt_token_{user_id}"}


# 1-6 ────────────────────────────────────────────────────────────────────────

def test_guest_scans_against_real_uuid_schema_and_limit(pg):
    client = TestClient(app)
    install = str(uuid.uuid4())

    first = _scan(client, _guest(install))
    assert _succeeded(first), first.text                       # 1: no UUID error
    assert first.json()["processingMetadata"]["guest"] is True
    assert first.json()["processingMetadata"]["guest_scans_remaining"] == 1
    assert scalar("SELECT max(scan_count) FROM guest_scan_usage WHERE key_kind='install'") == 1  # 4

    second = _scan(client, _guest(install))
    assert _succeeded(second)                                  # 5
    assert second.json()["processingMetadata"]["guest_scans_remaining"] == 0

    third = _scan(client, _guest(install))
    assert third.status_code == 429                            # 6
    assert third.json()["detail"]["error"] == "guest_daily_limit_reached"
    assert scalar("SELECT max(scan_count) FROM guest_scan_usage WHERE key_kind='install'") == 2

    assert scalar("SELECT count(*) FROM public.users") == 0          # 2
    assert scalar("SELECT count(*) FROM public.scan_usage") == 0     # 3
    assert scalar("SELECT count(*) FROM public.scan_history") == 0


def test_guest_without_install_id_uses_network_allowance(pg):
    client = TestClient(app)
    assert _succeeded(_scan(client))
    assert _succeeded(_scan(client))
    assert _scan(client).status_code == 429
    assert scalar("SELECT count(*) FROM guest_scan_usage WHERE key_kind='install'") == 0


# 7 ──────────────────────────────────────────────────────────────────────────

def test_failed_recognition_does_not_consume_guest_quota(pg, monkeypatch):
    monkeypatch.setattr(recognition_module, "get_vision_provider", lambda: _FailingVision())
    client = TestClient(app)
    install = str(uuid.uuid4())

    for _ in range(3):
        resp = _scan(client, _guest(install))
        assert resp.status_code == 200 and resp.json()["status"] == "error"

    assert (scalar("SELECT coalesce(sum(scan_count), 0) FROM guest_scan_usage") or 0) == 0


def test_catalogue_outage_does_not_consume_guest_quota(pg, monkeypatch):
    monkeypatch.setattr(recognition_module, "numista_client", NumistaClient(api_key=None))
    resp = _scan(TestClient(app), _guest(str(uuid.uuid4())))
    assert resp.json()["status"] == "unavailable"
    assert (scalar("SELECT coalesce(sum(scan_count), 0) FROM guest_scan_usage") or 0) == 0


# 8 ──────────────────────────────────────────────────────────────────────────

def _request(ip: str, install: str = None) -> Request:
    headers = [(INSTALL_ID_HEADER.lower().encode(), install.encode())] if install else []
    return Request({"type": "http", "method": "POST", "path": "/", "query_string": b"",
                    "headers": headers, "client": (ip, 40000)})


@pytest.mark.asyncio
async def test_concurrent_reservations_cannot_exceed_limit(pg):
    install = str(uuid.uuid4())

    async def attempt():
        slot = await guest_allowance.reserve(_request("192.0.2.10", install))
        await slot.commit()
        return True

    results = await asyncio.gather(*[attempt() for _ in range(12)], return_exceptions=True)
    assert sum(1 for r in results if r is True) == 2
    rows = await _fetch("SELECT key_kind, scan_count FROM guest_scan_usage ORDER BY key_kind")
    assert [(r["key_kind"], r["scan_count"]) for r in rows] == [("install", 2), ("network", 2)]


@pytest.mark.asyncio
async def test_concurrent_http_scans_cannot_exceed_limit(pg):
    install = str(uuid.uuid4())
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://coinscan.test") as client:
        responses = await asyncio.gather(*[
            client.post("/v1/recognition", files={"front_image": ("f.jpg", IMAGE, "image/jpeg")},
                        headers=_guest(install))
            for _ in range(6)
        ])
    ok = [r for r in responses if r.status_code == 200 and r.json()["status"] not in ("error", "unavailable")]
    limited = [r for r in responses if r.status_code == 429]
    assert len(ok) == 2 and len(limited) == 4
    assert (await _fetch("SELECT scan_count FROM guest_scan_usage WHERE key_kind='install'"))[0][0] == 2


# 9 ──────────────────────────────────────────────────────────────────────────

def test_different_guest_keys_are_isolated(pg):
    client = TestClient(app)
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    assert _succeeded(_scan(client, _guest(a)))
    assert _succeeded(_scan(client, _guest(a)))
    assert _scan(client, _guest(a)).status_code == 429
    assert _succeeded(_scan(client, _guest(b)))  # B's allowance is untouched by A


def test_network_ceiling_caps_rotating_install_ids(pg, monkeypatch):
    monkeypatch.setattr(settings, "guest_network_daily_scan_limit", 3)
    client = TestClient(app)
    outcomes = [_scan(client, _guest(str(uuid.uuid4()))).status_code for _ in range(5)]
    assert outcomes == [200, 200, 200, 429, 429]


# 10 ─────────────────────────────────────────────────────────────────────────

def test_raw_ip_and_install_id_are_never_persisted_or_logged(pg, monkeypatch, caplog):
    monkeypatch.setattr(settings, "trusted_proxy_hops", 1)
    ip, install = "198.51.100.23", str(uuid.uuid4())
    headers = {**_guest(install), "X-Forwarded-For": f"10.9.9.9, {ip}"}
    client = TestClient(app)
    caplog.set_level(logging.DEBUG)

    assert _succeeded(_scan(client, headers))
    client.post("/v1/feedback", json={"category": "other", "title": "Guest note",
                                      "description": "Feedback from a guest"}, headers=headers)

    tables = [r["table_name"] for r in fetch(
        "SELECT table_name FROM information_schema.tables WHERE table_schema='public'")]
    for table in tables:
        hits = scalar(f'SELECT count(*) FROM public."{table}" t WHERE t::text LIKE $1', f"%{ip}%")
        assert hits == 0, f"raw IP stored in {table}"
        hits = scalar(f'SELECT count(*) FROM public."{table}" t WHERE t::text LIKE $1', f"%{install}%")
        assert hits == 0, f"raw install id stored in {table}"
    assert scalar("SELECT count(*) FROM public.feedback WHERE client_ip IS NOT NULL") == 0
    assert scalar("SELECT count(*) FROM guest_scan_usage") == 2  # only keyed hashes
    assert all(len(h) == 64 for (h,) in fetch("SELECT key_hash FROM guest_scan_usage"))
    assert ip not in caplog.text and install not in caplog.text


# 11 ─────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "method,path",
    [
        ("get", "/v1/account/me"),
        ("get", "/v1/account/quota"),
        ("get", "/v1/account/history"),
        ("get", "/v1/account/export"),
        ("get", "/v1/account/legal/consent"),
        ("post", "/v1/account/legal/consent"),
        ("post", "/v1/account/delete"),
        ("delete", "/v1/account/delete"),
        ("get", "/v1/collection"),
        ("post", "/v1/collection"),
        ("delete", f"/v1/collection/{uuid.uuid4()}"),
    ],
)
def test_guests_cannot_reach_account_endpoints(pg, method, path):
    client = TestClient(app)
    kwargs = {}
    if method == "post" and "consent" in path:
        kwargs["json"] = {"terms_version": "1.0.0", "privacy_version": "1.0.0"}
    elif method == "post" and "collection" in path:
        kwargs["json"] = {"coin_name": "Coin", "country": "France", "denomination": "1 Franc"}
    elif method == "post":
        kwargs["json"] = {"confirm_phrase": "DELETE MY ACCOUNT"}
    resp = getattr(client, method)(path, headers=_guest(str(uuid.uuid4())), **kwargs)
    assert resp.status_code == 401
    assert scalar("SELECT count(*) FROM public.users") == 0


# 14 ─────────────────────────────────────────────────────────────────────────

def test_authenticated_scan_uses_account_quota_not_guest_allowance(pg):
    user_id = _add_auth_user()
    resp = _scan(TestClient(app), _bearer(user_id))

    assert _succeeded(resp), resp.text
    assert resp.json()["processingMetadata"]["guest"] is False
    assert scalar("SELECT scan_count FROM scan_usage WHERE user_id = $1", uuid.UUID(user_id)) == 1
    assert scalar("SELECT count(*) FROM scan_history WHERE user_id = $1", uuid.UUID(user_id)) == 1
    assert scalar("SELECT count(*) FROM guest_scan_usage") == 0


def test_signed_in_credential_without_account_uuid_cannot_reach_uuid_tables(pg):
    resp = _scan(TestClient(app), {"Authorization": "Bearer usr_local_dev_user"})
    assert resp.status_code == 403
    assert scalar("SELECT count(*) FROM public.users") == 0


# 15 ─────────────────────────────────────────────────────────────────────────

def test_account_data_isolation_on_postgres(pg):
    client = TestClient(app)
    alice, bob = _add_auth_user(), _add_auth_user()
    for uid in (alice, bob):
        r = client.post("/v1/account/legal/consent", headers=_bearer(uid),
                        json={"terms_version": settings.required_terms_version,
                              "privacy_version": settings.required_privacy_version})
        assert r.status_code == 200, r.text

    created = client.post("/v1/collection", headers=_bearer(alice),
                          json={"coin_name": "Alice coin", "country": "France", "denomination": "5 Francs"})
    assert created.status_code == 200, created.text
    item_id = created.json()["id"]

    assert client.get("/v1/collection", headers=_bearer(bob)).json() == []
    assert client.delete(f"/v1/collection/{item_id}", headers=_bearer(bob)).status_code == 404
    assert [i["coin_name"] for i in client.get("/v1/collection", headers=_bearer(alice)).json()] == ["Alice coin"]
    assert "Alice coin" not in str(client.get("/v1/account/export", headers=_bearer(bob)).json())


def test_guest_quota_status_endpoint(pg):
    client = TestClient(app)
    install = str(uuid.uuid4())
    assert client.get("/v1/guest/quota", headers=_guest(install)).json()["remaining"] == 2
    _scan(client, _guest(install))
    status = client.get("/v1/guest/quota", headers=_guest(install)).json()
    assert status["used"] == 1 and status["remaining"] == 1


# Account deletion in production mode ───────────────────────────────────────
# public.users references auth.users ON DELETE CASCADE, so deleting the Supabase
# login removes every user-owned row. The stand-in Admin API below deletes the
# auth.users row the way Supabase does.

DELETION_JWT_SECRET = "legacy-hs256-secret-that-is-long-enough-123"
DELETION_SUPABASE_URL = "https://project-ref.supabase.co"
USER_TABLES = ("users", "user_legal_consents", "collection_items")


def _production_token(user_id: str) -> dict:
    import time as _time
    import jwt as _jwt
    claims = {"sub": user_id, "aud": "authenticated", "iss": f"{DELETION_SUPABASE_URL}/auth/v1",
              "role": "authenticated", "exp": int(_time.time()) + 3600}
    return {"Authorization": "Bearer " + _jwt.encode(claims, DELETION_JWT_SECRET, algorithm="HS256")}


def _user_with_data(client) -> str:
    """Creates a user with consent and a collection item (development tokens)."""
    user_id = _add_auth_user()
    r = client.post("/v1/account/legal/consent", headers=_bearer(user_id),
                    json={"terms_version": settings.required_terms_version,
                          "privacy_version": settings.required_privacy_version})
    assert r.status_code == 200, r.text
    r = client.post("/v1/collection", headers=_bearer(user_id),
                    json={"coin_name": "Kept coin", "country": "France", "denomination": "1 Franc"})
    assert r.status_code == 200, r.text
    return user_id


def _rows(user_id: str) -> dict:
    uid = uuid.UUID(user_id)
    counts = {"auth.users": scalar("SELECT count(*) FROM auth.users WHERE id = $1", uid),
              "users": scalar("SELECT count(*) FROM public.users WHERE id = $1", uid)}
    for table in USER_TABLES[1:]:
        counts[table] = scalar(f"SELECT count(*) FROM public.{table} WHERE user_id = $1", uid)
    return counts


def _go_production(monkeypatch, admin_key):
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "supabase_url", DELETION_SUPABASE_URL)
    monkeypatch.setattr(settings, "supabase_jwt_secret", DELETION_JWT_SECRET)
    monkeypatch.setattr(settings, "supabase_jwt_audience", "authenticated")
    for name in ("supabase_jwt_public_key", "supabase_jwt_algorithm", "supabase_jwt_issuer",
                 "supabase_jwks_url", "supabase_service_role_key"):
        monkeypatch.setattr(settings, name, None)
    monkeypatch.setattr(settings, "supabase_secret_key", admin_key)


def _fake_admin_api(monkeypatch, status_code):
    import backend.app.api.account as account_module
    calls = []

    class _Client:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return False

        async def delete(self, url, headers=None):
            calls.append(url)
            if status_code in (200, 204):
                conn = await asyncpg.connect(**_conn_kwargs(DB_NAME))
                try:
                    await conn.execute("DELETE FROM auth.users WHERE id = $1",
                                       uuid.UUID(url.rsplit("/", 1)[1]))
                finally:
                    await conn.close()
            return httpx.Response(status_code, text="{}")

    monkeypatch.setattr(account_module.httpx, "AsyncClient", _Client)
    return calls


def test_production_account_deletion_removes_login_and_every_row(pg, monkeypatch):
    client = TestClient(app)
    alice, bob = _user_with_data(client), _user_with_data(client)
    _go_production(monkeypatch, "sb_secret_SENTINEL-admin-0123456789")
    calls = _fake_admin_api(monkeypatch, 200)

    resp = client.post("/v1/account/delete", json={"confirm_phrase": "DELETE MY ACCOUNT"},
                       headers=_production_token(alice))

    assert resp.status_code == 200, resp.text
    assert resp.json()["items_purged"]["supabase_auth_users"] == 1
    assert calls == [f"{DELETION_SUPABASE_URL}/auth/v1/admin/users/{alice}"]
    assert set(_rows(alice).values()) == {0}
    assert _rows(bob) == {"auth.users": 1, "users": 1, "user_legal_consents": 1, "collection_items": 1}


@pytest.mark.parametrize("admin_key,status_code,expected", [
    (None, 200, 503),                                           # credential missing
    ("sb_secret_SENTINEL-admin-0123456789", 500, 502),          # Admin API failed
    ("sb_secret_SENTINEL-admin-0123456789", 401, 502),          # wrong / revoked key
])
def test_production_account_deletion_failure_deletes_nothing(pg, monkeypatch, admin_key, status_code, expected):
    client = TestClient(app)
    user_id = _user_with_data(client)
    before = _rows(user_id)
    _go_production(monkeypatch, admin_key)
    _fake_admin_api(monkeypatch, status_code)

    resp = client.post("/v1/account/delete", json={"confirm_phrase": "DELETE MY ACCOUNT"},
                       headers=_production_token(user_id))

    assert resp.status_code == expected
    assert before == {"auth.users": 1, "users": 1, "user_legal_consents": 1, "collection_items": 1}
    assert _rows(user_id) == before


# Guest usage table: schema, privileges, UTC day ─────────────────────────────

GUEST_MIGRATION = next(p for p in MIGRATIONS if p.name.endswith("_guest_scan_usage.sql"))
VALID_HASH = "a" * 64


async def _execute(sql: str, *args, role: str = None):
    conn = await asyncpg.connect(**_conn_kwargs(DB_NAME))
    try:
        async with conn.transaction():
            if role:
                await conn.execute(f"SET LOCAL ROLE {role}")
            return await conn.execute(sql, *args)
    finally:
        await conn.close()


@pytest.mark.parametrize("key_hash,key_kind,scan_count", [
    ("203.0.113.7", "network", 1),                  # raw address instead of a hash
    (str(uuid.uuid4()).ljust(64, "0"), "install", 1),  # raw install id padded out
    ("A" * 64, "network", 1),                       # not lowercase hex
    (VALID_HASH, "user", 1),                        # unknown kind
    (VALID_HASH, "network", -1),                    # negative counter
])
def test_guest_usage_constraints_reject_bad_rows(pg, key_hash, key_kind, scan_count):
    with pytest.raises(asyncpg.exceptions.CheckViolationError):
        _run(_execute("INSERT INTO guest_scan_usage (key_hash, key_kind, scan_date, scan_count) "
                      "VALUES ($1, $2, CURRENT_DATE, $3)", key_hash, key_kind, scan_count))
    assert scalar("SELECT count(*) FROM guest_scan_usage") == 0


def test_guest_usage_has_one_row_per_key_and_day(pg):
    sql = "INSERT INTO guest_scan_usage (key_hash, key_kind, scan_date, scan_count) VALUES ($1, 'network', CURRENT_DATE, 1)"
    _run(_execute(sql, VALID_HASH))
    with pytest.raises(asyncpg.exceptions.UniqueViolationError):
        _run(_execute(sql, VALID_HASH))


@pytest.mark.parametrize("role", ["anon", "authenticated"])
@pytest.mark.parametrize("statement", [
    "SELECT count(*) FROM public.guest_scan_usage",
    f"INSERT INTO public.guest_scan_usage (key_hash, key_kind, scan_date) VALUES ('{VALID_HASH}', 'network', CURRENT_DATE)",
    "UPDATE public.guest_scan_usage SET scan_count = 0",
    "DELETE FROM public.guest_scan_usage",
])
def test_supabase_client_roles_cannot_touch_guest_counters(pg, role, statement):
    with pytest.raises(asyncpg.exceptions.InsufficientPrivilegeError):
        _run(_execute(statement, role=role))


def test_guest_usage_has_rls_and_the_migration_is_rerunnable(pg):
    assert scalar("SELECT relrowsecurity FROM pg_class WHERE oid = 'public.guest_scan_usage'::regclass") is True
    # Control: the harness really grants client roles on other tables (as Supabase does).
    assert scalar("SELECT has_table_privilege('authenticated', 'public.collection_items', 'SELECT')") is True
    _run(_execute(GUEST_MIGRATION.read_text()))
    for role in ("anon", "authenticated"):
        assert scalar("SELECT has_table_privilege($1, 'public.guest_scan_usage', 'SELECT')", role) is False


def test_guest_allowance_resets_on_the_next_utc_day(pg, monkeypatch):
    import backend.app.security.guest_quota as guest_quota
    from datetime import date as _date

    client = TestClient(app)
    install = str(uuid.uuid4())
    monkeypatch.setattr(guest_quota, "_today", lambda: _date(2026, 10, 1))
    assert all(_succeeded(_scan(client, _guest(install))) for _ in range(2))
    assert _scan(client, _guest(install)).status_code == 429

    monkeypatch.setattr(guest_quota, "_today", lambda: _date(2026, 10, 2))
    assert _succeeded(_scan(client, _guest(install)))
    rows = fetch("SELECT scan_date, key_kind, scan_count FROM guest_scan_usage ORDER BY scan_date, key_kind")
    assert [(str(r[0]), r[1], r[2]) for r in rows] == [
        ("2026-10-01", "install", 2), ("2026-10-01", "network", 2),
        ("2026-10-02", "install", 1), ("2026-10-02", "network", 1),
    ]


def test_guest_day_is_the_utc_date():
    import backend.app.security.guest_quota as guest_quota
    from datetime import datetime as _dt, timezone as _tz

    class _Clock(_dt):
        @classmethod
        def now(cls, tz=None):
            # 23:30 on 1 Oct in UTC-5 is already 2 Oct in UTC.
            moment = _dt(2026, 10, 2, 4, 30, tzinfo=_tz.utc)
            return moment.astimezone(tz) if tz else moment.replace(tzinfo=None)

    original = guest_quota.datetime
    guest_quota.datetime = _Clock
    try:
        assert str(guest_quota._today()) == "2026-10-02"
    finally:
        guest_quota.datetime = original


def test_old_guest_rows_are_pruned(pg):
    import backend.app.security.guest_quota as guest_quota
    from datetime import date as _date, timedelta as _td

    today = _date(2026, 10, 2)
    for days_ago in (0, guest_quota.KEEP_DAYS, guest_quota.KEEP_DAYS + 1):
        _run(_execute("INSERT INTO guest_scan_usage (key_hash, key_kind, scan_date, scan_count) "
                      "VALUES ($1, 'network', $2, 1)", f"{days_ago:064x}", today - _td(days=days_ago)))
    guest_allowance.store.reset_for_test()
    _run(guest_allowance.store.prune(today))
    kept = sorted(str(r[0]) for r in fetch("SELECT scan_date FROM guest_scan_usage"))
    assert kept == [str(today - _td(days=guest_quota.KEEP_DAYS)), str(today)]


# A signed-in caller never falls back to the guest allowance ──────────────────

@pytest.mark.parametrize("token", [
    "not-a-jwt",
    "usr_local_dev_user",                                   # development shortcut
    "sb_publishable_SENTINEL-fake-0123456789",              # a key, not a session
])
def test_invalid_session_in_hardened_mode_is_401_not_a_guest_scan(pg, monkeypatch, token):
    _go_production(monkeypatch, "sb_secret_SENTINEL-admin-0123456789")
    monkeypatch.setattr(settings, "app_env", "staging")
    monkeypatch.setattr(settings, "guest_quota_hmac_secret", "SENTINEL-guest-hmac-0123456789-0123456789")

    resp = _scan(TestClient(app), {"Authorization": f"Bearer {token}", **_guest(str(uuid.uuid4()))})

    assert resp.status_code == 401
    assert scalar("SELECT count(*) FROM guest_scan_usage") == 0
    assert scalar("SELECT count(*) FROM public.users") == 0


def test_expired_session_in_hardened_mode_is_401_not_a_guest_scan(pg, monkeypatch):
    import time as _time
    import jwt as _jwt

    _go_production(monkeypatch, "sb_secret_SENTINEL-admin-0123456789")
    monkeypatch.setattr(settings, "app_env", "staging")
    monkeypatch.setattr(settings, "guest_quota_hmac_secret", "SENTINEL-guest-hmac-0123456789-0123456789")
    user_id = _add_auth_user()
    expired = _jwt.encode({"sub": user_id, "aud": "authenticated", "iss": f"{DELETION_SUPABASE_URL}/auth/v1",
                           "role": "authenticated", "exp": int(_time.time()) - 60},
                          DELETION_JWT_SECRET, algorithm="HS256")

    resp = _scan(TestClient(app), {"Authorization": f"Bearer {expired}"})

    assert resp.status_code == 401
    assert scalar("SELECT count(*) FROM guest_scan_usage") == 0
    assert scalar("SELECT count(*) FROM scan_usage") == 0


def test_non_uuid_collection_ids_never_reach_uuid_columns(pg):
    """Before Phase 3 these reached PostgreSQL's uuid columns and failed with a 500."""
    client = TestClient(app)
    user = _add_auth_user()
    client.post("/v1/account/legal/consent", headers=_bearer(user),
                json={"terms_version": settings.required_terms_version,
                      "privacy_version": settings.required_privacy_version})

    assert client.delete("/v1/collection/not-a-uuid", headers=_bearer(user)).status_code == 404
    created = client.post("/v1/collection", headers=_bearer(user),
                          json={"id": "x" * 36, "coin_name": "Coin", "country": "France", "denomination": "1 Franc"})
    assert created.status_code == 200, created.text
    assert scalar("SELECT count(*) FROM public.collection_items WHERE user_id = $1", uuid.UUID(user)) == 1
