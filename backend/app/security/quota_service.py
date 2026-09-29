"""
Server-authoritative scan quota and concurrency control engine.

Key guarantees:
1. Tied to server-verified user_id or API key (never client-side assertions or device IDs).
2. Atomic check-and-increment to prevent race condition attacks where multiple
   simultaneous requests attempt to bypass daily scan limits.
3. Two-phase quota safety: Quota is validated before processing, but only deducted
   when the scan completes successfully. Server errors do not consume user quota.
4. Strict UTC midnight date boundaries.
5. Tier-based quotas:
   - Free / Limited: 3 scans / day
   - Plus: 30 scans / day
   - Pro: 100 scans / day (Fair-use high cap)
"""

import asyncio
from datetime import datetime, timezone, date
import logging
from typing import Dict, Tuple, Optional, Any
from fastapi import HTTPException, status

from backend.app.config import settings
from backend.app.security.rate_limit import SubscriptionTier
from backend.app.db.session import is_db_configured, get_session_factory
from backend.app.db.models import User, ScanUsage
from sqlalchemy import select, delete

logger = logging.getLogger("coinscan.quota")


class QuotaEngine:
    """Thread-safe, atomic scan quota manager.

    In production: Backed by PostgreSQL / Supabase table `scan_usage`.
    In development: Uses in-memory synchronization locks when DATABASE_URL is not configured.
    """

    TIER_DAILY_LIMITS: Dict[SubscriptionTier, int] = {
        SubscriptionTier.ANONYMOUS: 3,
        SubscriptionTier.FREE: 3,
        SubscriptionTier.PLUS: 30,
        SubscriptionTier.PRO: 100,  # Fair-use ceiling
        SubscriptionTier.ENTERPRISE: 10000,
    }

    def __init__(self):
        # Key: (user_id, YYYY-MM-DD) -> int (scan_count)
        self._daily_usage: Dict[Tuple[str, str], int] = {}
        # Key: (user_id, YYYY-MM-DD) -> int (in_flight_count)
        self._in_flight: Dict[Tuple[str, str], int] = {}
        # Mutex lock to protect concurrent check-and-increments
        self._lock = asyncio.Lock()

    def _check_persistence_mode(self):
        """Fails closed in production if database persistence is not configured."""
        if settings.app_env == "production" and not is_db_configured():
            logger.critical("Persistence failure: DATABASE_URL is not configured in production.")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database persistence unconfigured in production.",
            )

    @staticmethod
    def _current_utc_date_str() -> str:
        """Returns the current UTC date string formatted as YYYY-MM-DD."""
        return datetime.now(timezone.utc).strftime("%Y-%m-%d")

    async def check_quota_available(
        self,
        identifier: str,
        tier: SubscriptionTier = SubscriptionTier.FREE,
    ):
        """Validates that the user has remaining scan quota for today without consuming it.

        Raises:
            HTTPException 429 if the daily scan quota has been exhausted.
        """
        self._check_persistence_mode()
        date_str = self._current_utc_date_str()
        limit = self.TIER_DAILY_LIMITS.get(tier, 3)

        if is_db_configured():
            factory = get_session_factory()
            if factory:
                c_date = date.fromisoformat(date_str)
                async with factory() as session:
                    stmt = select(ScanUsage).where(
                        ScanUsage.user_id == identifier,
                        ScanUsage.scan_date == c_date,
                    )
                    res = await session.execute(stmt)
                    usage = res.scalar_one_or_none()
                    current_used = usage.scan_count if usage else 0
                    if current_used >= limit:
                        logger.warning(
                            f"DB Quota check blocked: user={identifier} tier={tier.value} "
                            f"used={current_used}/{limit} date={date_str}"
                        )
                        raise HTTPException(
                            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                            detail={
                                "error": "daily_quota_exceeded",
                                "message": f"You have reached your daily limit of {limit} scans for the {tier.value} tier. Quotas reset at 00:00 UTC.",
                                "tier": tier.value,
                                "limit": limit,
                                "used": current_used,
                                "resets_at_utc": f"{date_str}T23:59:59Z",
                            },
                        )
                    return

        async with self._lock:
            key = (identifier, date_str)
            current_used = self._daily_usage.get(key, 0)

            if current_used >= limit:
                logger.warning(
                    f"Quota check blocked: user={identifier} tier={tier.value} "
                    f"used={current_used}/{limit} date={date_str}"
                )
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail={
                        "error": "daily_quota_exceeded",
                        "message": f"You have reached your daily limit of {limit} scans for the {tier.value} tier. Quotas reset at 00:00 UTC.",
                        "tier": tier.value,
                        "limit": limit,
                        "used": current_used,
                        "resets_at_utc": f"{date_str}T23:59:59Z",
                    },
                )

    async def check_and_consume_quota(
        self,
        identifier: str,
        tier: SubscriptionTier = SubscriptionTier.FREE,
    ) -> int:
        """Atomically checks and consumes 1 scan from the user's daily quota.

        Args:
            identifier: Unique user_id or API key hash
            tier: Server-verified subscription tier

        Returns:
            The remaining scans for today (-1 if unlimited/enterprise, or integer >= 0)

        Raises:
            HTTPException 429 if the daily scan quota has been exhausted.
        """
        self._check_persistence_mode()
        date_str = self._current_utc_date_str()
        limit = self.TIER_DAILY_LIMITS.get(tier, 3)

        if is_db_configured():
            factory = get_session_factory()
            if factory:
                c_date = date.fromisoformat(date_str)
                async with factory() as session:
                    user = await session.get(User, identifier)
                    if not user:
                        user = User(id=identifier, email=f"{identifier}@coinscan.app")
                        session.add(user)
                        await session.flush()

                    stmt = select(ScanUsage).where(
                        ScanUsage.user_id == identifier,
                        ScanUsage.scan_date == c_date,
                    ).with_for_update()
                    res = await session.execute(stmt)
                    usage = res.scalar_one_or_none()
                    if usage is None:
                        usage = ScanUsage(user_id=identifier, scan_date=c_date, scan_count=1)
                        session.add(usage)
                        await session.commit()
                        remaining = limit - 1
                        return remaining
                    else:
                        if usage.scan_count >= limit:
                            raise HTTPException(
                                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                                detail={
                                    "error": "daily_quota_exceeded",
                                    "message": f"You have reached your daily limit of {limit} scans for the {tier.value} tier. Quotas reset at 00:00 UTC.",
                                    "tier": tier.value,
                                    "limit": limit,
                                    "used": usage.scan_count,
                                    "resets_at_utc": f"{date_str}T23:59:59Z",
                                },
                            )
                        usage.scan_count += 1
                        await session.commit()
                        remaining = limit - usage.scan_count
                        return remaining

        async with self._lock:
            key = (identifier, date_str)
            current_used = self._daily_usage.get(key, 0)

            if current_used >= limit:
                logger.warning(
                    f"Quota exhausted for user={identifier} tier={tier.value} "
                    f"used={current_used}/{limit} date={date_str}"
                )
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail={
                        "error": "daily_quota_exceeded",
                        "message": f"You have reached your daily limit of {limit} scans for the {tier.value} tier. Quotas reset at 00:00 UTC.",
                        "tier": tier.value,
                        "limit": limit,
                        "used": current_used,
                        "resets_at_utc": f"{date_str}T23:59:59Z",
                    },
                )

            # Atomically increment usage
            new_count = current_used + 1
            self._daily_usage[key] = new_count
            remaining = limit - new_count
            logger.info(
                f"Scan quota consumed: user={identifier} tier={tier.value} "
                f"used={new_count}/{limit} remaining={remaining}"
            )
            return remaining

    async def rollback_quota(self, identifier: str):
        """Rolls back 1 scan in the event of an unhandled downstream server/provider failure."""
        date_str = self._current_utc_date_str()
        async with self._lock:
            key = (identifier, date_str)
            current_used = self._daily_usage.get(key, 0)
            if current_used > 0:
                self._daily_usage[key] = current_used - 1
                logger.info(f"Quota rolled back for user={identifier} on error: used={current_used - 1}")

    def get_current_usage(self, identifier: str) -> int:
        """Inspects current usage for today without consuming quota."""
        date_str = self._current_utc_date_str()
        return self._daily_usage.get((identifier, date_str), 0)

    async def get_quota_status_async(
        self,
        identifier: str,
        tier: SubscriptionTier = SubscriptionTier.FREE,
    ) -> Dict[str, Any]:
        """Returns structured quota metrics for today."""
        self._check_persistence_mode()
        date_str = self._current_utc_date_str()
        limit = self.TIER_DAILY_LIMITS.get(tier, 3)
        current_used = 0

        if is_db_configured():
            factory = get_session_factory()
            if factory:
                c_date = date.fromisoformat(date_str)
                async with factory() as session:
                    stmt = select(ScanUsage).where(
                        ScanUsage.user_id == identifier,
                        ScanUsage.scan_date == c_date,
                    )
                    res = await session.execute(stmt)
                    usage = res.scalar_one_or_none()
                    current_used = usage.scan_count if usage else 0
        else:
            current_used = self._daily_usage.get((identifier, date_str), 0)

        remaining = max(0, limit - current_used)
        return {
            "user_id": identifier,
            "tier": tier.value,
            "daily_limit": limit,
            "scans_used_today": current_used,
            "scans_remaining_today": remaining,
            "resets_at_utc": f"{date_str}T23:59:59Z",
        }

    async def reserve_slot(
        self,
        identifier: str,
        tier: SubscriptionTier = SubscriptionTier.FREE,
    ) -> "QuotaReservation":
        """Atomically validates quota and reserves an in-flight processing slot.
        
        Guarantees that 10 simultaneous requests with 1 scan remaining will result in
        exactly 1 reservation granted and 9 immediate 429 rejections at the front door.
        """
        self._check_persistence_mode()
        date_str = self._current_utc_date_str()
        limit = self.TIER_DAILY_LIMITS.get(tier, 3)

        db_used = 0
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                c_date = date.fromisoformat(date_str)
                async with factory() as session:
                    stmt = select(ScanUsage).where(
                        ScanUsage.user_id == identifier,
                        ScanUsage.scan_date == c_date,
                    )
                    res = await session.execute(stmt)
                    usage = res.scalar_one_or_none()
                    if usage:
                        db_used = usage.scan_count

        async with self._lock:
            key = (identifier, date_str)
            current_used = max(self._daily_usage.get(key, 0), db_used)
            self._daily_usage[key] = current_used
            current_in_flight = self._in_flight.get(key, 0)

            if current_used + current_in_flight >= limit:
                logger.warning(
                    f"Quota reservation blocked: user={identifier} tier={tier.value} "
                    f"used={current_used} in_flight={current_in_flight} limit={limit} date={date_str}"
                )
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail={
                        "error": "daily_quota_exceeded",
                        "message": f"You have reached your daily limit of {limit} scans for the {tier.value} tier. Quotas reset at 00:00 UTC.",
                        "tier": tier.value,
                        "limit": limit,
                        "used": current_used,
                        "resets_at_utc": f"{date_str}T23:59:59Z",
                    },
                )
            self._in_flight[key] = current_in_flight + 1

        return QuotaReservation(self, identifier, date_str, tier, limit)

    def purge_user(self, identifier: str):
        """Purges all usage and reservation records for a deleted user account."""
        self._check_persistence_mode()
        for key in list(self._daily_usage.keys()):
            if key[0] == identifier:
                self._daily_usage.pop(key, None)
        for key in list(self._in_flight.keys()):
            if key[0] == identifier:
                self._in_flight.pop(key, None)

    async def purge_user_async(self, identifier: str):
        self._check_persistence_mode()
        self.purge_user(identifier)
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    stmt = delete(ScanUsage).where(ScanUsage.user_id == identifier)
                    await session.execute(stmt)
                    await session.commit()

    def reset_usage_for_test(self, identifier: Optional[str] = None):
        """Helper for test suites to reset usage tracking."""
        if identifier:
            date_str = self._current_utc_date_str()
            self._daily_usage.pop((identifier, date_str), None)
            self._in_flight.pop((identifier, date_str), None)
        else:
            self._daily_usage.clear()
            self._in_flight.clear()


class QuotaReservation:
    """Two-phase in-flight reservation token for scan quotas.
    
    Protects against concurrency race conditions where simultaneous requests
    attempt to exhaust or exceed quota slots before completion.
    """
    def __init__(self, engine: QuotaEngine, identifier: str, date_str: str, tier: SubscriptionTier, limit: int):
        self.engine = engine
        self.identifier = identifier
        self.date_str = date_str
        self.tier = tier
        self.limit = limit
        self.committed = False
        self.released = False

    async def commit(self) -> int:
        """Atomically transitions this reservation from in-flight to consumed quota."""
        if self.committed or self.released:
            return 0

        db_scan_count = 0
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                c_date = date.fromisoformat(self.date_str)
                async with factory() as session:
                    user = await session.get(User, self.identifier)
                    if not user:
                        user = User(id=self.identifier, email=f"{self.identifier}@coinscan.app")
                        session.add(user)
                        await session.flush()
                    stmt = select(ScanUsage).where(
                        ScanUsage.user_id == self.identifier,
                        ScanUsage.scan_date == c_date,
                    ).with_for_update()
                    res = await session.execute(stmt)
                    usage = res.scalar_one_or_none()
                    if usage is None:
                        usage = ScanUsage(user_id=self.identifier, scan_date=c_date, scan_count=1)
                        session.add(usage)
                        db_scan_count = 1
                    else:
                        usage.scan_count += 1
                        db_scan_count = usage.scan_count
                    await session.commit()

        async with self.engine._lock:
            key = (self.identifier, self.date_str)
            current_in_flight = self.engine._in_flight.get(key, 0)
            if current_in_flight > 0:
                self.engine._in_flight[key] = current_in_flight - 1
            new_used = max(self.engine._daily_usage.get(key, 0) + 1, db_scan_count)
            self.engine._daily_usage[key] = new_used
            self.committed = True
            remaining = max(0, self.limit - new_used)
            logger.info(
                f"Scan quota committed: user={self.identifier} tier={self.tier.value} "
                f"used={new_used}/{self.limit} remaining={remaining}"
            )
            return remaining

    async def release(self):
        """Rolls back the in-flight reservation on error, timeout, or cancellation."""
        if self.committed or self.released:
            return
        async with self.engine._lock:
            key = (self.identifier, self.date_str)
            current_in_flight = self.engine._in_flight.get(key, 0)
            if current_in_flight > 0:
                self.engine._in_flight[key] = current_in_flight - 1
            self.released = True
            logger.info(f"Quota reservation released on failure/abort for user={self.identifier}")

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if not self.committed:
            await self.release()


quota_engine = QuotaEngine()
