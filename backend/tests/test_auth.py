"""
Unit tests for API key verification, JWT token resolution, and subscription tier resolution.
"""

import pytest
from fastapi import HTTPException
from backend.app.security.auth import UnifiedAuthenticator
from backend.app.security.jwt_auth import AuthenticatedUser, jwt_verifier
from backend.app.security.rate_limit import SubscriptionTier, InMemoryRateLimiter


class MockRequest:
    def __init__(self, headers=None, client_ip="127.0.0.1"):
        self.headers = headers or {}
        self.client = type("Client", (), {"host": client_ip})()


def test_authenticator_anonymous_when_no_key():
    auth = UnifiedAuthenticator()
    req = MockRequest()
    caller = auth.resolve_caller(req)
    assert caller.tier == SubscriptionTier.ANONYMOUS
    assert caller.is_authenticated is False


def test_authenticator_rejects_invalid_key():
    auth = UnifiedAuthenticator()
    req = MockRequest(headers={"X-API-Key": "sk_invalid_fake_key_999"})
    with pytest.raises(HTTPException) as exc_info:
        auth.resolve_caller(req)
    assert exc_info.value.status_code == 401


def test_jwt_token_resolution():
    jwt_verifier.register_dev_user(
        "token_pro_user",
        AuthenticatedUser(
            user_id="usr_pro_007",
            email="collector@coinscan.app",
            tier=SubscriptionTier.PRO,
            is_authenticated=True,
            auth_method="jwt",
        ),
    )

    auth = UnifiedAuthenticator()
    req = MockRequest(headers={"Authorization": "Bearer token_pro_user"})
    caller = auth.resolve_caller(req)

    assert caller.user_id == "usr_pro_007"
    assert caller.tier == SubscriptionTier.PRO
    assert caller.is_authenticated is True


def test_rate_limiter_tier_aware_thresholds():
    limiter = InMemoryRateLimiter(default_rpm=2)

    # 1. Anonymous IP throttling at 2 rpm
    client_ip = "192.168.1.100"
    limiter.check_rate_limit(client_ip, tier=SubscriptionTier.ANONYMOUS)
    limiter.check_rate_limit(client_ip, tier=SubscriptionTier.ANONYMOUS)

    with pytest.raises(HTTPException) as exc:
        limiter.check_rate_limit(client_ip, tier=SubscriptionTier.ANONYMOUS)
    assert exc.value.status_code == 429

    # 2. Pro tier receives elevated IP limit
    pro_ip = "192.168.1.101"
    for _ in range(5):
        limiter.check_rate_limit(pro_ip, tier=SubscriptionTier.PRO)
