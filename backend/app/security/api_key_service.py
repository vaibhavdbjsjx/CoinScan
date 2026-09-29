"""
Developer API Key Management Service.

Supports separate monetization for B2B / developer API access:
1. Cryptographically secure key generation (e.g. coinscan_live_abc123...)
2. Only SHA-256 hash is persisted.
3. Raw key is exposed only ONCE at generation time.
4. Key lifecycle: creation, validation, usage tracking, revocation, and rotation.
"""

import hmac
import hashlib
import secrets
import time
from typing import Dict, Optional
from pydantic import BaseModel, Field
from fastapi import HTTPException, status

from backend.app.security.rate_limit import SubscriptionTier


class ApiKeyRecord(BaseModel):
    key_id: str
    user_id: str
    name: str
    key_prefix: str
    key_hash: str
    tier: SubscriptionTier = SubscriptionTier.PRO
    monthly_limit: int = 5000
    is_active: bool = True
    created_at: float = Field(default_factory=time.time)
    last_used_at: Optional[float] = None


class ApiKeyCreationResult(BaseModel):
    key_id: str
    name: str
    raw_api_key: str  # Shown only once to the developer
    key_prefix: str
    tier: SubscriptionTier
    monthly_limit: int


class ApiKeyService:
    """In-memory & DB-ready Developer API Key Manager."""

    PREFIX_LIVE = "coinscan_live_"
    PREFIX_TEST = "coinscan_test_"

    def __init__(self):
        # key_hash -> ApiKeyRecord
        self._keys_by_hash: Dict[str, ApiKeyRecord] = {}
        # key_id -> ApiKeyRecord
        self._keys_by_id: Dict[str, ApiKeyRecord] = {}

    @staticmethod
    def _hash_key(raw_key: str) -> str:
        """Calculates SHA-256 hash of the API key."""
        return hashlib.sha256(raw_key.encode("utf-8")).hexdigest()

    def generate_key(
        self,
        user_id: str,
        name: str = "Default API Key",
        tier: SubscriptionTier = SubscriptionTier.PRO,
        is_test: bool = False,
        monthly_limit: int = 5000,
    ) -> ApiKeyCreationResult:
        """Generates a new secure API key for developer access."""
        prefix = self.PREFIX_TEST if is_test else self.PREFIX_LIVE
        random_suffix = secrets.token_urlsafe(32)
        raw_key = f"{prefix}{random_suffix}"
        key_hash = self._hash_key(raw_key)

        key_id = f"key_{secrets.token_hex(8)}"
        visible_prefix = raw_key[:18]  # e.g. "coinscan_live_abc"

        record = ApiKeyRecord(
            key_id=key_id,
            user_id=user_id,
            name=name,
            key_prefix=visible_prefix,
            key_hash=key_hash,
            tier=tier,
            monthly_limit=monthly_limit,
            is_active=True,
        )

        self._keys_by_hash[key_hash] = record
        self._keys_by_id[key_id] = record

        return ApiKeyCreationResult(
            key_id=key_id,
            name=name,
            raw_api_key=raw_key,
            key_prefix=visible_prefix,
            tier=tier,
            monthly_limit=monthly_limit,
        )

    def validate_key(self, raw_key: str) -> ApiKeyRecord:
        """Validates a raw API key from request headers."""
        if not raw_key:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing API Key.",
            )

        key_hash = self._hash_key(raw_key)
        record = self._keys_by_hash.get(key_hash)

        if not record or not record.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid, revoked, or inactive API key.",
            )

        # Update last used timestamp
        record.last_used_at = time.time()
        return record

    def revoke_key(self, key_id: str, user_id: str) -> bool:
        """Revokes an active API key."""
        record = self._keys_by_id.get(key_id)
        if not record or record.user_id != user_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="API key not found.",
            )

        record.is_active = False
        return True


api_key_service = ApiKeyService()
