"""
Subscription Webhook Ingestion API.

Processes server-to-server webhook notifications from RevenueCat.
Guarantees:
1. Webhook Authorization verification (fail closed).
2. Event Idempotency (duplicate events are ignored and return HTTP 200).
3. Lifecycle state synchronization for subscriptions and entitlements, following
   RevenueCat's documented event semantics:
   - Grants (INITIAL_PURCHASE, RENEWAL, UNCANCELLATION, SUBSCRIPTION_EXTENDED,
     REFUND_REVERSED, TEMPORARY_ENTITLEMENT_GRANT) set the tier and its expiry.
   - PRODUCT_CHANGE is informational: the change takes effect via a later RENEWAL
     (App Store) / INITIAL_PURCHASE (Google Play) carrying the new product, so the
     tier is NOT changed on PRODUCT_CHANGE (acting on new_product_id immediately
     would wrongly downgrade users who keep the higher tier until renewal).
   - CANCELLATION keeps access until expiration, except refunds (cancel_reason
     CUSTOMER_SUPPORT, or an expiration time already in the past) which revoke now.
   - EXPIRATION revokes, unless it refers to an older period or a lower tier than
     the user's current entitlement (e.g. the old product after an upgrade).
   - SUBSCRIPTION_PAUSED / BILLING_ISSUE do not revoke access.
   - TRANSFER moves the entitlement between App User IDs.
4. The stored expiry is enforced whenever a tier is read, so a missed EXPIRATION
   webhook can never leave a user on a paid tier indefinitely.
5. Persistence failures return HTTP 500 and the event is NOT marked processed,
   so RevenueCat retries it.
"""

import hmac
import uuid
import logging
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List, Tuple
from fastapi import APIRouter, Header, HTTPException, status
from pydantic import BaseModel, Field

from backend.app.config import settings
from backend.app.security.rate_limit import SubscriptionTier

logger = logging.getLogger("coinscan.webhooks")
router = APIRouter(prefix="/v1/webhooks", tags=["Webhooks"])


class RevenueCatEvent(BaseModel):
    id: str = Field(..., description="Unique event identifier from RevenueCat")
    type: str = Field(..., description="INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION, etc.")
    # Absent on TRANSFER events (which use transferred_from / transferred_to).
    app_user_id: Optional[str] = None
    original_app_user_id: Optional[str] = None
    aliases: Optional[List[str]] = None
    transferred_from: Optional[List[str]] = None
    transferred_to: Optional[List[str]] = None
    product_id: Optional[str] = None
    new_product_id: Optional[str] = None
    entitlement_ids: Optional[List[str]] = None
    entitlement_id: Optional[str] = None  # deprecated single-entitlement field
    period_type: Optional[str] = None
    purchased_at_ms: Optional[int] = None
    expiration_at_ms: Optional[int] = None
    grace_period_expiration_at_ms: Optional[int] = None
    event_timestamp_ms: Optional[int] = None
    cancel_reason: Optional[str] = None
    expiration_reason: Optional[str] = None
    store: Optional[str] = None
    environment: Optional[str] = "PRODUCTION"


class RevenueCatWebhookPayload(BaseModel):
    api_version: Optional[str] = "1.0"
    event: RevenueCatEvent


class WebhookProcessingResult(BaseModel):
    status: str
    event_id: str
    action_taken: str
    user_id: str
    resolved_tier: str


class EntitlementPersistenceError(Exception):
    """The entitlement could not be written to the database; the event must be retried."""


from collections import OrderedDict
import time
from backend.app.db.session import is_db_configured, get_session_factory
from backend.app.db.models import User, Entitlement, SubscriptionEvent
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

_TIER_RANK = {
    SubscriptionTier.ANONYMOUS: 0,
    SubscriptionTier.FREE: 0,
    SubscriptionTier.PLUS: 1,
    SubscriptionTier.PRO: 2,
    SubscriptionTier.ENTERPRISE: 3,
}

# Allow for clock skew between RevenueCat timestamps and this server.
_EXPIRY_TOLERANCE_MS = 60_000


def _now_ms() -> int:
    return int(time.time() * 1000)


def _is_uuid(value: Optional[str]) -> bool:
    if not value:
        return False
    try:
        uuid.UUID(str(value))
        return True
    except (ValueError, TypeError, AttributeError):
        return False


def _csv_set(raw: Optional[str]) -> set:
    return {p.strip().lower() for p in (raw or "").split(",") if p.strip()}


def resolve_tier(entitlement_ids: Optional[List[str]], product_id: Optional[str]) -> Optional[SubscriptionTier]:
    """Maps RevenueCat entitlement IDs / product IDs to a tier by EXACT match.

    Substring matching is deliberately not used ("promo" contains "pro").
    Google Play product IDs may carry a ":base-plan" suffix, which is ignored.
    Returns None when nothing matches a configured entitlement or product.
    """
    pro_ents = _csv_set(settings.revenuecat_pro_entitlement_ids)
    plus_ents = _csv_set(settings.revenuecat_plus_entitlement_ids)
    pro_products = _csv_set(settings.revenuecat_pro_product_ids)
    plus_products = _csv_set(settings.revenuecat_plus_product_ids)

    tiers = set()
    for ent in entitlement_ids or []:
        e = (ent or "").strip().lower()
        if e in pro_ents:
            tiers.add(SubscriptionTier.PRO)
        elif e in plus_ents:
            tiers.add(SubscriptionTier.PLUS)
    if product_id:
        base = product_id.split(":", 1)[0].strip().lower()
        if base in pro_products:
            tiers.add(SubscriptionTier.PRO)
        elif base in plus_products:
            tiers.add(SubscriptionTier.PLUS)
    if not tiers:
        return None
    return max(tiers, key=lambda t: _TIER_RANK[t])


def resolve_subscriber_id(event: RevenueCatEvent) -> Optional[str]:
    """Returns the Supabase UUID for the subscriber when any known App User ID is one.

    RevenueCat's app_user_id is the *last seen* ID; purchases made before login
    carry an anonymous ID with the Supabase UUID listed in aliases.
    Falls back to app_user_id (in-memory only) when no UUID is known.
    """
    candidates = [event.app_user_id, event.original_app_user_id, *(event.aliases or [])]
    for candidate in candidates:
        if _is_uuid(candidate):
            return str(candidate)
    return event.app_user_id


def _event_order_ms(event: Dict[str, Any]) -> Optional[int]:
    """The timestamp used to order a subscriber's events (same rule for live and stored events)."""
    for key in ("event_timestamp_ms", "purchased_at_ms", "expiration_at_ms"):
        value = event.get(key)
        if isinstance(value, int) and not isinstance(value, bool):
            return value
    return None


# Events that change a subscriber's entitlement; only these take part in ordering.
_STATE_CHANGING_EVENTS = {
    "INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "SUBSCRIPTION_EXTENDED", "REFUND_REVERSED",
    "TEMPORARY_ENTITLEMENT_GRANT", "NON_RENEWING_PURCHASE",
    "CANCELLATION", "EXPIRATION", "REVOCATION", "BILLING_ISSUE", "TRANSFER",
}


def _ms_to_datetime(ms: Optional[int]) -> Optional[datetime]:
    if ms is None:
        return None
    return datetime.fromtimestamp(ms / 1000.0, tz=timezone.utc)


def _datetime_to_ms(dt: Optional[datetime]) -> Optional[int]:
    if dt is None:
        return None
    if dt.tzinfo is None:  # SQLite returns naive datetimes; values are stored in UTC
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp() * 1000)


class WebhookStateManager:
    """In-memory & DB-backed idempotent webhook state store with bounded LRU memory.

    In production: Backed by PostgreSQL / Supabase tables `subscription_events` and `entitlements`.
    In development: Uses an OrderedDict with a fixed capacity (MAX_PROCESSED_EVENTS = 10,000)
    when DATABASE_URL is not configured.
    """
    MAX_PROCESSED_EVENTS: int = 10000

    def __init__(self):
        self._processed_event_ids: OrderedDict[str, float] = OrderedDict()
        # user_id -> (tier, timestamp_ms of the last applied event)
        self._user_entitlements: Dict[str, tuple[SubscriptionTier, int]] = {}
        # user_id -> expiry (ms since epoch) of the current entitlement, None = no expiry known
        self._user_expiry: Dict[str, Optional[int]] = {}

    def _check_persistence_mode(self):
        """Fails closed in production if database persistence is not configured."""
        if settings.app_env == "production" and not is_db_configured():
            logger.critical("Persistence failure: DATABASE_URL is not configured in production.")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database persistence unconfigured in production.",
            )

    def is_processed(self, event_id: str) -> bool:
        self._check_persistence_mode()
        return event_id in self._processed_event_ids

    async def is_processed_async(self, event_id: str) -> bool:
        self._check_persistence_mode()
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    stmt = select(SubscriptionEvent).where(SubscriptionEvent.event_id == event_id)
                    res = await session.execute(stmt)
                    if res.scalar_one_or_none() is not None:
                        return True
        return self.is_processed(event_id)

    def mark_processed(self, event_id: str):
        self._check_persistence_mode()
        self._processed_event_ids[event_id] = time.time()
        self._processed_event_ids.move_to_end(event_id)
        if len(self._processed_event_ids) > self.MAX_PROCESSED_EVENTS:
            self._processed_event_ids.popitem(last=False)

    async def mark_processed_async(
        self,
        event_id: str,
        app_user_id: str = "",
        event_type: str = "",
        product_id: Optional[str] = None,
        store: Optional[str] = None,
        environment: str = "PRODUCTION",
        raw_payload: Optional[Dict[str, Any]] = None,
    ):
        self._check_persistence_mode()
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    sub_event = SubscriptionEvent(
                        event_id=event_id,
                        app_user_id=app_user_id,
                        event_type=event_type,
                        product_id=product_id,
                        store=store or "revenuecat",
                        environment=environment,
                        raw_payload=raw_payload or {},
                    )
                    session.add(sub_event)
                    try:
                        await session.commit()
                    except Exception as e:
                        # A concurrent delivery of the same event already recorded it.
                        logger.warning(f"Could not persist subscription event to DB: {type(e).__name__}")
                        await session.rollback()
        self.mark_processed(event_id)

    def is_stale(self, user_id: str, timestamp_ms: int) -> bool:
        """True when a newer event has already been applied for this user (this process)."""
        current = self._user_entitlements.get(user_id)
        return current is not None and timestamp_ms < current[1]

    async def is_stale_async(self, user_id: str, timestamp_ms: int) -> bool:
        """True when a newer state-changing event was already processed for this user.

        Uses the recorded events in the database as well as this process's memory,
        so ordering survives restarts and redeploys and holds across workers:
        RevenueCat may deliver (or retry) an older event after a newer one.
        Raises EntitlementPersistenceError when the history cannot be read, so the
        event is retried instead of possibly overwriting newer state.
        """
        if self.is_stale(user_id, timestamp_ms):
            return True
        if not user_id or not is_db_configured():
            return False
        factory = get_session_factory()
        if factory is None:
            return False
        try:
            async with factory() as session:
                stmt = select(SubscriptionEvent.raw_payload).where(
                    SubscriptionEvent.app_user_id == user_id,
                    SubscriptionEvent.event_type.in_(_STATE_CHANGING_EVENTS),
                )
                payloads = (await session.execute(stmt)).scalars().all()
        except Exception as db_err:
            logger.error(f"Could not read subscription history for user={user_id}: {type(db_err).__name__}")
            raise EntitlementPersistenceError("subscription history unavailable") from None
        for payload in payloads:
            stored = (payload or {}).get("event") if isinstance(payload, dict) else None
            stored_ts = _event_order_ms(stored) if isinstance(stored, dict) else None
            if stored_ts is not None and timestamp_ms < stored_ts:
                return True
        return False

    def set_user_tier(
        self,
        user_id: str,
        tier: SubscriptionTier,
        timestamp_ms: Optional[int] = None,
        expires_at_ms: Optional[int] = None,
    ) -> bool:
        """Sets the user tier if incoming event is not older than already processed events."""
        self._check_persistence_mode()
        ts = timestamp_ms or _now_ms()
        if self.is_stale(user_id, ts):
            last_ts = self._user_entitlements[user_id][1]
            logger.warning(
                f"Out-of-order webhook event dropped for user={user_id}: "
                f"incoming_ts={ts} < last_ts={last_ts}"
            )
            return False
        self._user_entitlements[user_id] = (tier, ts)
        self._user_expiry[user_id] = expires_at_ms
        return True

    async def set_user_tier_async(
        self,
        user_id: str,
        tier: SubscriptionTier,
        timestamp_ms: Optional[int] = None,
        status_val: str = "active",
        expires_at_ms: Optional[int] = None,
    ) -> bool:
        """Applies the tier in memory and persists it.

        Raises EntitlementPersistenceError when the database write fails, so the
        webhook is answered with 500 and RevenueCat retries it.
        """
        self._check_persistence_mode()
        updated = self.set_user_tier(user_id, tier, timestamp_ms, expires_at_ms)

        if not _is_uuid(user_id):
            logger.warning(
                f"RevenueCat app_user_id '{user_id}' is not a valid UUID. "
                "Retaining in-memory entitlement cache only; skipping PostgreSQL persistence."
            )
            return updated

        if updated and is_db_configured():
            factory = get_session_factory()
            if factory:
                user_uuid = str(uuid.UUID(str(user_id)))
                try:
                    async with factory() as session:
                        user = await session.get(User, user_uuid)
                        if not user:
                            try:
                                user = User(id=user_uuid, email=f"{user_id}@coinscan.app")
                                session.add(user)
                                await session.flush()
                            except IntegrityError:
                                # No matching Supabase auth user (e.g. deleted account):
                                # there is nobody to grant the entitlement to. Any other
                                # database error falls through to the retryable path below.
                                await session.rollback()
                                logger.warning(
                                    f"Cannot auto-create User({user_id}) in public.users "
                                    "(no matching auth.users row); entitlement not stored."
                                )
                                return updated
                        ent = await session.get(Entitlement, user_uuid)
                        if ent is None:
                            ent = Entitlement(user_id=user_uuid)
                            session.add(ent)
                        ent.tier = tier.value
                        ent.status = status_val
                        ent.expires_at = _ms_to_datetime(expires_at_ms)
                        await session.commit()
                except Exception as db_err:
                    # Exception text can include SQL parameters: log the type only.
                    logger.error(
                        f"Database error persisting entitlement for user={user_id}: {type(db_err).__name__}"
                    )
                    raise EntitlementPersistenceError(str(db_err)) from db_err
        return updated

    def get_user_tier(self, user_id: str) -> SubscriptionTier:
        self._check_persistence_mode()
        entry = self._user_entitlements.get(user_id)
        if not entry:
            return SubscriptionTier.FREE
        expires = self._user_expiry.get(user_id)
        if expires is not None and expires <= _now_ms():
            return SubscriptionTier.FREE
        return entry[0]

    async def get_user_entitlement_async(self, user_id: str) -> Tuple[SubscriptionTier, Optional[int]]:
        """Returns (effective tier, expiry ms). Expired entitlements resolve to FREE."""
        self._check_persistence_mode()
        if _is_uuid(user_id) and is_db_configured():
            factory = get_session_factory()
            if factory:
                try:
                    async with factory() as session:
                        ent = await session.get(Entitlement, str(uuid.UUID(str(user_id))))
                        if ent and ent.tier:
                            try:
                                tier = SubscriptionTier(ent.tier.lower())
                            except ValueError:
                                tier = SubscriptionTier.FREE
                            expires_ms = _datetime_to_ms(ent.expires_at)
                            if expires_ms is not None and expires_ms <= _now_ms():
                                return SubscriptionTier.FREE, expires_ms
                            return tier, expires_ms
                except Exception as e:
                    logger.warning(f"Error reading tier from DB for user={user_id}: {type(e).__name__}")
        return self.get_user_tier(user_id), self._user_expiry.get(user_id)

    async def get_user_tier_async(self, user_id: str) -> SubscriptionTier:
        tier, _ = await self.get_user_entitlement_async(user_id)
        return tier

    def reset_user(self, user_id: str):
        """Purges entitlement records for a deleted user account."""
        self._check_persistence_mode()
        self._user_entitlements.pop(user_id, None)
        self._user_expiry.pop(user_id, None)

    def reset_for_test(self):
        self._processed_event_ids.clear()
        self._user_entitlements.clear()
        self._user_expiry.clear()


webhook_state = WebhookStateManager()

_GRANT_EVENTS = {
    "INITIAL_PURCHASE",
    "RENEWAL",
    "UNCANCELLATION",
    "SUBSCRIPTION_EXTENDED",
    "REFUND_REVERSED",
    "TEMPORARY_ENTITLEMENT_GRANT",
    "NON_RENEWING_PURCHASE",
}
_TEMPORARY_GRANT_MS = 24 * 60 * 60 * 1000


async def _apply_grant(event: RevenueCatEvent, event_type: str, user_id: str, event_ts: int) -> Tuple[str, SubscriptionTier]:
    tier = resolve_tier(event.entitlement_ids or ([event.entitlement_id] if event.entitlement_id else None), event.product_id)
    current = await webhook_state.get_user_tier_async(user_id)
    if tier is None:
        # Never downgrade a paying user because of an unrecognised product.
        logger.warning(
            f"Unknown product/entitlement in webhook: product_id={event.product_id} "
            f"entitlement_ids={event.entitlement_ids}. Tier left unchanged."
        )
        return "unknown_product_ignored", current

    expires_ms = event.expiration_at_ms
    if expires_ms is None and event_type == "TEMPORARY_ENTITLEMENT_GRANT":
        expires_ms = event_ts + _TEMPORARY_GRANT_MS
    if expires_ms is None and event_type == "NON_RENEWING_PURCHASE":
        # Subscriptions are the only sold products; a lifetime grant is never inferred.
        logger.warning("NON_RENEWING_PURCHASE without expiration ignored.")
        return "non_renewing_without_expiration_ignored", current

    if expires_ms is not None and expires_ms <= _now_ms():
        updated = await webhook_state.set_user_tier_async(
            user_id, SubscriptionTier.FREE, timestamp_ms=event_ts, status_val="expired", expires_at_ms=expires_ms
        )
        return ("grant_already_expired" if updated else "out_of_order_event_ignored"), (
            SubscriptionTier.FREE if updated else current
        )

    status_val = "trial" if (event.period_type or "").upper() == "TRIAL" else "active"
    updated = await webhook_state.set_user_tier_async(
        user_id, tier, timestamp_ms=event_ts, status_val=status_val, expires_at_ms=expires_ms
    )
    if not updated:
        return "out_of_order_event_ignored", current
    return f"subscription_activated_{tier.value}", tier


async def _apply_cancellation(event: RevenueCatEvent, user_id: str, event_ts: int) -> Tuple[str, SubscriptionTier]:
    current = await webhook_state.get_user_tier_async(user_id)
    expires_ms = event.expiration_at_ms
    is_refund = (event.cancel_reason or "").upper() == "CUSTOMER_SUPPORT"
    already_ended = expires_ms is not None and (expires_ms <= event_ts or expires_ms <= _now_ms())

    if is_refund or already_ended:
        updated = await webhook_state.set_user_tier_async(
            user_id, SubscriptionTier.FREE, timestamp_ms=event_ts, status_val="revoked", expires_at_ms=expires_ms
        )
        if not updated:
            return "out_of_order_event_ignored", current
        return "refund_or_immediate_cancellation_revoked", SubscriptionTier.FREE

    # Auto-renew turned off: access continues until the period ends.
    if current != SubscriptionTier.FREE and expires_ms is not None:
        await webhook_state.set_user_tier_async(
            user_id, current, timestamp_ms=event_ts, status_val="cancelled", expires_at_ms=expires_ms
        )
    return "cancellation_scheduled_at_period_end", current


async def _apply_expiration(event: RevenueCatEvent, event_type: str, user_id: str, event_ts: int) -> Tuple[str, SubscriptionTier]:
    current, current_expires = await webhook_state.get_user_entitlement_async(user_id)

    if (
        current_expires is not None
        and event.expiration_at_ms is not None
        and current_expires > event.expiration_at_ms + _EXPIRY_TOLERANCE_MS
    ):
        # The user already has a later period (e.g. renewal processed first).
        return "stale_expiration_ignored", current

    expiring_tier = resolve_tier(event.entitlement_ids, event.product_id)
    if expiring_tier is not None and _TIER_RANK[current] > _TIER_RANK[expiring_tier]:
        # e.g. the old Plus product expiring after an upgrade to Pro.
        return "expiration_of_lower_tier_ignored", current

    status_val = "revoked" if event_type == "REVOCATION" else "expired"
    updated = await webhook_state.set_user_tier_async(
        user_id, SubscriptionTier.FREE, timestamp_ms=event_ts, status_val=status_val,
        expires_at_ms=event.expiration_at_ms,
    )
    if not updated:
        return "out_of_order_event_ignored", current
    return "subscription_downgraded_to_free", SubscriptionTier.FREE


async def _apply_transfer(event: RevenueCatEvent, event_ts: int) -> Tuple[str, str, SubscriptionTier]:
    destinations = event.transferred_to or []
    destination = next((d for d in destinations if _is_uuid(d)), destinations[0] if destinations else None)
    if not destination:
        return "transfer_missing_destination_ignored", "", SubscriptionTier.FREE

    best_tier, best_expires = SubscriptionTier.FREE, None
    for source in event.transferred_from or []:
        tier, expires = await webhook_state.get_user_entitlement_async(source)
        if _TIER_RANK[tier] > _TIER_RANK[best_tier]:
            best_tier, best_expires = tier, expires

    if best_tier == SubscriptionTier.FREE:
        current = await webhook_state.get_user_tier_async(destination)
        return "transfer_no_known_entitlement", destination, current

    await webhook_state.set_user_tier_async(
        destination, best_tier, timestamp_ms=event_ts, status_val="active", expires_at_ms=best_expires
    )
    for source in event.transferred_from or []:
        if source != destination:
            await webhook_state.set_user_tier_async(
                source, SubscriptionTier.FREE, timestamp_ms=event_ts, status_val="revoked"
            )
    return f"entitlement_transferred_{best_tier.value}", destination, best_tier


@router.post("/revenuecat", response_model=WebhookProcessingResult)
async def handle_revenuecat_webhook(
    payload: RevenueCatWebhookPayload,
    authorization: Optional[str] = Header(None),
) -> WebhookProcessingResult:
    """
    Receives and processes RevenueCat server-to-server webhook events.
    """
    event = payload.event
    event_id = event.id

    # 1. Verify Webhook Auth Token (Fail Closed)
    expected_secret = getattr(settings, "revenuecat_webhook_secret", None)
    if not expected_secret or not expected_secret.strip():
        logger.error("RevenueCat webhook secret is not configured or empty. Failing closed.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Webhook secret not configured on server.",
        )

    if not authorization or not authorization.strip():
        logger.warning("Unauthorized RevenueCat webhook attempt rejected (missing authorization header).")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing webhook authorization.",
        )

    clean_secret = expected_secret.strip()
    clean_auth = authorization.strip()
    expected_bearer = f"Bearer {clean_secret}"

    if not (
        hmac.compare_digest(clean_auth, expected_bearer)
        or hmac.compare_digest(clean_auth, clean_secret)
    ):
        logger.warning("Unauthorized RevenueCat webhook attempt rejected (signature mismatch).")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized webhook signature.",
        )

    event_type = event.type.upper()
    user_id = resolve_subscriber_id(event) or ""

    # 2. Idempotency Check
    if await webhook_state.is_processed_async(event_id):
        logger.info(f"Duplicate webhook event {event_id} received. Returning idempotent OK.")
        curr_tier = await webhook_state.get_user_tier_async(user_id) if user_id else SubscriptionTier.FREE
        return WebhookProcessingResult(
            status="duplicate_ignored",
            event_id=event_id,
            action_taken="none",
            user_id=user_id,
            resolved_tier=curr_tier.value,
        )

    # 3. Process Event by Type
    event_ts = _event_order_ms(event.model_dump()) or _now_ms()
    state_changing = _GRANT_EVENTS | {"CANCELLATION", "EXPIRATION", "REVOCATION", "BILLING_ISSUE"}

    try:
        if event_type == "TEST":
            action_taken, resolved_tier = "test_event_acknowledged", SubscriptionTier.FREE

        elif event_type == "TRANSFER":
            action_taken, user_id, resolved_tier = await _apply_transfer(event, event_ts)

        elif not user_id:
            action_taken, resolved_tier = "missing_app_user_id_ignored", SubscriptionTier.FREE

        elif event_type in state_changing and await webhook_state.is_stale_async(user_id, event_ts):
            action_taken = "out_of_order_event_ignored"
            resolved_tier = await webhook_state.get_user_tier_async(user_id)

        elif event_type in _GRANT_EVENTS:
            action_taken, resolved_tier = await _apply_grant(event, event_type, user_id, event_ts)

        elif event_type == "PRODUCT_CHANGE":
            # Informational only; the tier changes when the new product's
            # RENEWAL / INITIAL_PURCHASE event arrives.
            logger.info(
                f"Product change recorded for user={user_id}: "
                f"{event.product_id} -> {event.new_product_id} (no tier change until it takes effect)"
            )
            action_taken = "product_change_recorded_pending_effective_event"
            resolved_tier = await webhook_state.get_user_tier_async(user_id)

        elif event_type == "CANCELLATION":
            action_taken, resolved_tier = await _apply_cancellation(event, user_id, event_ts)

        elif event_type in ("EXPIRATION", "REVOCATION"):
            action_taken, resolved_tier = await _apply_expiration(event, event_type, user_id, event_ts)

        elif event_type == "BILLING_ISSUE":
            # Access is retained during the store's grace period.
            action_taken = "grace_period_notified"
            resolved_tier, current_expires = await webhook_state.get_user_entitlement_async(user_id)
            grace_end = event.grace_period_expiration_at_ms
            if resolved_tier != SubscriptionTier.FREE and grace_end is not None:
                await webhook_state.set_user_tier_async(
                    user_id, resolved_tier, timestamp_ms=event_ts, status_val="billing_retry",
                    expires_at_ms=max(grace_end, current_expires or 0),
                )

        elif event_type == "SUBSCRIPTION_PAUSED":
            # Pause takes effect at period end; access is revoked by the later EXPIRATION.
            action_taken = "pause_scheduled_no_change"
            resolved_tier = await webhook_state.get_user_tier_async(user_id)

        else:
            action_taken = f"unhandled_event_{event_type.lower()}"
            resolved_tier = await webhook_state.get_user_tier_async(user_id)

    except EntitlementPersistenceError:
        # Do NOT mark the event processed: a 5xx makes RevenueCat retry it.
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Entitlement could not be persisted; please retry.",
        )

    # 4. Mark Event Processed for Idempotency
    await webhook_state.mark_processed_async(
        event_id=event_id,
        app_user_id=user_id or (event.app_user_id or ""),
        event_type=event_type,
        product_id=event.product_id,
        store=event.store,
        environment=event.environment or "PRODUCTION",
        raw_payload=payload.model_dump(),
    )
    logger.info(
        f"Webhook event processed: id={event_id} type={event_type} "
        f"user={user_id} action={action_taken} tier={resolved_tier.value}"
    )

    return WebhookProcessingResult(
        status="success",
        event_id=event_id,
        action_taken=action_taken,
        user_id=user_id,
        resolved_tier=resolved_tier.value,
    )
