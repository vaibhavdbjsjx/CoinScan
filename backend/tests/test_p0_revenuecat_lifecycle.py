"""
P0 regression tests: RevenueCat entitlement lifecycle follows RevenueCat's
documented webhook semantics (verified against revenuecat.com docs):

- Refunds arrive as CANCELLATION (cancel_reason CUSTOMER_SUPPORT, expiration
  already in the past) and must revoke access immediately.
- PRODUCT_CHANGE is informational; the new tier applies when the RENEWAL /
  INITIAL_PURCHASE for the new product arrives.
- EXPIRATION of an older period / lower tier must not downgrade a newer entitlement.
- Stored expiry is enforced on read.
- Persistence failures return 5xx and are retried.
"""

import time
import uuid

import pytest
import pytest_asyncio
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

import backend.app.db.session as session_module
from backend.app.api import webhooks as webhooks_module
from backend.app.api.webhooks import EntitlementPersistenceError, resolve_tier, webhook_state
from backend.app.config import settings
from backend.app.db.models import Base, Entitlement, User
from backend.app.main import app
from backend.app.security.rate_limit import SubscriptionTier

SECRET = "test_rc_lifecycle_secret"
client = TestClient(app, headers={"Authorization": f"Bearer {SECRET}"})

HOUR_MS = 3_600_000


def _now_ms() -> int:
    return int(time.time() * 1000)


def _post(event: dict):
    return client.post("/v1/webhooks/revenuecat", json={"api_version": "1.0", "event": event})


def _event(event_type: str, user_id: str, **fields) -> dict:
    data = {"id": f"evt_{uuid.uuid4()}", "type": event_type, "app_user_id": user_id}
    data.update(fields)
    return data


@pytest.fixture(autouse=True)
def _webhook_secret():
    original = settings.revenuecat_webhook_secret
    settings.revenuecat_webhook_secret = SECRET
    webhook_state.reset_for_test()
    yield
    webhook_state.reset_for_test()
    settings.revenuecat_webhook_secret = original


def _grant(user_id: str, product: str, expires_in_ms: int = 30 * 24 * HOUR_MS, ts: int = None):
    ts = ts or _now_ms() - 1000
    return _post(
        _event(
            "INITIAL_PURCHASE",
            user_id,
            product_id=product,
            entitlement_ids=["pro" if ".pro." in product else "plus"],
            purchased_at_ms=ts,
            event_timestamp_ms=ts,
            expiration_at_ms=_now_ms() + expires_in_ms,
        )
    )


# ─── Refunds ─────────────────────────────────────────────────────────────────

def test_refund_via_customer_support_cancellation_revokes_immediately():
    user = "usr_refund_1"
    _grant(user, "com.coinscan.pro.monthly")
    assert webhook_state.get_user_tier(user) == SubscriptionTier.PRO

    resp = _post(
        _event(
            "CANCELLATION",
            user,
            product_id="com.coinscan.pro.monthly",
            entitlement_ids=["pro"],
            cancel_reason="CUSTOMER_SUPPORT",
            event_timestamp_ms=_now_ms(),
            expiration_at_ms=_now_ms() - 39_000,
        )
    )

    assert resp.status_code == 200
    assert resp.json()["resolved_tier"] == "free"
    assert resp.json()["action_taken"] == "refund_or_immediate_cancellation_revoked"
    assert webhook_state.get_user_tier(user) == SubscriptionTier.FREE


def test_cancellation_with_past_expiration_revokes_even_without_cancel_reason():
    """RevenueCat's refund sample: expiration_at_ms precedes event_timestamp_ms."""
    user = "usr_refund_2"
    _grant(user, "com.coinscan.plus.monthly")
    now = _now_ms()
    resp = _post(
        _event("CANCELLATION", user, product_id="com.coinscan.plus.monthly",
               event_timestamp_ms=now, expiration_at_ms=now - 39_000)
    )
    assert resp.json()["resolved_tier"] == "free"
    assert webhook_state.get_user_tier(user) == SubscriptionTier.FREE


def test_voluntary_cancellation_keeps_access_until_expiry_then_lapses():
    user = "usr_cancel_future"
    _grant(user, "com.coinscan.pro.monthly")
    future_expiry = _now_ms() + 5 * 24 * HOUR_MS
    resp = _post(
        _event("CANCELLATION", user, product_id="com.coinscan.pro.monthly",
               cancel_reason="UNSUBSCRIBE", event_timestamp_ms=_now_ms(),
               expiration_at_ms=future_expiry)
    )
    assert resp.json()["resolved_tier"] == "pro"
    assert webhook_state.get_user_tier(user) == SubscriptionTier.PRO

    # Simulate the period ending without an EXPIRATION webhook ever arriving
    webhook_state._user_expiry[user] = _now_ms() - 1
    assert webhook_state.get_user_tier(user) == SubscriptionTier.FREE


def test_refund_reversed_restores_access():
    user = "usr_refund_reversed"
    resp = _post(
        _event("REFUND_REVERSED", user, product_id="com.coinscan.pro.yearly",
               entitlement_ids=["pro"], event_timestamp_ms=_now_ms(),
               expiration_at_ms=_now_ms() + 300 * 24 * HOUR_MS)
    )
    assert resp.json()["resolved_tier"] == "pro"


# ─── Upgrades / downgrades ───────────────────────────────────────────────────

def test_product_change_alone_does_not_change_tier_upgrade_or_downgrade():
    plus_user, pro_user = "usr_pc_plus", "usr_pc_pro"
    _grant(plus_user, "com.coinscan.plus.monthly")
    _grant(pro_user, "com.coinscan.pro.monthly")

    up = _post(_event("PRODUCT_CHANGE", plus_user, product_id="com.coinscan.plus.monthly",
                      new_product_id="com.coinscan.pro.monthly", event_timestamp_ms=_now_ms()))
    down = _post(_event("PRODUCT_CHANGE", pro_user, product_id="com.coinscan.pro.monthly",
                        new_product_id="com.coinscan.plus.monthly", event_timestamp_ms=_now_ms()))

    assert up.json()["action_taken"] == "product_change_recorded_pending_effective_event"
    assert up.json()["resolved_tier"] == "plus"
    # Downgrade takes effect at next renewal; user keeps Pro until then
    assert down.json()["resolved_tier"] == "pro"


def test_upgrade_takes_effect_on_renewal_of_new_product_and_old_expiration_is_ignored():
    user = "usr_upgrade"
    t0 = _now_ms() - 10_000
    _grant(user, "com.coinscan.plus.monthly", ts=t0)

    renewal = _post(
        _event("RENEWAL", user, product_id="com.coinscan.pro.monthly", entitlement_ids=["pro"],
               event_timestamp_ms=t0 + 2000, expiration_at_ms=_now_ms() + 30 * 24 * HOUR_MS)
    )
    assert renewal.json()["resolved_tier"] == "pro"

    # The old Plus product then expires (arrives after the upgrade)
    old_exp = _post(
        _event("EXPIRATION", user, product_id="com.coinscan.plus.monthly", entitlement_ids=["plus"],
               event_timestamp_ms=t0 + 3000, expiration_at_ms=_now_ms() + 1000)
    )
    assert old_exp.json()["action_taken"] in ("expiration_of_lower_tier_ignored", "stale_expiration_ignored")
    assert webhook_state.get_user_tier(user) == SubscriptionTier.PRO


def test_expiration_of_an_older_period_does_not_revoke_renewed_subscription():
    user = "usr_old_period"
    now = _now_ms()
    _post(_event("RENEWAL", user, product_id="com.coinscan.pro.monthly", entitlement_ids=["pro"],
                 event_timestamp_ms=now - 5000, expiration_at_ms=now + 30 * 24 * HOUR_MS))
    resp = _post(_event("EXPIRATION", user, product_id="com.coinscan.pro.monthly", entitlement_ids=["pro"],
                        event_timestamp_ms=now, expiration_at_ms=now - 24 * HOUR_MS))
    assert resp.json()["action_taken"] == "stale_expiration_ignored"
    assert webhook_state.get_user_tier(user) == SubscriptionTier.PRO


def test_real_expiration_still_revokes():
    user = "usr_real_exp"
    _grant(user, "com.coinscan.pro.monthly", expires_in_ms=1000)
    resp = _post(_event("EXPIRATION", user, product_id="com.coinscan.pro.monthly", entitlement_ids=["pro"],
                        event_timestamp_ms=_now_ms(), expiration_at_ms=_now_ms() + 1000))
    assert resp.json()["resolved_tier"] == "free"


# ─── Mapping & identity ──────────────────────────────────────────────────────

def test_unknown_product_does_not_downgrade_paying_user():
    user = "usr_unknown_keep"
    _grant(user, "com.coinscan.pro.monthly")
    resp = _post(_event("RENEWAL", user, product_id="com.other.app.gems", entitlement_ids=["gems"],
                        event_timestamp_ms=_now_ms()))
    assert resp.json()["action_taken"] == "unknown_product_ignored"
    assert webhook_state.get_user_tier(user) == SubscriptionTier.PRO


def test_tier_mapping_is_exact_not_substring():
    assert resolve_tier(["promo"], None) is None
    assert resolve_tier(None, "com.coinscan.promo.monthly") is None
    assert resolve_tier(["pro"], None) == SubscriptionTier.PRO
    assert resolve_tier(["PLUS"], None) == SubscriptionTier.PLUS
    # Google Play "subscription:base-plan" format
    assert resolve_tier(None, "com.coinscan.pro.monthly:monthly-base") == SubscriptionTier.PRO
    # Highest tier wins when both entitlements are present
    assert resolve_tier(["plus", "pro"], None) == SubscriptionTier.PRO


def test_anonymous_purchase_is_linked_to_supabase_uuid_via_aliases():
    supabase_uuid = str(uuid.uuid4())
    resp = _post(
        _event("INITIAL_PURCHASE", "$RCAnonymousID:abc123", aliases=["$RCAnonymousID:abc123", supabase_uuid],
               original_app_user_id="$RCAnonymousID:abc123", product_id="com.coinscan.pro.monthly",
               entitlement_ids=["pro"], event_timestamp_ms=_now_ms(),
               expiration_at_ms=_now_ms() + 30 * 24 * HOUR_MS)
    )
    assert resp.json()["user_id"] == supabase_uuid
    assert webhook_state.get_user_tier(supabase_uuid) == SubscriptionTier.PRO


def test_transfer_event_without_app_user_id_moves_entitlement():
    source, destination = str(uuid.uuid4()), str(uuid.uuid4())
    _grant(source, "com.coinscan.pro.monthly")

    resp = _post({
        "id": f"evt_{uuid.uuid4()}",
        "type": "TRANSFER",
        "transferred_from": [source],
        "transferred_to": [destination],
        "event_timestamp_ms": _now_ms(),
    })

    assert resp.status_code == 200
    assert resp.json()["user_id"] == destination
    assert webhook_state.get_user_tier(destination) == SubscriptionTier.PRO
    assert webhook_state.get_user_tier(source) == SubscriptionTier.FREE


def test_paused_and_billing_issue_keep_access_and_test_event_is_acknowledged():
    user = "usr_pause"
    _grant(user, "com.coinscan.plus.yearly")
    paused = _post(_event("SUBSCRIPTION_PAUSED", user, event_timestamp_ms=_now_ms()))
    billing = _post(_event("BILLING_ISSUE", user, event_timestamp_ms=_now_ms() + 1,
                           grace_period_expiration_at_ms=_now_ms() + 6 * 24 * HOUR_MS))
    test_evt = _post({"id": f"evt_{uuid.uuid4()}", "type": "TEST", "app_user_id": "rc_test"})
    assert paused.json()["resolved_tier"] == "plus"
    assert billing.json()["resolved_tier"] == "plus"
    assert test_evt.status_code == 200


# ─── Persistence failure => retry ────────────────────────────────────────────

def test_persistence_failure_returns_500_and_event_is_retried(monkeypatch):
    user = "usr_db_down"
    event = _event("INITIAL_PURCHASE", user, product_id="com.coinscan.pro.monthly", entitlement_ids=["pro"],
                   event_timestamp_ms=_now_ms(), expiration_at_ms=_now_ms() + 30 * 24 * HOUR_MS)

    async def failing_set(*args, **kwargs):
        raise EntitlementPersistenceError("database unavailable")

    original = webhook_state.set_user_tier_async
    monkeypatch.setattr(webhook_state, "set_user_tier_async", failing_set)
    safe_client = TestClient(app, raise_server_exceptions=False, headers={"Authorization": f"Bearer {SECRET}"})
    first = safe_client.post("/v1/webhooks/revenuecat", json={"event": event})
    assert first.status_code == 500
    assert webhook_state.is_processed(event["id"]) is False

    monkeypatch.setattr(webhook_state, "set_user_tier_async", original)
    retry = _post(event)
    assert retry.status_code == 200
    assert retry.json()["status"] == "success"
    assert webhook_state.get_user_tier(user) == SubscriptionTier.PRO


# ─── Database-backed expiry enforcement (SQLite, production mode) ────────────

@pytest_asyncio.fixture
async def sqlite_db():
    orig = (settings.app_env, settings.database_url, session_module._engine, session_module._session_factory)
    settings.app_env = "production"
    settings.database_url = "sqlite+aiosqlite:///:memory:"
    engine = create_async_engine(settings.database_url)
    factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    session_module._engine, session_module._session_factory = engine, factory
    yield factory
    await engine.dispose()
    settings.app_env, settings.database_url, session_module._engine, session_module._session_factory = orig


@pytest.mark.asyncio
async def test_db_expiry_is_enforced_on_read(sqlite_db):
    user_uuid = str(uuid.uuid4())
    async with sqlite_db() as session:
        session.add(User(id=user_uuid, email="x@example.com"))
        await session.commit()

    await webhook_state.set_user_tier_async(
        user_uuid, SubscriptionTier.PRO, status_val="cancelled", expires_at_ms=_now_ms() + HOUR_MS
    )
    assert await webhook_state.get_user_tier_async(user_uuid) == SubscriptionTier.PRO

    async with sqlite_db() as session:
        ent = await session.get(Entitlement, user_uuid)
        assert ent.tier == "pro" and ent.status == "cancelled" and ent.expires_at is not None

    # Period ends; no EXPIRATION webhook arrives
    webhook_state._user_entitlements.clear()
    async with sqlite_db() as session:
        ent = await session.get(Entitlement, user_uuid)
        ent.expires_at = webhooks_module._ms_to_datetime(_now_ms() - 1000)
        await session.commit()
    assert await webhook_state.get_user_tier_async(user_uuid) == SubscriptionTier.FREE


@pytest.mark.asyncio
async def test_refund_is_persisted_as_revoked(sqlite_db):
    user_uuid = str(uuid.uuid4())
    async with sqlite_db() as session:
        session.add(User(id=user_uuid, email="y@example.com"))
        await session.commit()

    _grant(user_uuid, "com.coinscan.pro.monthly")
    _post(_event("CANCELLATION", user_uuid, product_id="com.coinscan.pro.monthly",
                 cancel_reason="CUSTOMER_SUPPORT", event_timestamp_ms=_now_ms(),
                 expiration_at_ms=_now_ms() - 1000))

    async with sqlite_db() as session:
        ent = await session.get(Entitlement, user_uuid)
        assert ent.tier == "free"
        assert ent.status == "revoked"
