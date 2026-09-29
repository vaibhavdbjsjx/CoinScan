"""
Phase 11 End-to-End Security, Identity & Multi-Tenant Isolation Test Suite.
"""

import pytest
import asyncio
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.api.feedback import feedback_store
from backend.app.api.account import account_store
from backend.app.security.jwt_auth import AuthenticatedUser, jwt_verifier
from backend.app.security.auth import UnifiedAuthenticator
from backend.app.security.rate_limit import SubscriptionTier
from backend.app.security.quota_service import QuotaEngine

client = TestClient(app)


class MockRequest:
    def __init__(self, headers=None, client_ip="127.0.0.1"):
        self.headers = headers or {}
        self.client = type("Client", (), {"host": client_ip})()


@pytest.fixture(autouse=True)
def setup_phase11_security_context():
    feedback_store.reset_for_test()
    account_store.reset_for_test()

    jwt_verifier.register_dev_user(
        "token_charlie_free",
        AuthenticatedUser(
            user_id="usr_charlie_11",
            email="charlie@coinscan.app",
            tier=SubscriptionTier.FREE,
            is_authenticated=True,
            auth_method="jwt",
        ),
    )
    jwt_verifier.register_dev_user(
        "token_diana_pro",
        AuthenticatedUser(
            user_id="usr_diana_99",
            email="diana@coinscan.app",
            tier=SubscriptionTier.PRO,
            is_authenticated=True,
            auth_method="jwt",
        ),
    )
    account_store.record_consent("usr_charlie_11", "1.0.0", "1.0.0")
    account_store.record_consent("usr_diana_99", "1.0.0", "1.0.0")
    yield
    feedback_store.reset_for_test()
    account_store.reset_for_test()



def test_client_tier_spoofing_rejected():
    """Client asserting 'X-Tier: pro' header without valid credentials MUST be treated as anonymous."""
    auth = UnifiedAuthenticator()
    spoofed_req = MockRequest(headers={"X-Tier": "pro", "X-Subscription": "active"})
    caller = auth.resolve_caller(spoofed_req)

    assert caller.tier == SubscriptionTier.ANONYMOUS
    assert caller.is_authenticated is False


def test_protected_endpoints_require_authentication():
    """Accessing export, account deletion, or collection without token yields 401."""
    # 1. Export without auth
    resp_export = client.get("/v1/account/export")
    assert resp_export.status_code == 401

    # 2. Deletion without auth
    resp_delete = client.post(
        "/v1/account/delete",
        json={"confirm_phrase": "DELETE MY ACCOUNT"},
    )
    assert resp_delete.status_code == 401

    # 3. Collection without auth
    resp_collection = client.get("/v1/collection")
    assert resp_collection.status_code == 401


def test_multi_tenant_vault_and_export_isolation():
    """Guarantees User Charlie cannot view, mutate, or export User Diana's collection items."""
    # 1. Diana adds a valuable coin to her vault
    diana_coin = {
        "coin_name": "1794 Flowing Hair Silver Dollar",
        "country": "United States",
        "denomination": "$1",
        "year": 1794,
        "grade": "VF35",
        "purchase_price": 450000.0,
        "notes": "Rare early American silver issue",
    }
    diana_resp = client.post(
        "/v1/collection",
        json=diana_coin,
        headers={"Authorization": "Bearer token_diana_pro"},
    )
    assert diana_resp.status_code == 200
    coin_id = diana_resp.json()["id"]

    # 2. Charlie requests his collection -> Diana's coin MUST NOT appear
    charlie_list = client.get(
        "/v1/collection",
        headers={"Authorization": "Bearer token_charlie_free"},
    )
    assert charlie_list.status_code == 200
    assert len(charlie_list.json()) == 0

    # 3. Charlie attempts to delete Diana's coin -> 404 Not Found (IDOR prevention)
    charlie_del = client.delete(
        f"/v1/collection/{coin_id}",
        headers={"Authorization": "Bearer token_charlie_free"},
    )
    assert charlie_del.status_code == 404

    # 4. Charlie requests data export -> Contains zero records of Diana's items
    charlie_export = client.get(
        "/v1/account/export",
        headers={"Authorization": "Bearer token_charlie_free"},
    )
    assert charlie_export.status_code == 200
    assert len(charlie_export.json()["collection_items"]) == 0


@pytest.mark.asyncio
async def test_quota_concurrency_race_prevention():
    """Concurrent parallel scan requests must be strictly limited to the free tier capacity (3 scans)."""
    engine = QuotaEngine()
    user_id = "usr_race_test_user"

    async def consume_one():
        try:
            return await engine.check_and_consume_quota(user_id, SubscriptionTier.FREE)
        except Exception as e:
            return e

    # Launch 10 simultaneous scan requests
    results = await asyncio.gather(*[consume_one() for _ in range(10)])

    # Exactly 3 requests must succeed (returning 1, 2, 3)
    successes = [r for r in results if isinstance(r, int)]
    failures = [r for r in results if not isinstance(r, int)]

    assert len(successes) == 3
    assert len(failures) == 7
