"""
Lightweight in-memory rate limiting and quota middleware for API protection.
Supports IP sliding-window throttling, API key authentication, and tier-based quota checks.
"""

import time
from enum import Enum
from typing import Dict, List, Optional
from collections import defaultdict
from fastapi import Request, HTTPException, status


class SubscriptionTier(str, Enum):
    ANONYMOUS = "anonymous"
    FREE = "free"
    PLUS = "plus"
    PRO = "pro"
    ENTERPRISE = "enterprise"


class InMemoryRateLimiter:
    """Sliding-window in-memory rate limiter per IP and client identifier."""

    def __init__(self, default_rpm: int = 60):
        self.default_rpm = default_rpm
        self.window = 60.0  # seconds
        self._ip_history: Dict[str, List[float]] = defaultdict(list)
        self._user_history: Dict[str, List[float]] = defaultdict(list)

    def check_rate_limit(
        self,
        client_ip: str,
        user_id: Optional[str] = None,
        tier: SubscriptionTier = SubscriptionTier.ANONYMOUS,
        api_key: Optional[str] = None,
    ):
        now = time.time()

        # 1. IP Throttling (Protection against DDoS and automated scrapers)
        ip_timestamps = self._ip_history[client_ip]
        self._ip_history[client_ip] = [t for t in ip_timestamps if now - t < self.window]

        ip_limit = self.default_rpm if tier not in (SubscriptionTier.PLUS, SubscriptionTier.PRO, SubscriptionTier.ENTERPRISE) else 120
        if len(self._ip_history[client_ip]) >= ip_limit:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many scan requests from this IP. Please wait a moment before trying again.",
            )
        self._ip_history[client_ip].append(now)

        # 2. User / API Key Rate & Quota Enforcement
        identifier = api_key or user_id
        if identifier:
            user_timestamps = self._user_history[identifier]
            self._user_history[identifier] = [t for t in user_timestamps if now - t < self.window]

            limit = 60
            if tier == SubscriptionTier.PLUS:
                limit = 90
            elif tier == SubscriptionTier.PRO:
                limit = 120
            elif tier == SubscriptionTier.ENTERPRISE:
                limit = 600

            if len(self._user_history[identifier]) >= limit:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=f"Rate limit exceeded for {tier.value} tier. Please upgrade for higher throughput.",
                )
            self._user_history[identifier].append(now)


rate_limiter = InMemoryRateLimiter(default_rpm=60)
