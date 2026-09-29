"""
Unified Authentication & Identity Resolution for CoinScan API.

Supports:
1. JWT Bearer Tokens: Mobile App / Web user authentication via Supabase Auth.
2. Developer API Keys: Cryptographic API keys (coinscan_live_...) with SHA-256 validation.
3. Legacy/Dev Keys: Static dev API keys configured via API_KEYS_JSON.
4. Anonymous / Unauthenticated Client fallback with strict rate/quota throttling.

Guarantees:
- Client-asserted headers like 'X-Tier: pro' are IGNORED.
- Tiers are server-authoritative.
"""

import json
import logging
from typing import Optional
from fastapi import Request, HTTPException, status, Depends

from backend.app.config import settings
from backend.app.security.rate_limit import SubscriptionTier
from backend.app.security.jwt_auth import AuthenticatedUser, jwt_verifier
from backend.app.security.api_key_service import api_key_service

logger = logging.getLogger("coinscan.auth")


class UnifiedAuthenticator:
    """Resolves identity and tier from either JWT Bearer tokens or API keys."""

    def __init__(self):
        self._dev_key_map: dict[str, SubscriptionTier] = {}
        self._load_legacy_dev_keys()

    def _load_legacy_dev_keys(self):
        raw = settings.api_keys_json
        if raw:
            try:
                parsed = json.loads(raw)
                for key, tier_name in parsed.items():
                    try:
                        self._dev_key_map[key] = SubscriptionTier(tier_name)
                    except ValueError:
                        pass
            except Exception as e:
                logger.error(f"Failed to load API_KEYS_JSON: {e}")

        if settings.api_secret:
            self._dev_key_map[settings.api_secret] = SubscriptionTier.PRO

    def resolve_caller(self, request: Request) -> AuthenticatedUser:
        """Extracts and verifies caller identity from Request headers."""
        # 1. Check Authorization: Bearer <token> (Mobile App / Supabase Auth)
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.lower().startswith("bearer "):
            user = jwt_verifier.verify_token(auth_header)
            if user:
                return user

        # 2. Check X-API-Key (Developer API or Mobile App API key)
        api_key = request.headers.get("X-API-Key") or request.headers.get("X-API-Secret")
        if api_key:
            # Check dynamic developer API keys (coinscan_live_...)
            if api_key.startswith("coinscan_"):
                key_record = api_key_service.validate_key(api_key)
                return AuthenticatedUser(
                    user_id=key_record.user_id,
                    tier=key_record.tier,
                    is_authenticated=True,
                    auth_method="api_key",
                )

            # Check legacy/dev static key map. These shared static secrets map to a paid
            # tier without a user account; if one were shipped inside a mobile build it
            # could be extracted, so they are never honoured in production.
            if api_key in self._dev_key_map:
                if settings.app_env == "production":
                    logger.warning("Rejected legacy static API key in production (API_SECRET/API_KEYS_JSON).")
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Invalid or revoked API key.",
                    )
                tier = self._dev_key_map[api_key]
                return AuthenticatedUser(
                    user_id=f"dev_key_{api_key[:6]}",
                    tier=tier,
                    is_authenticated=True,
                    auth_method="api_key",
                )

            # Unknown API Key
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or revoked API key.",
            )

        # 3. Fallback to Anonymous / Unauthenticated Client (IP-based identity)
        client_ip = request.client.host if request.client else "127.0.0.1"
        return AuthenticatedUser(
            user_id=f"anon_ip_{client_ip}",
            tier=SubscriptionTier.ANONYMOUS,
            is_authenticated=False,
            auth_method="anonymous",
        )


_unified_authenticator = UnifiedAuthenticator()


async def get_current_user(request: Request) -> AuthenticatedUser:
    """FastAPI dependency resolving authenticated user context."""
    user = _unified_authenticator.resolve_caller(request)
    if user.is_authenticated and user.auth_method == "jwt":
        from backend.app.api.webhooks import webhook_state
        db_tier = await webhook_state.get_user_tier_async(user.user_id)
        if db_tier != user.tier:
            user.tier = db_tier
    return user


async def verify_terms_accepted(
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> AuthenticatedUser:
    """Enforces that authenticated users have accepted the required Terms version.

    If unauthenticated (anonymous guest), bypasses to allow guest browsing.
    If authenticated via developer API key, bypasses consumer legal consent.
    If authenticated via JWT without current terms acceptance, raises 403 Forbidden with TERMS_ACCEPTANCE_REQUIRED.
    """
    if not current_user.is_authenticated:
        return current_user

    if current_user.auth_method == "api_key":
        return current_user

    from backend.app.api.account import account_store
    consent = await account_store.get_consent_async(current_user.user_id)
    if not consent or consent.get("terms_version") != settings.required_terms_version:
        logger.warning(
            f"Terms acceptance gate blocked user '{current_user.user_id}': "
            f"has '{consent.get('terms_version') if consent else 'none'}', "
            f"requires '{settings.required_terms_version}'."
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": "TERMS_ACCEPTANCE_REQUIRED",
                "message": f"You must accept CoinScan Terms & Conditions version {settings.required_terms_version} before accessing this service.",
                "required_terms_version": settings.required_terms_version,
                "required_privacy_version": settings.required_privacy_version,
            },
        )
    return current_user


async def verify_api_key(request: Request) -> SubscriptionTier:
    """Backwards-compatible FastAPI dependency returning resolved SubscriptionTier."""
    user = _unified_authenticator.resolve_caller(request)
    return user.tier

