"""
Server-authoritative JWT authentication and user context resolution.

Verifies Supabase access tokens passed via Authorization: Bearer <token> and
derives the user's identity from the verified token only (never from request
bodies or query parameters). Rejects spoofed client-claimed tiers or tampering.

Accepted signing methods:
  - Supabase JWT signing keys (ES256/RS256): public keys fetched from the
    project's JWKS endpoint and cached. Recommended for production.
  - SUPABASE_JWT_PUBLIC_KEY: one static PEM public key.
  - SUPABASE_JWT_SECRET: the legacy shared HS256 secret, for projects (or
    tokens) still on the legacy key.

In staging and production every failure is a 401. Development bearer
shortcuts exist only when APP_ENV is development or test.
"""

import asyncio
import logging
import time
import uuid
from typing import Dict, Optional, Tuple

import httpx
import jwt
from jwt.exceptions import (
    ExpiredSignatureError,
    InvalidIssuerError,
    InvalidSignatureError,
    InvalidTokenError,
)
from pydantic import BaseModel
from fastapi import HTTPException, status

from backend.app.config import settings
from backend.app.security.rate_limit import SubscriptionTier

logger = logging.getLogger("coinscan.auth.jwt")

ASYMMETRIC_ALGORITHMS = {"RS256", "RS384", "RS512", "PS256", "PS384", "PS512", "ES256", "ES384", "ES512", "EdDSA"}
HMAC_ALGORITHMS = {"HS256", "HS384", "HS512"}


class AuthenticatedUser(BaseModel):
    user_id: str
    email: Optional[str] = None
    tier: SubscriptionTier = SubscriptionTier.FREE
    is_authenticated: bool = True
    auth_method: str = "jwt"  # "jwt", "api_key", "anonymous"


class SupabaseSigningKeys:
    """Public signing keys of the Supabase project (JWKS), cached in memory.

    Fetched asynchronously, so no blocking network call happens while a token
    is verified: at startup, when the cache is older than
    SUPABASE_JWKS_CACHE_SECONDS, and when a token names an unknown key id.
    Fetches are spaced at least `min_refresh_interval` seconds apart, so
    tokens with made-up key ids cannot trigger a request storm. Only
    asymmetric public keys are accepted from the endpoint.
    """

    def __init__(self, min_refresh_interval: float = 30.0):
        self.min_refresh_interval = min_refresh_interval
        self.transport: Optional[httpx.AsyncBaseTransport] = None  # tests only
        self._keys: Dict[str, jwt.PyJWK] = {}
        self._fetched_at: float = 0.0
        self._last_attempt: Optional[float] = None
        self._lock: Optional[asyncio.Lock] = None

    @property
    def url(self) -> Optional[str]:
        return settings.resolved_jwks_url

    @property
    def has_keys(self) -> bool:
        return bool(self._keys)

    def get(self, kid: Optional[str]) -> Optional[jwt.PyJWK]:
        return self._keys.get(kid) if kid else None

    def is_stale(self) -> bool:
        return time.monotonic() - self._fetched_at > settings.supabase_jwks_cache_seconds

    def _recently_attempted(self) -> bool:
        return (
            self._last_attempt is not None
            and time.monotonic() - self._last_attempt < self.min_refresh_interval
        )

    async def refresh(self) -> bool:
        """Fetches the key set. Returns whether usable keys are cached afterwards."""
        url = self.url
        if not url or self._recently_attempted():
            return self.has_keys
        if self._lock is None:
            self._lock = asyncio.Lock()
        async with self._lock:
            if self._recently_attempted():
                return self.has_keys
            self._last_attempt = time.monotonic()
            try:
                async with httpx.AsyncClient(timeout=5.0, transport=self.transport) as client:
                    resp = await client.get(url)
                resp.raise_for_status()
                keys = self._parse(resp.json())
            except Exception as exc:
                logger.warning(f"Could not refresh Supabase signing keys: {type(exc).__name__}")
                return self.has_keys
            self._keys = keys
            self._fetched_at = time.monotonic()
            logger.info(f"Loaded {len(keys)} Supabase signing key(s).")
            return self.has_keys

    async def ensure_for_token(self, token: str) -> None:
        """Makes sure the key named by an asymmetric token is cached (if it exists)."""
        if not self.url:
            return
        try:
            header = jwt.get_unverified_header(token)
        except Exception:
            return
        if header.get("alg") not in ASYMMETRIC_ALGORITHMS:
            return
        kid = header.get("kid")
        if kid and (kid not in self._keys or self.is_stale()):
            await self.refresh()

    @staticmethod
    def _parse(document) -> Dict[str, jwt.PyJWK]:
        keys: Dict[str, jwt.PyJWK] = {}
        for jwk in (document or {}).get("keys", []):
            if not isinstance(jwk, dict):
                continue
            kid, alg, kty = jwk.get("kid"), jwk.get("alg"), jwk.get("kty")
            if not kid or kty not in ("EC", "RSA", "OKP"):
                continue  # never trust a symmetric ("oct") key published at a URL
            if alg and alg not in ASYMMETRIC_ALGORITHMS:
                continue
            try:
                keys[kid] = jwt.PyJWK(jwk)
            except Exception:
                continue
        return keys

    def reset_for_test(self) -> None:
        self._keys = {}
        self._fetched_at = 0.0
        self._last_attempt = None
        self._lock = None  # created again inside the next event loop
        self.transport = None


signing_keys = SupabaseSigningKeys()


class JwtAuthVerifier:
    """Verifies JWT bearer tokens and resolves user identity."""

    def __init__(self):
        # Development/test-only token registry (unit tests and local work)
        self._dev_users: dict[str, AuthenticatedUser] = {}

    def register_dev_user(self, token: str, user: AuthenticatedUser):
        """Registers a development token. Honoured only when APP_ENV is development or test."""
        self._dev_users[token] = user

    def _resolve_key(self, header: dict) -> Tuple[Optional[object], Optional[str]]:
        """Returns (verification key, error message)."""
        alg = header.get("alg")
        configured_alg = settings.supabase_jwt_algorithm
        if configured_alg and alg != configured_alg:
            return None, f"Unsupported token algorithm '{alg}'."

        if alg in ASYMMETRIC_ALGORITHMS:
            jwk = signing_keys.get(header.get("kid"))
            if jwk is not None:
                if jwk.algorithm_name != alg:
                    return None, "Token algorithm does not match its signing key."
                return jwk.key, None
            static_pem = settings.supabase_jwt_public_key
            if not static_pem and settings.supabase_jwt_secret and settings.supabase_jwt_secret.strip().startswith("-----BEGIN"):
                static_pem = settings.supabase_jwt_secret
            if static_pem:
                return static_pem, None
            if signing_keys.url:
                return None, "Unknown token signing key."
            return None, "Authentication configuration missing."

        if alg in HMAC_ALGORITHMS:
            secret = settings.supabase_jwt_secret
            if secret and not secret.strip().startswith("-----BEGIN"):
                return secret, None
            if settings.supabase_jwt_public_key or signing_keys.url:
                return None, f"Unsupported token algorithm '{alg}'."
            return None, "Authentication configuration missing."

        # Includes "none": unsigned tokens are never accepted.
        return None, f"Unsupported token algorithm '{alg}'."

    def verify_token(self, token: Optional[str]) -> Optional[AuthenticatedUser]:
        """Verifies a bearer token and returns the user it identifies.

        Staging and production: strict signature, expiry, audience, issuer and
        subject checks; any failure raises 401 and no development shortcut exists.
        Development and test: additionally accepts registered dev tokens and the
        usr_/dev_/jwt_token_ prefixes; an invalid token yields None (guest).
        """
        if not token:
            return None

        clean_token = token.strip()
        if clean_token.lower().startswith("bearer "):
            clean_token = clean_token[7:].strip()
        if not clean_token:
            return None

        strict = settings.is_hardened

        def reject(detail: str) -> None:
            if strict:
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=detail)
            return None

        # DEVELOPMENT/TEST-ONLY SHORTCUTS, decided by APP_ENV alone.
        if settings.dev_features_enabled:
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

        try:
            header = jwt.get_unverified_header(clean_token)
        except Exception:
            return reject("Malformed authentication token.")

        key, problem = self._resolve_key(header)
        if key is None:
            if strict and problem == "Authentication configuration missing.":
                logger.error("No Supabase token verification key is configured.")
            return reject(problem or "Invalid authentication token.")

        audience = settings.supabase_jwt_audience or ("authenticated" if strict else None)
        issuer = settings.resolved_jwt_issuer
        decode_kwargs = {"algorithms": [header.get("alg")], "options": {"require": ["exp"]}}
        if audience:
            decode_kwargs["audience"] = audience
        else:
            decode_kwargs["options"]["verify_aud"] = False
        if issuer:
            decode_kwargs["issuer"] = issuer

        try:
            payload = jwt.decode(clean_token, key, **decode_kwargs)
        except ExpiredSignatureError:
            return reject("Authentication token has expired.")
        except InvalidIssuerError:
            return reject("Invalid token issuer.")
        except InvalidSignatureError:
            return reject("Invalid token signature.")
        except InvalidTokenError:
            return reject("Invalid authentication token.")
        except Exception:
            return reject("Invalid authentication token.")

        role = payload.get("role")
        if role is not None and role != "authenticated":
            return reject("Token is not a signed-in user session.")
        if payload.get("is_anonymous") is True:
            return reject("Anonymous sessions are not accepted.")

        user_id = payload.get("sub")
        if not user_id:
            return reject("Token missing subject identifier.")

        if strict:
            try:
                uuid.UUID(str(user_id))
            except (ValueError, TypeError, AttributeError):
                return reject("Token subject identifier must be a valid UUID in production.")

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
