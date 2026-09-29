"""
Unit tests for RevenueCat webhook receiver, event routing, and idempotency.
"""

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.config import settings
from backend.app.api.webhooks import webhook_state
from backend.app.security.rate_limit import SubscriptionTier

TEST_RC_SECRET = "test_revenuecat_secret_xyz"
client = TestClient(app, headers={"Authorization": f"Bearer {TEST_RC_SECRET}"})


@pytest.fixture(autouse=True)
def reset_webhook_state():
    original_secret = settings.revenuecat_webhook_secret
    settings.revenuecat_webhook_secret = TEST_RC_SECRET
    webhook_state.reset_for_test()
    yield
    webhook_state.reset_for_test()
    settings.revenuecat_webhook_secret = original_secret


def test_revenuecat_initial_purchase_activates_pro():
    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_rc_purchase_001",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_collector_42",
            "product_id": "com.coinscan.pro.monthly",
            "entitlement_ids": ["coinscan_pro"],
            "period_type": "PROMOTIONAL",
            "purchased_at_ms": 1700000000000,
            "environment": "SANDBOX",
        },
    }

    response = client.post("/v1/webhooks/revenuecat", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["user_id"] == "usr_collector_42"
    assert data["resolved_tier"] == "pro"
    assert "activated" in data["action_taken"]

    # Verify state in manager
    assert webhook_state.get_user_tier("usr_collector_42") == SubscriptionTier.PRO


def test_revenuecat_webhook_idempotency_duplicate_event():
    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_rc_dup_999",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_dealer_88",
            "product_id": "com.coinscan.pro.yearly",
            "entitlement_ids": ["coinscan_pro"],
        },
    }

    # 1. First event
    resp1 = client.post("/v1/webhooks/revenuecat", json=payload)
    assert resp1.status_code == 200
    assert resp1.json()["status"] == "success"

    # 2. Duplicate event with same event_id
    resp2 = client.post("/v1/webhooks/revenuecat", json=payload)
    assert resp2.status_code == 200
    assert resp2.json()["status"] == "duplicate_ignored"
    assert resp2.json()["action_taken"] == "none"


def test_revenuecat_initial_purchase_activates_plus():
    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_rc_plus_001",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_plus_member",
            "product_id": "com.coinscan.plus.monthly",
            "entitlement_ids": ["coinscan_plus"],
            "period_type": "NORMAL",
            "purchased_at_ms": 1700000000000,
            "environment": "SANDBOX",
        },
    }

    response = client.post("/v1/webhooks/revenuecat", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["user_id"] == "usr_plus_member"
    assert data["resolved_tier"] == "plus"
    assert webhook_state.get_user_tier("usr_plus_member") == SubscriptionTier.PLUS


def test_revenuecat_expiration_downgrades_to_free():
    webhook_state.set_user_tier("usr_expired_1", SubscriptionTier.PRO)

    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_rc_exp_002",
            "type": "EXPIRATION",
            "app_user_id": "usr_expired_1",
            "product_id": "com.coinscan.pro.monthly",
        },
    }

    response = client.post("/v1/webhooks/revenuecat", json=payload)
    assert response.status_code == 200
    assert response.json()["resolved_tier"] == "free"
    assert webhook_state.get_user_tier("usr_expired_1") == SubscriptionTier.FREE


def test_revenuecat_revocation_downgrades_to_free():
    webhook_state.set_user_tier("usr_revoked_1", SubscriptionTier.PRO)

    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_rc_rev_003",
            "type": "REVOCATION",
            "app_user_id": "usr_revoked_1",
            "product_id": "com.coinscan.pro.monthly",
        },
    }

    response = client.post("/v1/webhooks/revenuecat", json=payload)
    assert response.status_code == 200
    assert response.json()["resolved_tier"] == "free"
    assert webhook_state.get_user_tier("usr_revoked_1") == SubscriptionTier.FREE


def test_revenuecat_cancellation_keeps_active_tier_until_expiration():
    webhook_state.set_user_tier("usr_cancel_pending", SubscriptionTier.PRO)

    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_rc_cancel_004",
            "type": "CANCELLATION",
            "app_user_id": "usr_cancel_pending",
            "product_id": "com.coinscan.pro.monthly",
        },
    }

    response = client.post("/v1/webhooks/revenuecat", json=payload)
    assert response.status_code == 200
    # Still Pro until expiration occurs
    assert response.json()["resolved_tier"] == "pro"
    assert webhook_state.get_user_tier("usr_cancel_pending") == SubscriptionTier.PRO


def test_revenuecat_webhook_auth_verification(monkeypatch):
    from backend.app.config import settings

    monkeypatch.setattr(settings, "revenuecat_webhook_secret", "secret_rc_token_123")

    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_rc_auth_test",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_auth_tester",
            "product_id": "com.coinscan.pro.monthly",
        },
    }

    # 1. Missing / wrong authorization header returns 401
    bad_resp = client.post("/v1/webhooks/revenuecat", json=payload, headers={"Authorization": "Bearer wrong_token"})
    assert bad_resp.status_code == 401

    # 2. Correct authorization header returns 200
    good_resp = client.post("/v1/webhooks/revenuecat", json=payload, headers={"Authorization": "Bearer secret_rc_token_123"})
    assert good_resp.status_code == 200
    assert good_resp.json()["status"] == "success"


def test_account_isolation_entitlements():
    # User A buys Pro
    webhook_state.set_user_tier("usr_account_a", SubscriptionTier.PRO)
    # User B is unassigned
    assert webhook_state.get_user_tier("usr_account_b") == SubscriptionTier.FREE

    # Verify separate users do not share entitlements
    assert webhook_state.get_user_tier("usr_account_a") == SubscriptionTier.PRO
    assert webhook_state.get_user_tier("usr_account_b") == SubscriptionTier.FREE


def test_unknown_product_id_defaults_to_free():
    """Unknown or unrecognized product IDs must NOT silently grant PRO access."""
    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_rc_unknown_product_001",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_unknown_product_user",
            "product_id": "com.coinscan.mystery.monthly",
            "entitlement_ids": ["coinscan_mystery"],
        },
    }

    response = client.post("/v1/webhooks/revenuecat", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["resolved_tier"] == "free"
    assert webhook_state.get_user_tier("usr_unknown_product_user") == SubscriptionTier.FREE


def test_bounded_lru_idempotency_eviction():
    """Verify that WebhookStateManager bounds its memory and evicts oldest items beyond capacity."""
    manager = type(webhook_state)()
    manager.MAX_PROCESSED_EVENTS = 5  # Small limit for test

    for i in range(10):
        manager.mark_processed(f"evt_{i}")

    # Oldest 5 (evt_0 to evt_4) should have been evicted
    for i in range(5):
        assert not manager.is_processed(f"evt_{i}")

    # Newest 5 (evt_5 to evt_9) should remain present
    for i in range(5, 10):
        assert manager.is_processed(f"evt_{i}")


def test_billing_issue_maintains_tier():
    """Billing issue enters grace period without immediate entitlement termination."""
    webhook_state.set_user_tier("usr_grace_user", SubscriptionTier.PRO)

    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_rc_billing_issue_001",
            "type": "BILLING_ISSUE",
            "app_user_id": "usr_grace_user",
            "product_id": "com.coinscan.pro.monthly",
        },
    }

    response = client.post("/v1/webhooks/revenuecat", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["action_taken"] == "grace_period_notified"
    assert data["resolved_tier"] == "pro"
    assert webhook_state.get_user_tier("usr_grace_user") == SubscriptionTier.PRO


def test_unknown_event_type_handled_safely():
    """Unhandled webhook event types return 200 without throwing or altering entitlement."""
    webhook_state.set_user_tier("usr_future_event_user", SubscriptionTier.PLUS)

    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_rc_future_type_001",
            "type": "NEW_UNSEEN_EVENT_TYPE",
            "app_user_id": "usr_future_event_user",
            "product_id": "com.coinscan.plus.monthly",
        },
    }

    response = client.post("/v1/webhooks/revenuecat", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["action_taken"] == "unhandled_event_new_unseen_event_type"
    assert data["resolved_tier"] == "plus"
    assert webhook_state.get_user_tier("usr_future_event_user") == SubscriptionTier.PLUS


# ─── REVENUECAT WEBHOOK SECURITY & FAIL-CLOSED TESTS ──────────────────────────

def test_webhook_fail_closed_when_secret_missing():
    """Missing revenuecat_webhook_secret must fail closed with 401."""
    settings.revenuecat_webhook_secret = None
    raw_client = TestClient(app)

    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_missing_secret",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_hacker",
            "product_id": "com.coinscan.pro.monthly",
        },
    }
    response = raw_client.post(
        "/v1/webhooks/revenuecat",
        json=payload,
        headers={"Authorization": "Bearer any_token"},
    )
    assert response.status_code == 401
    assert "not configured" in response.json()["detail"].lower()


def test_webhook_fail_closed_when_secret_empty():
    """Empty or whitespace revenuecat_webhook_secret must fail closed with 401."""
    settings.revenuecat_webhook_secret = "   "
    raw_client = TestClient(app)

    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_empty_secret",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_hacker",
            "product_id": "com.coinscan.pro.monthly",
        },
    }
    response = raw_client.post(
        "/v1/webhooks/revenuecat",
        json=payload,
        headers={"Authorization": "Bearer any_token"},
    )
    assert response.status_code == 401


def test_webhook_missing_authorization_header_rejected():
    """Request with no Authorization header must be rejected with 401."""
    raw_client = TestClient(app)

    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_no_auth",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_anon",
            "product_id": "com.coinscan.pro.monthly",
        },
    }
    response = raw_client.post("/v1/webhooks/revenuecat", json=payload)
    assert response.status_code == 401
    assert "missing" in response.json()["detail"].lower() or "unauthorized" in response.json()["detail"].lower()


def test_webhook_invalid_secret_rejected():
    """Wrong signature/secret must be rejected with 401."""
    raw_client = TestClient(app)

    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_invalid_auth",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_bad_actor",
            "product_id": "com.coinscan.pro.monthly",
        },
    }
    response = raw_client.post(
        "/v1/webhooks/revenuecat",
        json=payload,
        headers={"Authorization": "Bearer wrong_secret_xyz"},
    )
    assert response.status_code == 401
    assert "unauthorized" in response.json()["detail"].lower()


def test_webhook_valid_secret_bearer_and_raw():
    """Valid secret accepted both with Bearer prefix and as raw token."""
    raw_client = TestClient(app)

    payload_bearer = {
        "api_version": "1.0",
        "event": {
            "id": "evt_valid_bearer",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_valid_1",
            "product_id": "com.coinscan.pro.monthly",
            "entitlement_ids": ["coinscan_pro"],
        },
    }
    resp1 = raw_client.post(
        "/v1/webhooks/revenuecat",
        json=payload_bearer,
        headers={"Authorization": f"Bearer {TEST_RC_SECRET}"},
    )
    assert resp1.status_code == 200
    assert resp1.json()["status"] == "success"

    payload_raw = {
        "api_version": "1.0",
        "event": {
            "id": "evt_valid_raw",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_valid_2",
            "product_id": "com.coinscan.pro.monthly",
            "entitlement_ids": ["coinscan_pro"],
        },
    }
    resp2 = raw_client.post(
        "/v1/webhooks/revenuecat",
        json=payload_raw,
        headers={"Authorization": TEST_RC_SECRET},
    )
    assert resp2.status_code == 200
    assert resp2.json()["status"] == "success"


def test_webhook_replay_idempotency_behavior():
    """Replay of an existing event_id returns duplicate_ignored without re-processing."""
    raw_client = TestClient(app)

    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_replay_test_100",
            "type": "INITIAL_PURCHASE",
            "app_user_id": "usr_replay_user",
            "product_id": "com.coinscan.pro.monthly",
            "entitlement_ids": ["coinscan_pro"],
        },
    }
    # Initial request
    resp1 = raw_client.post(
        "/v1/webhooks/revenuecat",
        json=payload,
        headers={"Authorization": f"Bearer {TEST_RC_SECRET}"},
    )
    assert resp1.status_code == 200
    assert resp1.json()["status"] == "success"

    # Replay request
    resp2 = raw_client.post(
        "/v1/webhooks/revenuecat",
        json=payload,
        headers={"Authorization": f"Bearer {TEST_RC_SECRET}"},
    )
    assert resp2.status_code == 200
    assert resp2.json()["status"] == "duplicate_ignored"
    assert resp2.json()["action_taken"] == "none"


def test_webhook_anonymous_user_alias_handled_safely():
    """RevenueCat webhooks sending anonymous user aliases (e.g. $RCAnonymousID:...) must not crash with 500."""
    anon_user = "$RCAnonymousID:e8b417c809a149f69ad9e4d5fb7c6d67"
    payload = {
        "api_version": "1.0",
        "event": {
            "id": "evt_anon_alias_test_001",
            "type": "INITIAL_PURCHASE",
            "app_user_id": anon_user,
            "product_id": "com.coinscan.pro.monthly",
            "entitlement_ids": ["pro"],
        },
    }
    response = client.post("/v1/webhooks/revenuecat", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["resolved_tier"] == "pro"
    assert webhook_state.get_user_tier(anon_user) == SubscriptionTier.PRO


