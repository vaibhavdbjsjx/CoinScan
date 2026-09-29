"""
Unit tests for Phase 10: Feedback, Account Deletion, Data Export, Collection Vault & IDOR Security.
"""

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.api.feedback import feedback_store
from backend.app.api.account import account_store
from backend.app.security.jwt_auth import AuthenticatedUser, jwt_verifier
from backend.app.security.rate_limit import SubscriptionTier

client = TestClient(app)


@pytest.fixture(autouse=True)
def setup_phase10_test_state():
    feedback_store.reset_for_test()
    account_store.reset_for_test()

    # Register test users
    jwt_verifier.register_dev_user(
        "token_alice",
        AuthenticatedUser(
            user_id="usr_alice_42",
            email="alice@coinscan.app",
            tier=SubscriptionTier.FREE,
            is_authenticated=True,
            auth_method="jwt",
        ),
    )
    jwt_verifier.register_dev_user(
        "token_bob",
        AuthenticatedUser(
            user_id="usr_bob_99",
            email="bob@coinscan.app",
            tier=SubscriptionTier.PRO,
            is_authenticated=True,
            auth_method="jwt",
        ),
    )
    account_store.record_consent("usr_alice_42", "1.0.0", "1.0.0")
    account_store.record_consent("usr_bob_99", "1.0.0", "1.0.0")
    yield
    feedback_store.reset_for_test()
    account_store.reset_for_test()



def test_feedback_submission_and_rate_limiting():
    # 1. Valid feedback submission
    payload = {
        "category": "recognition_incorrect",
        "title": "Morgan Dollar Mint Mark Misread",
        "description": "The scan identified the mint mark as S instead of CC on an 1882 dollar.",
        "app_version": "1.0.0",
        "platform": "ios",
    }
    response = client.post(
        "/v1/feedback",
        json=payload,
        headers={"Authorization": "Bearer token_alice"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert "feedback_id" in data

    # 2. Rate limit test (submit 5 more to trigger 429)
    for _ in range(4):
        resp = client.post(
            "/v1/feedback",
            json=payload,
            headers={"Authorization": "Bearer token_alice"},
        )
        assert resp.status_code == 200

    # 6th submission should exceed limit
    blocked_resp = client.post(
        "/v1/feedback",
        json=payload,
        headers={"Authorization": "Bearer token_alice"},
    )
    assert blocked_resp.status_code == 429


def test_collection_vault_lifecycle_and_idor_protection():
    # 1. Alice adds a coin to her vault
    item_payload = {
        "coin_name": "1882-CC Morgan Silver Dollar",
        "country": "United States",
        "denomination": "$1",
        "year": 1882,
        "mint_mark": "CC",
        "grade": "MS65",
        "purchase_price": 650.0,
        "notes": "Beautiful Gilded Age strike",
    }
    add_resp = client.post(
        "/v1/collection",
        json=item_payload,
        headers={"Authorization": "Bearer token_alice"},
    )
    assert add_resp.status_code == 200
    item_id = add_resp.json()["id"]
    assert add_resp.json()["user_id"] == "usr_alice_42"

    # 2. Alice lists her collection -> item is present
    list_alice = client.get(
        "/v1/collection",
        headers={"Authorization": "Bearer token_alice"},
    )
    assert list_alice.status_code == 200
    assert len(list_alice.json()) == 1
    assert list_alice.json()[0]["id"] == item_id

    # 3. IDOR Check: Bob lists his collection -> Alice's item is NOT visible
    list_bob = client.get(
        "/v1/collection",
        headers={"Authorization": "Bearer token_bob"},
    )
    assert list_bob.status_code == 200
    assert len(list_bob.json()) == 0

    # 4. IDOR Check: Bob attempts to delete Alice's coin item -> Rejected 404
    delete_bob = client.delete(
        f"/v1/collection/{item_id}",
        headers={"Authorization": "Bearer token_bob"},
    )
    assert delete_bob.status_code == 404

    # 5. Alice deletes her own coin item -> Success
    delete_alice = client.delete(
        f"/v1/collection/{item_id}",
        headers={"Authorization": "Bearer token_alice"},
    )
    assert delete_alice.status_code == 200


def test_account_deletion_and_cascading_cleanup():
    # 1. Alice creates collection items
    client.post(
        "/v1/collection",
        json={
            "coin_name": "1907 Saint-Gaudens Double Eagle",
            "country": "United States",
            "denomination": "$20",
            "purchase_price": 28500.0,
        },
        headers={"Authorization": "Bearer token_alice"},
    )

    # 2. Rejection on confirmation phrase mismatch
    bad_delete = client.post(
        "/v1/account/delete",
        json={"confirm_phrase": "NO", "reason": "Testing"},
        headers={"Authorization": "Bearer token_alice"},
    )
    assert bad_delete.status_code == 400

    # 3. Successful account deletion with exact phrase
    good_delete = client.post(
        "/v1/account/delete",
        json={"confirm_phrase": "DELETE MY ACCOUNT", "reason": "Moving platforms"},
        headers={"Authorization": "Bearer token_alice"},
    )
    assert good_delete.status_code == 200
    assert good_delete.json()["status"] == "success"
    assert good_delete.json()["items_purged"]["collection_items"] == 1

    # 4. Verify collection is completely empty and consent is purged after deletion
    post_delete_list = client.get(
        "/v1/collection",
        headers={"Authorization": "Bearer token_alice"},
    )
    assert post_delete_list.status_code == 403
    assert len(account_store.get_collection_items("usr_alice_42")) == 0



def test_data_export_endpoint():
    # Alice requests data export
    resp = client.get(
        "/v1/account/export",
        headers={"Authorization": "Bearer token_alice"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "user_profile" in data
    assert "collection_items" in data
    assert "scan_history" in data
    assert data["entitlements"]["tier"] == "free"
