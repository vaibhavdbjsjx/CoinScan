"""
RevenueCat webhook ordering on real PostgreSQL, across restarts.

RevenueCat may deliver (or retry) an older event after a newer one. Ordering
must not depend on this process's memory: after a restart, a redeploy, or on
another worker, an older event must still never overwrite newer state. A
restart is simulated by clearing the in-process webhook state between
deliveries; the database is all that remains.

Set TEST_POSTGRES_URL to run (see test_postgres_guest_integration.py).
"""

import time
import uuid

import pytest
from fastapi.testclient import TestClient

from backend.app.api.webhooks import webhook_state
from backend.app.config import settings
from backend.app.main import app
from backend.tests.test_postgres_guest_integration import (  # noqa: F401  (fixtures)
    PG_URL,
    _add_auth_user,
    database,
    pg,
    scalar,
)

pytestmark = pytest.mark.skipif(
    not PG_URL, reason="TEST_POSTGRES_URL is not set: PostgreSQL integration tests were not run"
)

SECRET = "test_rc_ordering_secret"
DAY_MS = 24 * 3_600_000


def _now_ms() -> int:
    return int(time.time() * 1000)


@pytest.fixture
def rc(pg, monkeypatch):
    monkeypatch.setattr(settings, "revenuecat_webhook_secret", SECRET)
    webhook_state.reset_for_test()
    yield TestClient(app, headers={"Authorization": f"Bearer {SECRET}"})
    webhook_state.reset_for_test()


def _send(client, event_type, user_id, ts, **fields):
    event = {"id": f"evt_{uuid.uuid4()}", "type": event_type, "app_user_id": user_id,
             "event_timestamp_ms": ts, **fields}
    resp = client.post("/v1/webhooks/revenuecat", json={"api_version": "1.0", "event": event})
    assert resp.status_code == 200, resp.text
    return resp.json()


def _pro(ts, expires):
    return {"product_id": "com.coinscan.pro.monthly", "entitlement_ids": ["pro"],
            "purchased_at_ms": ts, "expiration_at_ms": expires}


def _restart():
    """Everything in process memory is gone; only the database remains."""
    webhook_state.reset_for_test()


def _stored_tier(user_id):
    return scalar("SELECT tier::text FROM public.entitlements WHERE user_id = $1", uuid.UUID(user_id))


def test_late_renewal_after_refund_does_not_restore_access_after_restart(rc):
    user = _add_auth_user()
    now = _now_ms()
    _send(rc, "INITIAL_PURCHASE", user, now - 3 * DAY_MS, **_pro(now - 3 * DAY_MS, now + 27 * DAY_MS))
    refund = _send(rc, "CANCELLATION", user, now - DAY_MS, cancel_reason="CUSTOMER_SUPPORT",
                   product_id="com.coinscan.pro.monthly", entitlement_ids=["pro"],
                   expiration_at_ms=now - DAY_MS)
    assert refund["resolved_tier"] == "free"

    _restart()
    # A renewal from before the refund, delivered late (e.g. a retry).
    late = _send(rc, "RENEWAL", user, now - 2 * DAY_MS, **_pro(now - 2 * DAY_MS, now + 28 * DAY_MS))

    assert late["action_taken"] == "out_of_order_event_ignored"
    assert late["resolved_tier"] == "free"
    assert _stored_tier(user) == "free"


def test_late_refund_from_an_earlier_period_does_not_revoke_after_restart(rc):
    user = _add_auth_user()
    now = _now_ms()
    _send(rc, "INITIAL_PURCHASE", user, now - 3 * DAY_MS, **_pro(now - 3 * DAY_MS, now + 27 * DAY_MS))
    _send(rc, "RENEWAL", user, now - DAY_MS, **_pro(now - DAY_MS, now + 29 * DAY_MS))

    _restart()
    stale = _send(rc, "CANCELLATION", user, now - 2 * DAY_MS, cancel_reason="CUSTOMER_SUPPORT",
                  product_id="com.coinscan.pro.monthly", expiration_at_ms=now - 2 * DAY_MS)

    assert stale["action_taken"] == "out_of_order_event_ignored"
    assert _stored_tier(user) == "pro"


def test_newer_events_still_apply_after_restart(rc):
    user = _add_auth_user()
    now = _now_ms()
    _send(rc, "INITIAL_PURCHASE", user, now - 3 * DAY_MS, **_pro(now - 3 * DAY_MS, now + 27 * DAY_MS))

    _restart()
    refund = _send(rc, "CANCELLATION", user, now - 1000, cancel_reason="CUSTOMER_SUPPORT",
                   product_id="com.coinscan.pro.monthly", expiration_at_ms=now - 1000)

    assert refund["action_taken"] == "refund_or_immediate_cancellation_revoked"
    assert _stored_tier(user) == "free"


def test_duplicate_delivery_after_restart_is_idempotent(rc):
    user = _add_auth_user()
    now = _now_ms()
    event = {"id": f"evt_{uuid.uuid4()}", "type": "INITIAL_PURCHASE", "app_user_id": user,
             "event_timestamp_ms": now - DAY_MS, **_pro(now - DAY_MS, now + 29 * DAY_MS)}
    first = rc.post("/v1/webhooks/revenuecat", json={"event": event})
    _restart()
    second = rc.post("/v1/webhooks/revenuecat", json={"event": event})

    assert first.json()["status"] == "success"
    assert second.json()["status"] == "duplicate_ignored"
    assert scalar("SELECT count(*) FROM public.subscription_events WHERE event_id = $1", event["id"]) == 1
