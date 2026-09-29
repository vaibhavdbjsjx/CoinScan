"""
Unit tests for server-authoritative scan quota enforcement and concurrency control.
"""

import pytest
import asyncio
from fastapi import HTTPException

from backend.app.security.quota_service import QuotaEngine
from backend.app.security.rate_limit import SubscriptionTier


@pytest.fixture
def fresh_quota_engine():
    engine = QuotaEngine()
    engine.reset_usage_for_test()
    return engine


@pytest.mark.asyncio
async def test_sequential_free_tier_quota_exhaustion(fresh_quota_engine):
    engine = fresh_quota_engine
    user_id = "usr_free_collector_1"

    # Scan 1: Allowed (2 remaining)
    rem1 = await engine.check_and_consume_quota(user_id, tier=SubscriptionTier.FREE)
    assert rem1 == 2
    assert engine.get_current_usage(user_id) == 1

    # Scan 2: Allowed (1 remaining)
    rem2 = await engine.check_and_consume_quota(user_id, tier=SubscriptionTier.FREE)
    assert rem2 == 1
    assert engine.get_current_usage(user_id) == 2

    # Scan 3: Allowed (0 remaining)
    rem3 = await engine.check_and_consume_quota(user_id, tier=SubscriptionTier.FREE)
    assert rem3 == 0
    assert engine.get_current_usage(user_id) == 3

    # Scan 4: Exceeded -> HTTP 429
    with pytest.raises(HTTPException) as exc_info:
        await engine.check_and_consume_quota(user_id, tier=SubscriptionTier.FREE)
    assert exc_info.value.status_code == 429
    assert exc_info.value.detail["error"] == "daily_quota_exceeded"
    assert exc_info.value.detail["limit"] == 3


@pytest.mark.asyncio
async def test_concurrent_scan_requests_quota_lock(fresh_quota_engine):
    """
    Simulates 10 concurrent requests sent at the exact same millisecond.
    Guarantees that exactly 3 succeed for Free tier and exactly 7 are rejected with 429.
    """
    engine = fresh_quota_engine
    user_id = "usr_concurrent_tester"

    async def make_request():
        try:
            await engine.check_and_consume_quota(user_id, tier=SubscriptionTier.FREE)
            return "success"
        except HTTPException as e:
            if e.status_code == 429:
                return "quota_exceeded"
            return "other_error"

    # Launch 10 simultaneous concurrent requests
    results = await asyncio.gather(*[make_request() for _ in range(10)])

    successes = results.count("success")
    quota_blocks = results.count("quota_exceeded")

    assert successes == 3, f"Expected exactly 3 allowed scans, but got {successes}"
    assert quota_blocks == 7, f"Expected exactly 7 blocked scans, but got {quota_blocks}"
    assert engine.get_current_usage(user_id) == 3


@pytest.mark.asyncio
async def test_pro_tier_fair_use_capacity(fresh_quota_engine):
    engine = fresh_quota_engine
    user_id = "usr_pro_dealer"

    # Consuming 50 scans should succeed smoothly
    for i in range(50):
        await engine.check_and_consume_quota(user_id, tier=SubscriptionTier.PRO)

    assert engine.get_current_usage(user_id) == 50
