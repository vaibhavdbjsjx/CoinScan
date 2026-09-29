"""
Server-authoritative JWT authentication and user context resolution.

Verifies Supabase / OAuth JWT tokens passed via Authorization: Bearer <token>
header, extracting user identity, email, and authenticating server context.
Rejects spoofed client-claimed tiers or tampering.
"""

import time
import logging
from typing import Optional
import jwt
from jwt.exceptions import (
    PyJWTError,
    ExpiredSignatureError,
    InvalidSignatureError,
    DecodeError,
    InvalidTokenError,
    InvalidIssuerError,
)
from pydantic import BaseModel
from fastapi import Request, HTTPException, status, Header

from backend.app.config import settings
from backend.app.security.rate_limit import SubscriptionTier

logger = logging.getLogger("coinscan.auth.jwt")


class AuthenticatedUser(BaseModel):
    user_id: str
    email: Optional[str] = None
    tier: SubscriptionTier = SubscriptionTier.FREE
    is_authenticated: bool = True
    auth_method: str = "jwt"  # "jwt", "api_key", "anonymous"


class JwtAuthVerifier:
    """Verifies JWT bearer tokens and resolves user identity."""

    def __init__(self):
        # In-memory mock store for local/dev and unit tests when Supabase is not attached
        self._dev_users: dict[str, AuthenticatedUser] = {}

    def register_dev_user(self, token: str, user: AuthenticatedUser):
        """Helper to register user tokens for testing and offline development."""
        self._dev_users[token] = user

    def _get_verification_key_and_algorithms(self, unverified_header: dict) -> tuple[Optional[str], list[str]]:
        """Resolves the cryptographic verification key and allowed algorithms.

        Supports symmetric signing (HS256 with SUPABASE_JWT_SECRET) and
        asymmetric signing (RS256/ES256 with SUPABASE_JWT_PUBLIC_KEY or PEM secret).
        """
        configured_alg = settings.supabase_jwt_algorithm
        pub_key = settings.supabase_jwt_public_key
        secret = settings.supabase_jwt_secret

        if pub_key:
            allowed_algs = [configured_alg] if configured_alg else ["RS256", "RS384", "RS512", "ES256", "ES384", "ES512"]
            return pub_key, allowed_algs

        if secret and secret.strip().startswith("-----BEGIN"):
            allowed_algs = [configured_alg] if configured_alg else ["RS256", "RS384", "RS512", "ES256", "ES384", "ES512"]
            return secret, allowed_algs

        if secret:
            allowed_algs = [configured_alg] if configured_alg else ["HS256", "HS384", "HS512"]
            return secret, allowed_algs

        return None, []

    def verify_token(self, token: Optional[str]) -> Optional[AuthenticatedUser]:
        """Verify JWT token and extract user context.

        In production:
        - Strict cryptographic signature, expiration, and claims verification.
        - Fails closed with 401 if token is invalid, expired, malformed, or forged.
        - No prefix-based or mock-token bypasses are allowed in production.

        In non-production:
        - Supports mock registered tokens and dev prefixes (usr_, dev_, jwt_token_).
        - Also verifies cryptographic JWTs if provided.
        """
        if not token:
            return None

        # Clean token format (e.g. strip "Bearer ")
        clean_token = token.strip()
        if clean_token.lower().startswith("bearer "):
            clean_token = clean_token[7:].strip()

        if not clean_token:
            return None

        is_production = (settings.app_env == "production")

        # LOCAL-DEVELOPMENT ONLY BYPASSES. Never on staging or on a hosted platform
        # (Cloud Run / Render), even if APP_ENV was left at its "development" default.
        if settings.is_local_development:
            if clean_token in self._dev_users:
                return self._dev_users[clean_token]

            if (
                clean_token.startswith("usr_")
                or clean_token.startswith("dev_")
                or clean_token.startswith("jwt_token_")
            ):
                effective_user_id = (
                    clean_token[10:] if clean_token.startswith("jwt_token_") else clean_token
                )
                from backend.app.api.webhooks import webhook_state
                active_tier = webhook_state.get_user_tier(effective_user_id)
                return AuthenticatedUser(
                    user_id=effective_user_id,
                    email=f"{effective_user_id}@coinscan.app",
                    tier=active_tier,
                    is_authenticated=True,
                    auth_method="jwt",
                )

        # In production, prefix bypasses are explicitly rejected
        # (clean_token will attempt JWT parsing and fail with 401 if not a valid JWT)

        # Parse JWT header
        try:
            unverified_header = jwt.get_unverified_header(clean_token)
        except PyJWTError as e:
            if is_production:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail=f"Malformed authentication token: {e}",
                )
            return None
        except Exception:
            if is_production:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Malformed authentication token.",
                )
            return None

        key, allowed_algs = self._get_verification_key_and_algorithms(unverified_header)

        if not key:
            if is_production:
                logger.error("Supabase JWT secret or public key is not configured in production.")
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Authentication configuration missing.",
                )
            return None

        token_alg = unverified_header.get("alg")
        if token_alg not in allowed_algs:
            if is_production:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail=f"Unsupported token algorithm '{token_alg}'.",
                )
            return None

        decode_kwargs = {
            "algorithms": allowed_algs,
        }
        if settings.supabase_jwt_audience:
            decode_kwargs["audience"] = settings.supabase_jwt_audience
        else:
            decode_kwargs["options"] = {"verify_aud": False}

        expected_issuer = settings.supabase_jwt_issuer
        if not expected_issuer and settings.supabase_url:
            expected_issuer = f"{settings.supabase_url.rstrip('/')}/auth/v1"
        if expected_issuer:
            decode_kwargs["issuer"] = expected_issuer

        try:
            payload = jwt.decode(
                clean_token,
                key,
                **decode_kwargs,
            )
        except ExpiredSignatureError:
            if is_production:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Authentication token has expired.",
                )
            return None
        except InvalidIssuerError:
            if is_production:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid token issuer.",
                )
            return None
        except InvalidSignatureError:
            if is_production:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid token signature.",
                )
            return None
        except DecodeError as e:
            if is_production:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail=f"Malformed authentication token: {e}",
                )
            return None
        except InvalidTokenError as e:
            if is_production:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail=f"Invalid authentication token: {e}",
                )
            return None

        user_id = payload.get("sub")
        if not user_id:
            if is_production:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Token missing subject identifier.",
                )
            return None

        if is_production:
            try:
                import uuid
                uuid.UUID(str(user_id))
            except (ValueError, TypeError, AttributeError):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Token subject identifier must be a valid UUID in production.",
                )

        email = payload.get("email")
        if not email and isinstance(payload.get("user_metadata"), dict):
            email = payload["user_metadata"].get("email")

        active_tier = SubscriptionTier.FREE
        try:
            from backend.app.api.webhooks import webhook_state
            active_tier = webhook_state.get_user_tier(str(user_id))
        except Exception:
            active_tier = SubscriptionTier.FREE

        return AuthenticatedUser(
            user_id=str(user_id),
            email=email or f"{user_id}@coinscan.app",
            tier=active_tier,
            is_authenticated=True,
            auth_method="jwt",
        )


jwt_verifier = JwtAuthVerifier()
