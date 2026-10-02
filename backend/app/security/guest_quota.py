"""
Daily scan allowance for signed-out (guest) callers.

Guests stay unauthenticated. They never get a users row, a scan_usage row, scan
history or any UUID identity. Their usage is counted in the guest_scan_usage table
under keyed hashes (HMAC-SHA256 with GUEST_QUOTA_HMAC_SECRET), so neither the
client address nor the app install ID is stored.

Keys per request:
  - install: the app's random install ID header, when it is a valid UUID. This is
    only a rate-limit hint, never an identity: it grants nothing beyond its own
    daily allowance (GUEST_DAILY_SCAN_LIMIT).
  - network: the client address resolved through the trusted-proxy setting. With
    an install ID it is a per-network ceiling (GUEST_NETWORK_DAILY_SCAN_LIMIT);
    without one it carries the guest allowance itself.

A slot is reserved before any paid provider call with a conditional upsert, which
PostgreSQL applies atomically per row, so concurrent requests on any number of
instances cannot exceed the limit. A failed scan releases the slot again.
"""

import asyncio
import hashlib
import hmac
import logging
import secrets
import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Dict, List, Optional, Tuple

from fastapi import HTTPException, Request, status
from sqlalchemy import func, update, select, delete
from sqlalchemy.dialects import postgresql, sqlite
from sqlalchemy.exc import SQLAlchemyError

from backend.app.config import settings
from backend.app.db.models import GuestScanUsage
from backend.app.db.session import get_session_factory, is_db_configured
from backend.app.security.client_ip import get_client_ip, network_bucket

logger = logging.getLogger("coinscan.guest")

INSTALL_ID_HEADER = "X-CoinScan-Install-ID"
KEEP_DAYS = 2

# Used only when running locally without GUEST_QUOTA_HMAC_SECRET.
_LOCAL_ONLY_KEY = secrets.token_bytes(32)


@dataclass(frozen=True)
class AllowanceKey:
    kind: str
    digest: str
    daily_limit: int


def _today() -> date:
    return datetime.now(timezone.utc).date()


def _signing_key() -> bytes:
    if settings.guest_quota_hmac_secret:
        return settings.guest_quota_hmac_secret.encode("utf-8")
    if settings.dev_features_enabled:
        return _LOCAL_ONLY_KEY
    logger.error("GUEST_QUOTA_HMAC_SECRET is missing; guest scanning is disabled.")
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "error": "guest_scanning_unavailable",
            "message": "Scanning without an account is not available right now. Please sign in.",
        },
    )


def _digest(kind: str, value: str) -> str:
    return hmac.new(_signing_key(), f"{kind}|{value}".encode("utf-8"), hashlib.sha256).hexdigest()


def _install_id(request: Request) -> Optional[str]:
    raw = request.headers.get(INSTALL_ID_HEADER)
    if not raw:
        return None
    try:
        return str(uuid.UUID(raw.strip()))
    except ValueError:
        return None


def allowance_keys(request: Request) -> List[AllowanceKey]:
    network_id = network_bucket(get_client_ip(request))
    network = AllowanceKey("network", _digest("network", network_id), settings.guest_daily_scan_limit)
    install = _install_id(request)
    if install is None:
        return [network]
    return [
        AllowanceKey("install", _digest("install", install), settings.guest_daily_scan_limit),
        AllowanceKey("network", network.digest, settings.guest_network_daily_scan_limit),
    ]


def _limit_reached(limit: int, day: date) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail={
            "error": "guest_daily_limit_reached",
            "message": (
                f"You've used today's {limit} free guest scan{'s' if limit != 1 else ''}. "
                "Create a free account to keep scanning."
            ),
            "limit": limit,
            "resets_at_utc": f"{day.isoformat()}T23:59:59Z",
        },
    )


def _unavailable() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "error": "guest_scanning_unavailable",
            "message": "Scanning without an account is not available right now. Please try again shortly.",
        },
    )


class GuestAllowanceStore:
    """PostgreSQL-backed counters; an in-process dict only when no database is configured."""

    def __init__(self):
        self._local: Dict[Tuple[str, date], int] = {}
        self._lock = asyncio.Lock()
        self._pruned_on: Optional[date] = None

    @staticmethod
    def _factory():
        if settings.app_env == "production" and not is_db_configured():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database persistence unconfigured in production.",
            )
        return get_session_factory() if is_db_configured() else None

    async def take(self, key: AllowanceKey, day: date) -> Optional[int]:
        """Adds one use if the key is under its limit. Returns the new count, or None."""
        if key.daily_limit <= 0:
            return None
        factory = self._factory()
        if factory is None:
            async with self._lock:
                used = self._local.get((key.digest, day), 0)
                if used >= key.daily_limit:
                    return None
                self._local[(key.digest, day)] = used + 1
                return used + 1

        async with factory() as session:
            dialect = session.bind.dialect.name
            insert = postgresql.insert if dialect == "postgresql" else sqlite.insert
            stmt = insert(GuestScanUsage).values(
                key_hash=key.digest,
                key_kind=key.kind,
                scan_date=day,
                scan_count=1,
            )
            stmt = stmt.on_conflict_do_update(
                index_elements=[GuestScanUsage.key_hash, GuestScanUsage.scan_date],
                set_={
                    "scan_count": GuestScanUsage.scan_count + 1,
                    "updated_at": func.current_timestamp(),
                },
                where=GuestScanUsage.scan_count < key.daily_limit,
            ).returning(GuestScanUsage.scan_count)
            row = (await session.execute(stmt)).first()
            await session.commit()
            return int(row[0]) if row is not None else None

    async def give_back(self, digest: str, day: date) -> None:
        factory = self._factory()
        if factory is None:
            async with self._lock:
                used = self._local.get((digest, day), 0)
                if used > 0:
                    self._local[(digest, day)] = used - 1
            return
        async with factory() as session:
            await session.execute(
                update(GuestScanUsage)
                .where(
                    GuestScanUsage.key_hash == digest,
                    GuestScanUsage.scan_date == day,
                    GuestScanUsage.scan_count > 0,
                )
                .values(scan_count=GuestScanUsage.scan_count - 1, updated_at=func.current_timestamp())
            )
            await session.commit()

    async def used(self, digest: str, day: date) -> int:
        factory = self._factory()
        if factory is None:
            return self._local.get((digest, day), 0)
        async with factory() as session:
            value = (
                await session.execute(
                    select(GuestScanUsage.scan_count).where(
                        GuestScanUsage.key_hash == digest,
                        GuestScanUsage.scan_date == day,
                    )
                )
            ).scalar_one_or_none()
            return int(value or 0)

    async def prune(self, today: date) -> None:
        """Removes rows past the retention window, at most once a day per process."""
        if self._pruned_on == today:
            return
        self._pruned_on = today
        cutoff = today - timedelta(days=KEEP_DAYS)
        factory = self._factory()
        if factory is None:
            async with self._lock:
                for k in [k for k in self._local if k[1] < cutoff]:
                    del self._local[k]
            return
        try:
            async with factory() as session:
                await session.execute(delete(GuestScanUsage).where(GuestScanUsage.scan_date < cutoff))
                await session.commit()
        except SQLAlchemyError as e:
            logger.warning(f"Guest usage pruning skipped: {type(e).__name__}")

    def reset_for_test(self) -> None:
        self._local.clear()
        self._pruned_on = None


@dataclass
class GuestSlot:
    """One reserved guest scan. commit() keeps it; release() returns it."""

    store: GuestAllowanceStore
    day: date
    taken: List[Tuple[AllowanceKey, int]] = field(default_factory=list)
    committed: bool = False
    released: bool = False

    @property
    def remaining(self) -> int:
        return max(0, min(k.daily_limit - used for k, used in self.taken)) if self.taken else 0

    async def commit(self) -> int:
        self.committed = True
        return self.remaining

    async def release(self) -> None:
        if self.committed or self.released:
            return
        self.released = True
        for key, _ in self.taken:
            try:
                await self.store.give_back(key.digest, self.day)
            except SQLAlchemyError as e:
                logger.error(f"Could not release a guest scan slot: {type(e).__name__}")


class GuestAllowance:
    def __init__(self, store: Optional[GuestAllowanceStore] = None):
        self.store = store or GuestAllowanceStore()

    async def reserve(self, request: Request) -> GuestSlot:
        keys = allowance_keys(request)
        day = _today()
        slot = GuestSlot(store=self.store, day=day)
        try:
            await self.store.prune(day)
            for key in keys:
                used = await self.store.take(key, day)
                if used is None:
                    await slot.release()
                    raise _limit_reached(keys[0].daily_limit, day)
                slot.taken.append((key, used))
        except SQLAlchemyError as e:
            logger.error(f"Guest allowance unavailable: {type(e).__name__}")
            await slot.release()
            raise _unavailable()
        return slot

    async def status(self, request: Request) -> dict:
        keys = allowance_keys(request)
        day = _today()
        primary = keys[0]
        try:
            used = await self.store.used(primary.digest, day)
        except SQLAlchemyError:
            raise _unavailable()
        return {
            "limit": primary.daily_limit,
            "used": used,
            "remaining": max(0, primary.daily_limit - used),
            "resets_at_utc": f"{day.isoformat()}T23:59:59Z",
        }


guest_allowance = GuestAllowance()
