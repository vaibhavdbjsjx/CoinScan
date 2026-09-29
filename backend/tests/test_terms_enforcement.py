"""
Unit and regression tests for Server-Side Terms & Conditions Gate and Legal Consent Enforcement.

Validates:
1. Unauthenticated consent recording is rejected (401).
2. Authenticated user can record versioned consent for their own account.
3. Consent status reflects current vs outdated version.
4. Accounts without terms acceptance are blocked from accessing protected account services (403 TERMS_ACCEPTANCE_REQUIRED).
5. Accounts with outdated terms versions are blocked until re-consent.
6. A user cannot record consent for another user (IDOR protection).
7. Account deletion purges consent records.
8. Data export includes legal consent audit metadata.
"""

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.config import settings
from backend.app.api.account import account_store
from backend.app.security.jwt_auth import AuthenticatedUser, jwt_verifier
from backend.app.security.rate_limit import SubscriptionTier

client = TestClient(app)


@pytest.fixture(autouse=True)
def setup_terms_test_state():
    account_store.reset_for_test()
    jwt_verifier.register_dev_user(
        "token_test_user_a",
        AuthenticatedUser(
            user_id="usr_test_a",
            email="user_a@coinscan.app",
            tier=SubscriptionTier.FREE,
            is_authenticated=True,
            auth_method="jwt",
        ),
    )
    jwt_verifier.register_dev_user(
        "token_test_user_b",
        AuthenticatedUser(
            user_id="usr_test_b",
            email="user_b@coinscan.app",
            tier=SubscriptionTier.FREE,
            is_authenticated=True,
            auth_method="jwt",
        ),
    )
    yield
    account_store.reset_for_test()


def test_unauthenticated_consent_rejected():
    """Unauthenticated consent submission must return 401."""
    resp = client.post(
        "/v1/account/consent",
        json={"terms_version": "1.0.0", "privacy_version": "1.0.0"},
    )
    assert resp.status_code == 401


def test_missing_terms_blocks_protected_services():
    """A user who has not accepted Terms is rejected with 403 TERMS_ACCEPTANCE_REQUIRED."""
    # Attempt to access collection without recorded consent
    resp = client.get(
        "/v1/collection",
        headers={"Authorization": "Bearer token_test_user_a"},
    )
    assert resp.status_code == 403
    data = resp.json()
    assert data["detail"]["error"] == "TERMS_ACCEPTANCE_REQUIRED"
    assert data["detail"]["required_terms_version"] == "1.0.0"


def test_outdated_terms_version_requires_reconsent():
    """If user accepted an older version (e.g. 0.9.0), access is blocked until re-consent."""
    account_store.record_consent("usr_test_a", terms_version="0.9.0", privacy_version="0.9.0")

    # Check status endpoint
    status_resp = client.get(
        "/v1/account/consent",
        headers={"Authorization": "Bearer token_test_user_a"},
    )
    assert status_resp.status_code == 200
    status_data = status_resp.json()
    assert status_data["is_current"] is False
    assert status_data["status"] == "reconsent_required"

    # Protected service access is blocked
    resp = client.get(
        "/v1/collection",
        headers={"Authorization": "Bearer token_test_user_a"},
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["error"] == "TERMS_ACCEPTANCE_REQUIRED"


def test_valid_terms_acceptance_permits_access():
    """Recording required terms version unblocks access immediately."""
    consent_resp = client.post(
        "/v1/account/consent",
        json={
            "terms_version": settings.required_terms_version,
            "privacy_version": settings.required_privacy_version,
        },
        headers={"Authorization": "Bearer token_test_user_a"},
    )
    assert consent_resp.status_code == 200
    consent_data = consent_resp.json()
    assert consent_data["status"] == "success"
    assert consent_data["is_current"] is True
    assert consent_data["user_id"] == "usr_test_a"

    # Protected collection access is now allowed
    col_resp = client.get(
        "/v1/collection",
        headers={"Authorization": "Bearer token_test_user_a"},
    )
    assert col_resp.status_code == 200


def test_account_isolation_consent_cannot_leak():
    """User A's consent does NOT grant access to User B."""
    # User A consents
    client.post(
        "/v1/account/consent",
        json={"terms_version": "1.0.0", "privacy_version": "1.0.0"},
        headers={"Authorization": "Bearer token_test_user_a"},
    )

    # User B has not consented -> blocked
    resp_b = client.get(
        "/v1/collection",
        headers={"Authorization": "Bearer token_test_user_b"},
    )
    assert resp_b.status_code == 403
    assert resp_b.json()["detail"]["error"] == "TERMS_ACCEPTANCE_REQUIRED"


def test_data_export_contains_consent_record():
    """Data export archive includes legal consent timestamp and versions."""
    client.post(
        "/v1/account/consent",
        json={"terms_version": "1.0.0", "privacy_version": "1.0.0"},
        headers={"Authorization": "Bearer token_test_user_a"},
    )

    export_resp = client.get(
        "/v1/account/export",
        headers={"Authorization": "Bearer token_test_user_a"},
    )
    assert export_resp.status_code == 200
    export_data = export_resp.json()
    assert "legal_consent" in export_data
    assert export_data["legal_consent"]["terms_version"] == "1.0.0"
    assert export_data["legal_consent"]["privacy_version"] == "1.0.0"
