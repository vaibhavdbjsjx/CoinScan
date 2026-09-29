"""
Account Management API: Deletion, Data Portability (Export), and Mandatory Legal Consent.

Implements:
1. GDPR / App Store compliant permanent account deletion (cascading cleanup).
2. Data export engine producing complete, structured user archives without secret leakage.
3. Server-authoritative Terms & Conditions and Privacy Policy consent management.
"""

import time
import uuid
import logging
from typing import Dict, Any, List, Optional
from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException, status

from datetime import datetime, timezone
from backend.app.config import settings
from backend.app.security.auth import get_current_user, verify_terms_accepted, AuthenticatedUser
from backend.app.api.feedback import feedback_store
from backend.app.security.api_key_service import api_key_service
from backend.app.models.legal import TermsConsentRequest, TermsConsentResponse
from backend.app.db.session import is_db_configured, get_session_factory
from backend.app.db.models import User, UserLegalConsent, CollectionItem, ScanHistory, Feedback, Entitlement, ScanUsage
from sqlalchemy import select, delete
import httpx

logger = logging.getLogger("coinscan.account")
router = APIRouter(prefix="/v1/account", tags=["Account Management"])


class UserProfileResponse(BaseModel):
    id: str
    email: str
    display_name: str
    preferred_currency: str = "USD"
    tier: str
    created_at: float


class QuotaStatusResponse(BaseModel):
    user_id: str
    tier: str
    daily_limit: int
    scans_used_today: int
    scans_remaining_today: int
    resets_at_utc: str


class ScanRecordResponse(BaseModel):
    id: str
    user_id: str
    scanned_at: float
    coin_name: Optional[str] = None
    country: Optional[str] = None
    denomination: Optional[str] = None
    year: Optional[str] = None
    mint_mark: Optional[str] = None
    grade: Optional[str] = None
    confidence_score: Optional[float] = None
    numista_id: Optional[int] = None
    status_label: str = "identified"
    front_image_url: Optional[str] = None
    reverse_image_url: Optional[str] = None


class AccountDeletionConfirmation(BaseModel):
    confirm_phrase: str  # Must match "DELETE MY ACCOUNT" to avoid accidental triggers
    reason: str = "User requested account deletion"


class AccountDeletionResponse(BaseModel):
    status: str
    user_id: str
    message: str
    deleted_at: float
    items_purged: Dict[str, int]


class AccountDataExportResponse(BaseModel):
    export_version: str = "1.0.0"
    exported_at: float
    user_profile: Dict[str, Any]
    entitlements: Dict[str, Any]
    legal_consent: Optional[Dict[str, Any]] = None
    scan_history: List[Dict[str, Any]]
    collection_items: List[Dict[str, Any]]
    feedback_submissions: List[Dict[str, Any]]


async def delete_supabase_auth_user(user_id: str) -> bool:
    """
    Permanently deletes user credentials from Supabase auth.users via
    the Supabase GoTrue Admin API. Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.
    """
    if not settings.supabase_url or not settings.supabase_service_role_key:
        logger.warning(
            f"Supabase Admin API credentials not configured; skipping auth.users deletion for user={user_id}"
        )
        return False

    url = f"{settings.supabase_url.rstrip('/')}/auth/v1/admin/users/{user_id}"
    headers = {
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "apikey": settings.supabase_service_role_key,
    }
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.delete(url, headers=headers)
            if resp.status_code in (200, 204, 404):
                logger.info(f"Supabase auth.users record purged for user={user_id} (status: {resp.status_code})")
                return True
            else:
                logger.error(
                    f"Failed to purge Supabase auth.users for user={user_id}: HTTP {resp.status_code} {resp.text}"
                )
                return False
    except Exception as e:
        logger.error(f"Error calling Supabase GoTrue Admin API for user={user_id}: {e}")
        return False


class AccountStore:
    """Manages user state deletion, legal consent, and export compilation.

    In production: Backed by PostgreSQL / Supabase with strict foreign-key cascading.
    In development: Employs memory structures when DATABASE_URL is unconfigured.
    """

    def __init__(self):
        # user_id -> dict of mock user profile data
        self._profiles: Dict[str, Dict[str, Any]] = {}
        # user_id -> list of collections
        self._collections: Dict[str, List[Dict[str, Any]]] = {}
        # user_id -> list of scans
        self._scans: Dict[str, List[Dict[str, Any]]] = {}
        # user_id -> dict of consent record
        self._consents: Dict[str, Dict[str, Any]] = {}

    def _check_persistence_mode(self):
        """Fails closed in production if database persistence is not configured."""
        if settings.app_env == "production" and not is_db_configured():
            logger.critical("Persistence failure: DATABASE_URL is not configured in production.")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database persistence unconfigured in production.",
            )

    def get_or_create_profile(self, user_id: str) -> Dict[str, Any]:
        self._check_persistence_mode()
        if user_id not in self._profiles:
            self._profiles[user_id] = {
                "id": user_id,
                "created_at": time.time() - 86400 * 30,
                "email": f"{user_id}@coinscan.app",
                "display_name": "CoinScan Collector",
                "preferred_currency": "USD",
            }
        return self._profiles[user_id]

    async def get_or_create_profile_async(self, user_id: str) -> Dict[str, Any]:
        self._check_persistence_mode()
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    db_user = await session.get(User, user_id)
                    if db_user:
                        return {
                            "id": db_user.id,
                            "created_at": db_user.created_at.timestamp() if db_user.created_at else time.time(),
                            "email": db_user.email,
                            "display_name": db_user.display_name or "CoinScan Collector",
                            "preferred_currency": db_user.preferred_currency,
                        }
                    else:
                        new_user = User(
                            id=user_id,
                            email=f"{user_id}@coinscan.app",
                            display_name="CoinScan Collector",
                            preferred_currency="USD",
                        )
                        session.add(new_user)
                        await session.commit()
                        return {
                            "id": new_user.id,
                            "created_at": time.time(),
                            "email": new_user.email,
                            "display_name": new_user.display_name,
                            "preferred_currency": new_user.preferred_currency,
                        }
        return self.get_or_create_profile(user_id)

    def record_consent(
        self,
        user_id: str,
        terms_version: str,
        privacy_version: str,
        accepted_at: Optional[float] = None,
    ) -> Dict[str, Any]:
        self._check_persistence_mode()
        record = {
            "user_id": user_id,
            "terms_version": terms_version,
            "privacy_version": privacy_version,
            "accepted_at": accepted_at or time.time(),
        }
        self._consents[user_id] = record
        return record

    async def record_consent_async(
        self,
        user_id: str,
        terms_version: str,
        privacy_version: str,
        accepted_at: Optional[float] = None,
    ) -> Dict[str, Any]:
        self._check_persistence_mode()
        now = accepted_at or time.time()
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    db_user = await session.get(User, user_id)
                    if not db_user:
                        db_user = User(
                            id=user_id,
                            email=f"{user_id}@coinscan.app",
                            display_name="CoinScan Collector",
                        )
                        session.add(db_user)
                        await session.flush()

                    db_consent = await session.get(UserLegalConsent, user_id)
                    dt_now = datetime.fromtimestamp(now, tz=timezone.utc)
                    if db_consent:
                        db_consent.terms_version = terms_version
                        db_consent.privacy_version = privacy_version
                        db_consent.accepted_at = dt_now
                    else:
                        db_consent = UserLegalConsent(
                            user_id=user_id,
                            terms_version=terms_version,
                            privacy_version=privacy_version,
                            accepted_at=dt_now,
                        )
                        session.add(db_consent)
                    await session.commit()
        return self.record_consent(user_id, terms_version, privacy_version, now)

    def get_consent(self, user_id: str) -> Optional[Dict[str, Any]]:
        self._check_persistence_mode()
        return self._consents.get(user_id)

    async def get_consent_async(self, user_id: str) -> Optional[Dict[str, Any]]:
        self._check_persistence_mode()
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    db_consent = await session.get(UserLegalConsent, user_id)
                    if db_consent:
                        return {
                            "user_id": db_consent.user_id,
                            "terms_version": db_consent.terms_version,
                            "privacy_version": db_consent.privacy_version,
                            "accepted_at": db_consent.accepted_at.timestamp() if db_consent.accepted_at else time.time(),
                        }
                    return None
        return self.get_consent(user_id)

    def add_collection_item(self, user_id: str, item: Dict[str, Any]):
        self._check_persistence_mode()
        self._collections.setdefault(user_id, []).append(item)

    async def add_collection_item_async(self, user_id: str, item: Dict[str, Any]):
        self._check_persistence_mode()
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    db_user = await session.get(User, user_id)
                    if not db_user:
                        db_user = User(id=user_id, email=f"{user_id}@coinscan.app")
                        session.add(db_user)
                        await session.flush()

                    db_item = CollectionItem(
                        id=item.get("id"),
                        user_id=user_id,
                        coin_name=item["coin_name"],
                        country=item["country"],
                        denomination=item["denomination"],
                        year=item.get("year"),
                        mint_mark=item.get("mint_mark"),
                        composition=item.get("composition"),
                        grade=item.get("grade"),
                        numista_id=item.get("numista_id"),
                        purchase_price=item.get("purchase_price"),
                        currency_code=item.get("currency_code", "USD"),
                        initial_valuation_snapshot=item.get("initial_valuation_snapshot"),
                        current_estimated_value=item.get("current_estimated_value"),
                        notes=item.get("notes"),
                        front_image_url=item.get("front_image_url"),
                        reverse_image_url=item.get("reverse_image_url"),
                    )
                    session.add(db_item)
                    await session.commit()
        self.add_collection_item(user_id, item)

    def get_collection_items(self, user_id: str) -> List[Dict[str, Any]]:
        self._check_persistence_mode()
        return self._collections.get(user_id, [])

    async def get_collection_items_async(self, user_id: str) -> List[Dict[str, Any]]:
        self._check_persistence_mode()
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    stmt = (
                        select(CollectionItem)
                        .where(CollectionItem.user_id == user_id)
                        .order_by(CollectionItem.created_at.desc())
                    )
                    result = await session.execute(stmt)
                    rows = result.scalars().all()
                    return [
                        {
                            "id": r.id,
                            "user_id": r.user_id,
                            "coin_name": r.coin_name,
                            "country": r.country,
                            "denomination": r.denomination,
                            "year": r.year,
                            "mint_mark": r.mint_mark,
                            "composition": r.composition,
                            "grade": r.grade,
                            "numista_id": r.numista_id,
                            "purchase_price": float(r.purchase_price) if r.purchase_price is not None else None,
                            "currency_code": r.currency_code,
                            "initial_valuation_snapshot": float(r.initial_valuation_snapshot) if r.initial_valuation_snapshot is not None else None,
                            "current_estimated_value": float(r.current_estimated_value) if r.current_estimated_value is not None else None,
                            "notes": r.notes,
                            "front_image_url": r.front_image_url,
                            "reverse_image_url": r.reverse_image_url,
                            "is_favorite": r.is_favorite,
                            "created_at": r.created_at.timestamp() if r.created_at else time.time(),
                            "updated_at": r.updated_at.timestamp() if r.updated_at else time.time(),
                        }
                        for r in rows
                    ]
        return self.get_collection_items(user_id)

    def delete_collection_item(self, user_id: str, item_id: str) -> bool:
        self._check_persistence_mode()
        items = self._collections.get(user_id, [])
        initial_len = len(items)
        self._collections[user_id] = [i for i in items if i.get("id") != item_id]
        return len(self._collections[user_id]) < initial_len

    async def delete_collection_item_async(self, user_id: str, item_id: str) -> bool:
        self._check_persistence_mode()
        deleted = False
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    stmt = delete(CollectionItem).where(
                        CollectionItem.user_id == user_id,
                        CollectionItem.id == item_id,
                    )
                    res = await session.execute(stmt)
                    await session.commit()
                    deleted = res.rowcount > 0
        mem_deleted = self.delete_collection_item(user_id, item_id)
        return deleted or mem_deleted

    def add_scan(self, user_id: str, scan: Dict[str, Any]):
        self._check_persistence_mode()
        self._scans.setdefault(user_id, []).insert(0, scan)

    async def add_scan_async(self, user_id: str, scan: Dict[str, Any]):
        self._check_persistence_mode()
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    db_user = await session.get(User, user_id)
                    if not db_user:
                        db_user = User(id=user_id, email=f"{user_id}@coinscan.app")
                        session.add(db_user)
                        await session.flush()

                    db_scan = ScanHistory(
                        id=scan.get("id") or str(uuid.uuid4()),
                        user_id=user_id,
                        coin_name=scan.get("coin_name"),
                        country=scan.get("country"),
                        denomination=scan.get("denomination"),
                        year=str(scan.get("year")) if scan.get("year") is not None else None,
                        mint_mark=scan.get("mint_mark"),
                        grade=scan.get("grade"),
                        confidence_score=scan.get("confidence_score"),
                        numista_id=scan.get("numista_id"),
                        status_label=scan.get("status_label") or "identified",
                        front_image_url=scan.get("front_image_url"),
                        reverse_image_url=scan.get("reverse_image_url"),
                        result_json=scan.get("result_json"),
                    )
                    session.add(db_scan)
                    await session.commit()
        self.add_scan(user_id, scan)

    def get_scans(self, user_id: str) -> List[Dict[str, Any]]:
        self._check_persistence_mode()
        return self._scans.get(user_id, [])

    async def get_scans_async(self, user_id: str) -> List[Dict[str, Any]]:
        self._check_persistence_mode()
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    stmt = (
                        select(ScanHistory)
                        .where(ScanHistory.user_id == user_id)
                        .order_by(ScanHistory.scanned_at.desc())
                    )
                    result = await session.execute(stmt)
                    rows = result.scalars().all()
                    return [
                        {
                            "id": r.id,
                            "user_id": r.user_id,
                            "scanned_at": r.scanned_at.timestamp() if r.scanned_at else time.time(),
                            "coin_name": r.coin_name,
                            "country": r.country,
                            "denomination": r.denomination,
                            "year": r.year,
                            "mint_mark": r.mint_mark,
                            "grade": r.grade,
                            "confidence_score": float(r.confidence_score) if r.confidence_score is not None else None,
                            "numista_id": r.numista_id,
                            "status_label": r.status_label,
                            "front_image_url": r.front_image_url,
                            "reverse_image_url": r.reverse_image_url,
                        }
                        for r in rows
                    ]
        return self.get_scans(user_id)

    def delete_account(self, user_id: str) -> Dict[str, int]:
        """Permanently cascades and removes all user records across all subsystems."""
        self._check_persistence_mode()
        profile_count = 1 if user_id in self._profiles else 0
        self._profiles.pop(user_id, None)

        consent_count = 1 if user_id in self._consents else 0
        self._consents.pop(user_id, None)

        collection_count = len(self._collections.pop(user_id, []))
        scan_count = len(self._scans.pop(user_id, []))

        # Revoke all API keys owned by this user
        revoked_keys_count = 0
        for key_id, key_record in list(api_key_service._keys_by_id.items()):
            if key_record.user_id == user_id:
                key_record.is_active = False
                revoked_keys_count += 1

        # Purge entitlement records and quota
        from backend.app.api.webhooks import webhook_state
        from backend.app.security.quota_service import quota_engine
        webhook_state.reset_user(user_id)
        quota_engine.purge_user(user_id)

        logger.info(
            f"Account deleted permanently: user={user_id} "
            f"purged: profiles={profile_count} consents={consent_count} "
            f"collections={collection_count} scans={scan_count} keys={revoked_keys_count}"
        )

        return {
            "profile": profile_count,
            "legal_consents": consent_count,
            "collection_items": collection_count,
            "scans": scan_count,
            "api_keys_revoked": revoked_keys_count,
        }

    async def delete_account_async(self, user_id: str) -> Dict[str, int]:
        self._check_persistence_mode()
        purged = self.delete_account(user_id)
        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    db_user = await session.get(User, user_id)
                    if db_user:
                        await session.delete(db_user)
                    else:
                        # Fallback explicit deletion across all child tables
                        await session.execute(delete(Entitlement).where(Entitlement.user_id == user_id))
                        await session.execute(delete(CollectionItem).where(CollectionItem.user_id == user_id))
                        await session.execute(delete(ScanUsage).where(ScanUsage.user_id == user_id))
                        await session.execute(delete(ScanHistory).where(ScanHistory.user_id == user_id))
                        await session.execute(delete(UserLegalConsent).where(UserLegalConsent.user_id == user_id))
                        await session.execute(delete(User).where(User.id == user_id))
                    await session.commit()
        auth_purged = await delete_supabase_auth_user(user_id)
        if auth_purged:
            purged["supabase_auth_users"] = 1
        return purged

    def reset_for_test(self):
        self._profiles.clear()
        self._collections.clear()
        self._scans.clear()
        self._consents.clear()


account_store = AccountStore()


@router.get("/me", response_model=UserProfileResponse)
async def get_my_profile(
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Retrieves the authenticated user's authoritative profile and entitlement tier.
    """
    if not current_user.is_authenticated:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required.",
        )
    profile = await account_store.get_or_create_profile_async(current_user.user_id)
    return UserProfileResponse(
        id=profile["id"],
        email=profile.get("email") or f"{current_user.user_id}@coinscan.app",
        display_name=profile.get("display_name") or "CoinScan Collector",
        preferred_currency=profile.get("preferred_currency") or "USD",
        tier=current_user.tier.value,
        created_at=profile.get("created_at") or time.time(),
    )


@router.get("/quota", response_model=QuotaStatusResponse)
async def get_my_quota(
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Retrieves the server-authoritative daily scan quota and remaining balance.
    """
    if not current_user.is_authenticated:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required.",
        )
    from backend.app.security.quota_service import quota_engine
    quota_info = await quota_engine.get_quota_status_async(
        current_user.user_id,
        current_user.tier,
    )
    return QuotaStatusResponse(**quota_info)


@router.get("/history", response_model=List[ScanRecordResponse])
async def get_my_scan_history(
    current_user: AuthenticatedUser = Depends(verify_terms_accepted),
):
    """
    Retrieves historical coin scan analyses performed by the authenticated user.
    """
    if not current_user.is_authenticated:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required.",
        )
    scans = await account_store.get_scans_async(current_user.user_id)
    return [ScanRecordResponse(**s) for s in scans]


@router.post("/consent", response_model=TermsConsentResponse)
@router.post("/legal/consent", response_model=TermsConsentResponse)
async def record_legal_consent(
    consent_in: TermsConsentRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Records or updates the authenticated user's acceptance of mandatory
    Terms & Conditions and Privacy Policy versions.
    Enforces that a user can only record consent for their own authenticated account.
    """
    if not current_user.is_authenticated:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required to record legal consent.",
        )

    now = consent_in.accepted_at or time.time()
    record = await account_store.record_consent_async(
        user_id=current_user.user_id,
        terms_version=consent_in.terms_version,
        privacy_version=consent_in.privacy_version,
        accepted_at=now,
    )

    is_current = (
        record["terms_version"] == settings.required_terms_version
        and record["privacy_version"] == settings.required_privacy_version
    )

    logger.info(
        f"Legal consent recorded: user={current_user.user_id} "
        f"terms={consent_in.terms_version} privacy={consent_in.privacy_version} "
        f"is_current={is_current}"
    )

    return TermsConsentResponse(
        status="success",
        user_id=current_user.user_id,
        terms_version=record["terms_version"],
        privacy_version=record["privacy_version"],
        is_current=is_current,
        accepted_at=record["accepted_at"],
        required_terms_version=settings.required_terms_version,
        required_privacy_version=settings.required_privacy_version,
    )


@router.get("/consent", response_model=TermsConsentResponse)
@router.get("/legal/consent", response_model=TermsConsentResponse)
async def get_legal_consent(
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Retrieves the authenticated user's current Terms & Conditions consent status.
    """
    if not current_user.is_authenticated:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required.",
        )

    record = await account_store.get_consent_async(current_user.user_id)
    if not record:
        return TermsConsentResponse(
            status="not_accepted",
            user_id=current_user.user_id,
            terms_version="",
            privacy_version="",
            is_current=False,
            accepted_at=0.0,
            required_terms_version=settings.required_terms_version,
            required_privacy_version=settings.required_privacy_version,
        )

    is_current = (
        record["terms_version"] == settings.required_terms_version
        and record["privacy_version"] == settings.required_privacy_version
    )

    return TermsConsentResponse(
        status="accepted" if is_current else "reconsent_required",
        user_id=current_user.user_id,
        terms_version=record["terms_version"],
        privacy_version=record["privacy_version"],
        is_current=is_current,
        accepted_at=record["accepted_at"],
        required_terms_version=settings.required_terms_version,
        required_privacy_version=settings.required_privacy_version,
    )


@router.post("/delete", response_model=AccountDeletionResponse)
@router.delete("/delete", response_model=AccountDeletionResponse)
async def delete_account_endpoint(
    confirmation: Optional[AccountDeletionConfirmation] = None,
    confirm_phrase: Optional[str] = None,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Permanently deletes the authenticated user's account, profile, collection,
    scan history, legal consent records, and revokes all active developer API keys.
    Supports both POST and DELETE HTTP methods.
    """
    if not current_user.is_authenticated:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="You must be signed in to delete an account.",
        )

    phrase = ""
    if confirmation and confirmation.confirm_phrase:
        phrase = confirmation.confirm_phrase.strip().upper()
    elif confirm_phrase:
        phrase = confirm_phrase.strip().upper()

    if phrase != "DELETE MY ACCOUNT":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Confirmation phrase mismatch. Please enter 'DELETE MY ACCOUNT' to confirm.",
        )

    now = time.time()
    purged_metrics = await account_store.delete_account_async(current_user.user_id)

    return AccountDeletionResponse(
        status="success",
        user_id=current_user.user_id,
        message="Your account and all associated numismatic data have been permanently deleted.",
        deleted_at=now,
        items_purged=purged_metrics,
    )


@router.get("/export", response_model=AccountDataExportResponse)
async def export_user_data(
    current_user: AuthenticatedUser = Depends(verify_terms_accepted),
):
    """
    Exports all personal data, collection vault items, scan records, and legal consent
    for the authenticated user in standard JSON format.
    Requires that mandatory Terms & Conditions have been accepted.
    """
    if not current_user.is_authenticated:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="You must be signed in to export data.",
        )

    user_id = current_user.user_id
    profile = await account_store.get_or_create_profile_async(user_id)
    collections = await account_store.get_collection_items_async(user_id)
    legal_consent = await account_store.get_consent_async(user_id)
    feedbacks = [
        f.model_dump()
        for f in feedback_store.list_user_feedback(user_id)
    ]

    return AccountDataExportResponse(
        export_version="1.0.0",
        exported_at=time.time(),
        user_profile=profile,
        entitlements={
            "tier": current_user.tier.value,
            "auth_method": current_user.auth_method,
        },
        legal_consent=legal_consent,
        scan_history=await account_store.get_scans_async(user_id),
        collection_items=collections,
        feedback_submissions=feedbacks,
    )
