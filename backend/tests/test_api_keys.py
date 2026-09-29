"""
Unit tests for Developer API key generation, SHA-256 validation, and revocation.
"""

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.security.api_key_service import ApiKeyService
from backend.app.security.rate_limit import SubscriptionTier
from backend.app.security.auth import UnifiedAuthenticator

client = TestClient(app)


@pytest.fixture
def fresh_api_key_service():
    return ApiKeyService()


def test_api_key_generation_and_validation(fresh_api_key_service):
    service = fresh_api_key_service
    user_id = "usr_developer_99"

    # 1. Generate new key
    creation = service.generate_key(
        user_id=user_id,
        name="Production Ingestion Key",
        tier=SubscriptionTier.PRO,
    )

    assert creation.raw_api_key.startswith("coinscan_live_")
    assert creation.key_prefix.startswith("coinscan_live_")
    assert creation.tier == SubscriptionTier.PRO

    # 2. Validate raw key
    record = service.validate_key(creation.raw_api_key)
    assert record.user_id == user_id
    assert record.tier == SubscriptionTier.PRO
    assert record.is_active is True
    assert record.last_used_at is not None


def test_api_key_revocation_blocks_access(fresh_api_key_service):
    service = fresh_api_key_service
    user_id = "usr_dev_1"

    creation = service.generate_key(user_id=user_id, name="Temporary Key")
    raw_key = creation.raw_api_key

    # Should validate before revocation
    assert service.validate_key(raw_key).is_active is True

    # Revoke key
    service.revoke_key(creation.key_id, user_id=user_id)

    # Should reject after revocation
    with pytest.raises(HTTPException) as exc_info:
        service.validate_key(raw_key)
    assert exc_info.value.status_code == 401


def test_unified_authenticator_resolves_dynamic_key():
    from backend.app.security.api_key_service import api_key_service

    creation = api_key_service.generate_key(
        user_id="usr_auth_tester",
        name="Test Live Key",
        tier=SubscriptionTier.PRO,
    )

    auth = UnifiedAuthenticator()

    class MockRequest:
        def __init__(self, headers):
            self.headers = headers
            self.client = None

    request = MockRequest({"X-API-Key": creation.raw_api_key})
    caller = auth.resolve_caller(request)

    assert caller.user_id == "usr_auth_tester"
    assert caller.tier == SubscriptionTier.PRO
    assert caller.auth_method == "api_key"
