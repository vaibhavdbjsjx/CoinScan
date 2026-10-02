"""
Guest (signed-out) scanning: identity, keyed allowance and access boundaries.

These run on every test run without a database (in-memory allowance store).
The PostgreSQL behaviour, UUID schema and cross-request concurrency are covered
by test_postgres_guest_integration.py.
"""

import io
import logging
import uuid

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image
from starlette.requests import Request

from backend.app.api import recognition as recognition_module
from backend.app.config import Settings, settings
from backend.app.main import app
from backend.app.security.auth import GUEST_USER_ID, UnifiedAuthenticator
from backend.app.security.client_ip import get_client_ip
from backend.app.security.guest_quota import INSTALL_ID_HEADER, allowance_keys, guest_allowance
from backend.app.services.numista.client import NumistaClient, NumistaTypeDetail
from backend.app.services.recognition.vision_provider import VisionProvider


def _request(peer="203.0.113.5", headers=None) -> Request:
    raw = [(k.lower().encode(), v.encode()) for k, v in (headers or {}).items()]
    return Request({"type": "http", "method": "POST", "path": "/", "query_string": b"",
                    "headers": raw, "client": (peer, 40000)})


def _jpeg() -> bytes:
    img = Image.new("RGB", (400, 400), color=(120, 110, 90))
    for x in range(0, 400, 8):
        for y in range(400):
            img.putpixel((x, y), (250, 250, 250))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=92)
    return buf.getvalue()


def _scan(client, headers=None):
    return client.post("/v1/recognition", files={"front_image": ("f.jpg", _jpeg(), "image/jpeg")},
                       headers=headers or {})


# ── Client address behind proxies ────────────────────────────────────────────

def test_forwarded_header_is_ignored_without_a_trusted_proxy(monkeypatch):
    monkeypatch.setattr(settings, "trusted_proxy_hops", 0)
    assert get_client_ip(_request(headers={"X-Forwarded-For": "6.6.6.6"})) == "203.0.113.5"


def test_only_the_entry_added_by_the_trusted_proxy_is_used(monkeypatch):
    monkeypatch.setattr(settings, "trusted_proxy_hops", 1)
    spoofed = {"X-Forwarded-For": "6.6.6.6, 198.51.100.7"}
    assert get_client_ip(_request(headers=spoofed)) == "198.51.100.7"

    monkeypatch.setattr(settings, "trusted_proxy_hops", 2)
    chained = {"X-Forwarded-For": "6.6.6.6, 198.51.100.7, 10.0.0.2"}
    assert get_client_ip(_request(headers=chained)) == "198.51.100.7"


@pytest.mark.parametrize("header", [None, "", "not-an-ip", "198.51.100.7"])
def test_missing_short_or_invalid_forwarded_header_falls_back_to_the_peer(monkeypatch, header):
    monkeypatch.setattr(settings, "trusted_proxy_hops", 2)
    headers = {} if header is None else {"X-Forwarded-For": header}
    assert get_client_ip(_request(headers=headers)) == "203.0.113.5"


def test_edge_proxy_header_is_used_when_configured(monkeypatch):
    # e.g. Railway's edge sets X-Real-IP itself; it takes precedence over X-Forwarded-For.
    monkeypatch.setattr(settings, "client_ip_header", "X-Real-IP")
    monkeypatch.setattr(settings, "trusted_proxy_hops", 1)
    headers = {"X-Real-IP": "198.51.100.7", "X-Forwarded-For": "6.6.6.6, 10.0.0.1"}
    assert get_client_ip(_request(headers=headers)) == "198.51.100.7"


def test_edge_proxy_header_list_uses_the_leftmost_entry(monkeypatch):
    monkeypatch.setattr(settings, "client_ip_header", "x-forwarded-for")
    headers = {"X-Forwarded-For": "198.51.100.7, 100.64.0.2"}
    assert get_client_ip(_request(headers=headers)) == "198.51.100.7"


@pytest.mark.parametrize("value", [None, "", "not-an-ip", "unknown, 10.0.0.1"])
def test_missing_or_malformed_edge_header_falls_back_to_the_peer(monkeypatch, value):
    monkeypatch.setattr(settings, "client_ip_header", "X-Real-IP")
    headers = {} if value is None else {"X-Real-IP": value}
    assert get_client_ip(_request(headers=headers)) == "203.0.113.5"


def _raw_request(peer, header_pairs) -> Request:
    """A request with possibly repeated headers."""
    raw = [(k.lower().encode(), v.encode()) for k, v in header_pairs]
    return Request({"type": "http", "method": "POST", "path": "/", "query_string": b"",
                    "headers": raw, "client": (peer, 40000)})


def test_spoofed_forwarded_for_is_ignored_when_the_edge_header_is_configured(monkeypatch):
    monkeypatch.setattr(settings, "client_ip_header", "X-Real-IP")
    monkeypatch.setattr(settings, "trusted_proxy_hops", 0)
    headers = {"X-Real-IP": "198.51.100.7", "X-Forwarded-For": "6.6.6.6", "Forwarded": "for=6.6.6.6",
               "True-Client-IP": "6.6.6.6", "CF-Connecting-IP": "6.6.6.6"}
    assert get_client_ip(_request(headers=headers)) == "198.51.100.7"
    # Without the edge header, client-chosen headers are still ignored.
    del headers["X-Real-IP"]
    assert get_client_ip(_request(headers=headers)) == "203.0.113.5"


def test_repeated_edge_header_falls_back_to_the_peer(monkeypatch):
    """If a client copy survived next to the edge's own, neither can be trusted."""
    monkeypatch.setattr(settings, "client_ip_header", "X-Real-IP")
    request = _raw_request("203.0.113.5", [("X-Real-IP", "6.6.6.6"), ("X-Real-IP", "198.51.100.7")])
    assert get_client_ip(request) == "203.0.113.5"


@pytest.mark.parametrize("value", [
    "198.51.100.7:4321",          # address with port
    "[2001:db8::1]:443",          # bracketed IPv6 with port
    "198.51.100.7 6.6.6.6",       # two values without a comma
    "198.51.100.256",             # out of range
    "2001:db8::zz",               # invalid IPv6
    "for=198.51.100.7",           # RFC 7239 syntax, not a bare address
    "%00198.51.100.7",
])
def test_malformed_edge_header_values_fall_back_to_the_peer(monkeypatch, value):
    monkeypatch.setattr(settings, "client_ip_header", "X-Real-IP")
    assert get_client_ip(_request(headers={"X-Real-IP": value})) == "203.0.113.5"


@pytest.mark.parametrize("value,expected", [
    ("2001:DB8::1", "2001:db8::1"),             # IPv6 is normalised
    (" 198.51.100.7 ", "198.51.100.7"),         # surrounding spaces
    ("::ffff:198.51.100.7", "198.51.100.7"),    # IPv4-mapped IPv6 is the IPv4 client
])
def test_edge_header_values_are_normalised(monkeypatch, value, expected):
    monkeypatch.setattr(settings, "client_ip_header", "X-Real-IP")
    assert get_client_ip(_request(headers={"X-Real-IP": value})) == expected


def test_unusable_edge_header_is_logged_without_the_address(monkeypatch, caplog):
    import backend.app.security.client_ip as client_ip_module
    monkeypatch.setattr(client_ip_module, "_warned_about_header", False)
    monkeypatch.setattr(settings, "client_ip_header", "X-Real-IP")
    with caplog.at_level(logging.WARNING, logger="coinscan.client_ip"):
        get_client_ip(_request(peer="203.0.113.5", headers={"X-Real-IP": "6.6.6.6:80"}))
        get_client_ip(_request(peer="203.0.113.5"))
    assert caplog.text.count("CLIENT_IP_HEADER X-Real-IP") == 1  # once per process
    assert "6.6.6.6" not in caplog.text and "203.0.113.5" not in caplog.text


def test_ipv6_clients_share_one_network_allowance_per_64(monkeypatch):
    """Switching addresses inside one IPv6 /64 must not reset the guest allowance."""
    monkeypatch.setattr(settings, "client_ip_header", "X-Real-IP")

    def network_digest(address):
        keys = allowance_keys(_request(headers={"X-Real-IP": address}))
        return [k.digest for k in keys if k.kind == "network"][0]

    same = {network_digest(a) for a in ("2001:db8:1:2::1", "2001:db8:1:2:ffff::9", "2001:db8:1:2:abcd:1234:5678:9abc")}
    assert len(same) == 1
    assert network_digest("2001:db8:1:3::1") not in same
    assert network_digest("198.51.100.7") != network_digest("198.51.100.8")


# ── Guest identity and allowance keys ────────────────────────────────────────

def test_signed_out_caller_has_no_identity_derived_from_address_or_device():
    caller = UnifiedAuthenticator().resolve_caller(
        _request(headers={INSTALL_ID_HEADER: str(uuid.uuid4())})
    )
    assert caller.is_authenticated is False
    assert caller.user_id == GUEST_USER_ID
    assert "203.0.113.5" not in caller.user_id


def test_allowance_keys_are_keyed_hashes_never_raw_values(monkeypatch):
    monkeypatch.setattr(settings, "guest_quota_hmac_secret", "secret-one")
    install = str(uuid.uuid4())
    request = _request(headers={INSTALL_ID_HEADER: install})

    keys = allowance_keys(request)
    assert [k.kind for k in keys] == ["install", "network"]
    for key in keys:
        assert len(key.digest) == 64 and int(key.digest, 16) >= 0
        assert "203.0.113.5" not in key.digest and install not in key.digest
    assert [k.digest for k in allowance_keys(request)] == [k.digest for k in keys]  # stable

    monkeypatch.setattr(settings, "guest_quota_hmac_secret", "secret-two")
    assert [k.digest for k in allowance_keys(request)] != [k.digest for k in keys]  # keyed


def test_install_id_only_adds_its_own_allowance_under_a_network_ceiling(monkeypatch):
    monkeypatch.setattr(settings, "guest_quota_hmac_secret", "s")
    keys = allowance_keys(_request(headers={INSTALL_ID_HEADER: str(uuid.uuid4())}))
    assert [(k.kind, k.daily_limit) for k in keys] == [
        ("install", settings.guest_daily_scan_limit),
        ("network", settings.guest_network_daily_scan_limit),
    ]


@pytest.mark.parametrize("value", ["not-a-uuid", "../../etc", "1' OR '1'='1", "x" * 500])
def test_malformed_install_id_is_ignored(monkeypatch, value):
    monkeypatch.setattr(settings, "guest_quota_hmac_secret", "s")
    keys = allowance_keys(_request(headers={INSTALL_ID_HEADER: value}))
    assert [(k.kind, k.daily_limit) for k in keys] == [("network", settings.guest_daily_scan_limit)]


# ── Allowance behaviour (in-memory store) ────────────────────────────────────

@pytest.mark.asyncio
async def test_two_guest_scans_per_day_then_a_clear_limit_error():
    request = _request(headers={INSTALL_ID_HEADER: str(uuid.uuid4())})
    for remaining in (1, 0):
        slot = await guest_allowance.reserve(request)
        assert await slot.commit() == remaining

    with pytest.raises(HTTPException) as exc:
        await guest_allowance.reserve(request)
    assert exc.value.status_code == 429
    assert exc.value.detail["error"] == "guest_daily_limit_reached"
    assert exc.value.detail["limit"] == 2


@pytest.mark.asyncio
async def test_released_slot_is_returned_and_release_is_idempotent():
    request = _request()
    slot = await guest_allowance.reserve(request)
    await slot.release()
    await slot.release()
    assert all(v == 0 for v in guest_allowance.store._local.values())

    committed = await guest_allowance.reserve(request)
    await committed.commit()
    await committed.release()  # a committed scan stays charged
    assert (await guest_allowance.status(request))["used"] == 1


@pytest.mark.asyncio
async def test_a_refused_reservation_does_not_charge_the_keys_it_passed(monkeypatch):
    monkeypatch.setattr(settings, "guest_network_daily_scan_limit", 1)
    first = _request(headers={INSTALL_ID_HEADER: str(uuid.uuid4())})
    await (await guest_allowance.reserve(first)).commit()

    second = _request(headers={INSTALL_ID_HEADER: str(uuid.uuid4())})  # same network
    with pytest.raises(HTTPException):
        await guest_allowance.reserve(second)
    assert (await guest_allowance.status(second))["used"] == 0


# ── Fail closed off localhost ────────────────────────────────────────────────

class _RecordingVision(VisionProvider):
    calls = 0

    async def analyze_coin_images(self, *args, **kwargs):
        _RecordingVision.calls += 1
        raise AssertionError("the paid provider must not be called")


@pytest.mark.parametrize("env", ["production", "staging", "unset"])
def test_guest_scanning_is_off_without_the_hashing_secret_on_a_server(monkeypatch, env):
    if env == "unset":
        # A deployment that never sets APP_ENV (on any platform) gets the hardened default.
        monkeypatch.delenv("APP_ENV", raising=False)
        monkeypatch.setenv("RAILWAY_ENVIRONMENT", "production")
        env = Settings(_env_file=None).app_env
    monkeypatch.setattr(settings, "app_env", env)
    monkeypatch.setattr(settings, "guest_quota_hmac_secret", None)
    _RecordingVision.calls = 0
    monkeypatch.setattr(recognition_module, "get_vision_provider", lambda: _RecordingVision())

    resp = _scan(TestClient(app))

    assert resp.status_code == 503
    assert resp.json()["detail"]["error"] == "guest_scanning_unavailable"
    assert _RecordingVision.calls == 0


# ── Access boundaries ────────────────────────────────────────────────────────

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
    ],
)
def test_guests_are_refused_by_account_endpoints(method, path):
    kwargs = {}
    if method in ("post", "delete"):
        kwargs["json"] = (
            {"terms_version": "1.0.0", "privacy_version": "1.0.0"} if "consent" in path
            else {"coin_name": "Coin", "country": "France", "denomination": "1 Franc"} if "collection" in path
            else {"confirm_phrase": "DELETE MY ACCOUNT"}
        )
    client = TestClient(app)
    resp = client.request(method.upper(), path, headers={INSTALL_ID_HEADER: str(uuid.uuid4())}, **kwargs)
    assert resp.status_code == 401, (path, resp.status_code, resp.text)


def test_guest_quota_endpoint_is_for_guests_only():
    client = TestClient(app)
    status = client.get("/v1/guest/quota").json()
    assert status["limit"] == 2 and status["remaining"] == 2
    assert client.get("/v1/guest/quota", headers={"Authorization": "Bearer usr_quota_user"}).status_code == 400


class _Catalogue(NumistaClient):
    def __init__(self):
        super().__init__(api_key="unused")

    async def search_types(self, query, category="coin", count=5):
        return [NumistaTypeDetail(id=1492, title="1 Dollar", country="United States",
                                  denomination="1 Dollar", min_year=1878, max_year=1921)]


def test_guest_scan_response_reports_remaining_scans_and_logs_no_address(monkeypatch, caplog):
    monkeypatch.setattr(recognition_module, "numista_client", _Catalogue())
    caplog.set_level(logging.DEBUG)
    install = str(uuid.uuid4())
    resp = _scan(TestClient(app), {INSTALL_ID_HEADER: install})

    assert resp.status_code == 200
    meta = resp.json()["processingMetadata"]
    assert meta["guest"] is True and meta["guest_scans_remaining"] == 1
    assert "testclient" not in caplog.text and install not in caplog.text
