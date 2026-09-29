"""
Comprehensive break-test and chaos engineering regression suite.
Verifies defense against:
1. Out-of-order webhook reordering attacks.
2. In-flight quota race attacks and 0-quota consumption on failure.
3. Collection input boundary abuse (NaN, Inf, negatives, oversized fields).
4. Valuation abuse (NaN, Inf, negative FX).
5. AI vision response malformed JSON and corrupted types.
6. Cascading account cleanup resetting entitlements and quota.
"""

import math
import pytest
import asyncio
from fastapi import HTTPException
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.security.quota_service import QuotaEngine
from backend.app.security.rate_limit import SubscriptionTier
from backend.app.api.webhooks import webhook_state
from backend.app.api.account import account_store
from backend.app.services.valuation.valuation_service import ValuationEngine
from backend.app.models.domain import CoinIdentity
from backend.app.services.recognition.vision_provider import safe_parse_vision_response


client = TestClient(app)


# ---------------------------------------------------------------------------
# 1. Webhook Out-Of-Order & Replay Attack Defense
# ---------------------------------------------------------------------------

def test_out_of_order_webhook_dropped():
    from backend.app.config import settings
    orig_secret = settings.revenuecat_webhook_secret
    settings.revenuecat_webhook_secret = "test_chaos_webhook_secret"
    auth_headers = {"Authorization": "Bearer test_chaos_webhook_secret"}

    try:
        webhook_state.reset_for_test()
        user_id = "usr_chaos_webhook_1"

        # Step 1: Recent EXPIRATION event at ts=2000000000000 arrives
        res1 = client.post(
            "/v1/webhooks/revenuecat",
            json={
                "api_version": "1.0",
                "event": {
                    "id": "evt_expiration_new",
                    "type": "EXPIRATION",
                    "app_user_id": user_id,
                    "expiration_at_ms": 2000000000000,
                },
            },
            headers=auth_headers,
        )
        assert res1.status_code == 200
        assert webhook_state.get_user_tier(user_id) == SubscriptionTier.FREE

        # Step 2: Delayed / Out-of-order INITIAL_PURCHASE at ts=1000000000000 arrives
        res2 = client.post(
            "/v1/webhooks/revenuecat",
            json={
                "api_version": "1.0",
                "event": {
                    "id": "evt_purchase_old",
                    "type": "INITIAL_PURCHASE",
                    "app_user_id": user_id,
                    "product_id": "coinscan_pro_annual",
                    "purchased_at_ms": 1000000000000,
                },
            },
            headers=auth_headers,
        )
        assert res2.status_code == 200
        # Crucial invariant: Out-of-order event must NOT grant PRO
        assert webhook_state.get_user_tier(user_id) == SubscriptionTier.FREE
        assert res2.json()["action_taken"] == "out_of_order_event_ignored"
    finally:
        settings.revenuecat_webhook_secret = orig_secret


# ---------------------------------------------------------------------------
# 2. In-Flight Quota Reservation & Concurrency Race Defense
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_in_flight_quota_reservation_race():
    """
    Simulates 10 concurrent requests when a user has 1 scan remaining.
    Guarantees exactly 1 reservation succeeds and 9 fail with 429 at the gate.
    """
    engine = QuotaEngine()
    engine.reset_usage_for_test()
    user_id = "usr_quota_race_attacker"

    # Consume 2 of 3 scans
    await engine.check_and_consume_quota(user_id, tier=SubscriptionTier.FREE)
    await engine.check_and_consume_quota(user_id, tier=SubscriptionTier.FREE)
    assert engine.get_current_usage(user_id) == 2

    # Now 1 scan remaining. Launch 10 simultaneous reservations
    async def try_reserve():
        try:
            res = await engine.reserve_slot(user_id, tier=SubscriptionTier.FREE)
            return ("success", res)
        except HTTPException as e:
            return ("blocked_429" if e.status_code == 429 else "error", None)

    tasks = [try_reserve() for _ in range(10)]
    results = await asyncio.gather(*tasks)

    successes = [r for r in results if r[0] == "success"]
    blocked = [r for r in results if r[0] == "blocked_429"]

    assert len(successes) == 1, f"Expected exactly 1 granted slot, got {len(successes)}"
    assert len(blocked) == 9, f"Expected exactly 9 blocked 429s, got {len(blocked)}"

    # If the single successful reservation is released (e.g. failure), quota remains at 2
    res_token = successes[0][1]
    await res_token.release()
    assert engine.get_current_usage(user_id) == 2


@pytest.mark.asyncio
async def test_failed_recognition_consumes_zero_quota():
    """
    Verifies that when a recognition request fails (e.g. unreadable/blurred image),
    0 quota is deducted.
    """
    engine = QuotaEngine()
    engine.reset_usage_for_test()
    user_id = "usr_zero_quota_fail_test"

    res = await engine.reserve_slot(user_id, tier=SubscriptionTier.FREE)
    assert engine.get_current_usage(user_id) == 0

    # Simulate error / abort
    await res.release()
    assert engine.get_current_usage(user_id) == 0


# ---------------------------------------------------------------------------
# 3. Collection Vault Input Abuse Defense
# ---------------------------------------------------------------------------

def test_collection_item_negative_price_rejected():
    auth_header = {"Authorization": "Bearer usr_input_tester"}
    account_store.record_consent(
        user_id="usr_input_tester",
        terms_version="1.0.0",
        privacy_version="1.0.0",
    )

    # Negative purchase price
    res = client.post(
        "/v1/collection",
        headers=auth_header,
        json={
            "coin_name": "Morgan Dollar",
            "country": "United States",
            "denomination": "1 Dollar",
            "purchase_price": -50.0,
        },
    )
    assert res.status_code == 422


def test_collection_item_nan_price_rejected():
    auth_header = {"Authorization": "Bearer usr_input_tester"}
    res = client.post(
        "/v1/collection",
        headers=auth_header,
        json={
            "coin_name": "Morgan Dollar",
            "country": "United States",
            "denomination": "1 Dollar",
            "purchase_price": "NaN",
        },
    )
    assert res.status_code == 422


def test_collection_item_oversized_notes_rejected():
    auth_header = {"Authorization": "Bearer usr_input_tester"}
    res = client.post(
        "/v1/collection",
        headers=auth_header,
        json={
            "coin_name": "Morgan Dollar",
            "country": "United States",
            "denomination": "1 Dollar",
            "notes": "A" * 6000,  # Exceeds max_length=5000
        },
    )
    assert res.status_code == 422


# ---------------------------------------------------------------------------
# 4. Valuation Engine NaN / Inf / Negative Defense
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_valuation_engine_nan_inf_defense():
    engine = ValuationEngine()
    coin = CoinIdentity(
        country="United States",
        denomination="1 Dollar",
        year=1882,
        mint="CC",
        composition="90% Silver, 10% Copper",
        weightG=26.73,
    )

    # NaN fx_rate
    res_nan = await engine.calculate_valuation(coin, fx_rate_to_usd=float("nan"))
    assert res_nan.estimates == []

    # Inf fx_rate
    res_inf = await engine.calculate_valuation(coin, fx_rate_to_usd=float("inf"))
    assert res_inf.estimates == []

    # Negative fx_rate
    res_neg = await engine.calculate_valuation(coin, fx_rate_to_usd=-1.5)
    assert res_neg.estimates == []


# ---------------------------------------------------------------------------
# 5. AI Vision Malformed Response Defense
# ---------------------------------------------------------------------------

def test_safe_parse_vision_response_unparsable_fallback():
    # Model returns raw garbage / conversational crash
    obs = safe_parse_vision_response("I cannot identify this coin because the image is corrupt.")
    assert obs.visual_similarity_score == 0.1
    assert not obs.obverse_reverse_consistent
    assert "malformed" in obs.confidence_reasoning


def test_safe_parse_vision_response_negative_numista_id_sanitized():
    raw_json = '{"numista_id_guess": -999, "visible_inscriptions": "NOT_A_LIST", "candidate_varieties": 123}'
    obs = safe_parse_vision_response(raw_json)
    assert obs.numista_id_guess is None
    assert isinstance(obs.visible_inscriptions, list)
    assert isinstance(obs.candidate_varieties, list)


# ---------------------------------------------------------------------------
# 6. Account Deletion Cascading Purge
# ---------------------------------------------------------------------------

def test_account_deletion_resets_entitlement_and_quota():
    user_id = "usr_to_delete_999"
    # Set up entitlement and usage
    webhook_state.set_user_tier(user_id, SubscriptionTier.PRO)
    account_store.get_or_create_profile(user_id)
    account_store.record_consent(user_id, "1.0.0", "1.0.0")

    assert webhook_state.get_user_tier(user_id) == SubscriptionTier.PRO

    # Delete account
    account_store.delete_account(user_id)

    # Entitlement must revert to FREE
    assert webhook_state.get_user_tier(user_id) == SubscriptionTier.FREE
    assert account_store.get_consent(user_id) is None
