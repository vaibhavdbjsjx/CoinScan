"""
Recognition endpoints for processing multi-sided coin captures.
"""

import time
import base64
import uuid
import logging
from typing import Optional, List
from fastapi import APIRouter, UploadFile, File, Form, HTTPException, Request, Depends, status

from backend.app.security.auth import get_current_user, AuthenticatedUser
from backend.app.security.quota_service import quota_engine
from backend.app.api.account import account_store

from backend.app.config import settings
from backend.app.models.domain import (
    ConfidenceLevel,
    RecognitionStatus,
    ImageQualityReport,
    ImageQualityIssue,
)
from backend.app.models.requests import JsonRecognitionRequest
from backend.app.models.responses import RecognitionResponse
from backend.app.preprocessing.image_quality import ImageTooLargeError, inspect_image_quality
from backend.app.preprocessing.image_normalization import normalize_image_for_analysis
from backend.app.services.recognition.vision_provider import (
    VisionProvider,
    GeminiVisionProvider,
    OpenAIVisionProvider,
    MockVisionProvider,
    VisionProviderError,
)
from backend.app.services.recognition.ocr_service import extract_ocr_signals
from backend.app.services.recognition.evidence_engine import build_candidate_from_evidence
from backend.app.services.numista.client import (
    NumistaClient,
    CatalogueUnavailableError,
    SOURCE_NUMISTA,
    SOURCE_OFFLINE_FIXTURE,
)
from backend.app.services.valuation.valuation_service import ValuationEngine
from backend.app.services.currency.fx_service import FxService
from backend.app.security.rate_limit import rate_limiter, SubscriptionTier
from backend.app.security.client_ip import get_client_ip
from backend.app.security.guest_quota import guest_allowance
from backend.app.db.session import is_db_configured

logger = logging.getLogger("coinscan.recognition")
router = APIRouter(prefix="/v1", tags=["Recognition"])


def get_vision_provider() -> VisionProvider:
    """Instantiates configured Vision AI provider.
    
    Enforces real provider credentials in staging and production to prevent
    silent fallback to mock recognition results.
    """
    if settings.vision_provider == "gemini" and settings.gemini_api_key:
        return GeminiVisionProvider(api_key=settings.gemini_api_key, model=settings.gemini_model)
    elif settings.vision_provider == "openai" and settings.openai_api_key:
        return OpenAIVisionProvider(api_key=settings.openai_api_key, model=settings.openai_model)
    elif settings.dev_features_enabled:
        # Deterministic mock provider ONLY for local development and testing
        return MockVisionProvider()
    else:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Vision AI provider ({settings.vision_provider}) credentials are not configured on this {settings.app_env} service.",
        )


numista_client = NumistaClient(
    api_key=settings.numista_api_key,
    base_url=settings.numista_api_base_url,
    # The offline fixture is test data; it is only ever honoured for local development.
    offline_fixture=settings.numista_offline_fixture and settings.dev_features_enabled,
)
valuation_engine = ValuationEngine()
fx_service = FxService(
    api_key=settings.exchangerate_api_key,
    base_url=settings.exchangerate_api_base_url,
)


def _upload_limit_bytes() -> int:
    return settings.max_upload_mb * 1024 * 1024


def _upload_too_large(label: str) -> HTTPException:
    return HTTPException(
        status_code=413,
        detail=f"{label} image exceeds maximum upload size of {settings.max_upload_mb}MB.",
    )


def _image_too_large(label: str, error: ImageTooLargeError) -> HTTPException:
    return HTTPException(
        status_code=413,
        detail=f"{label} image is too large to process. {error}",
    )


async def _read_upload(upload: UploadFile, label: str) -> bytes:
    """Reads an uploaded image without holding more than the per-image limit in memory."""
    limit = _upload_limit_bytes()
    data = await upload.read(limit + 1)
    if len(data) > limit:
        raise _upload_too_large(label)
    return data


def _require_account_id(user: AuthenticatedUser) -> None:
    """Account quota and history live in UUID-keyed tables. A signed-in credential
    without a UUID account id (local development tokens and keys) must never reach
    them, so it cannot scan while a database is configured."""
    if not is_db_configured():
        return
    try:
        uuid.UUID(str(user.user_id))
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This credential is not linked to a CoinScan account and cannot be used for scanning.",
        )


@router.get("/guest/quota")
async def guest_quota_status(
    request: Request,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """Today's guest scan allowance for this device/network (read-only)."""
    if current_user.is_authenticated:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Signed-in users have an account quota: use /v1/account/quota.",
        )
    return await guest_allowance.status(request)


@router.post("/recognition", response_model=RecognitionResponse)
async def recognize_coin_multipart(
    request: Request,
    front_image: UploadFile = File(...),
    reverse_image: Optional[UploadFile] = File(None),
    edge_image: Optional[UploadFile] = File(None),
    preferred_currency: str = Form("USD"),
    locale: str = Form("en-US"),
    detected_year_hint: Optional[int] = Form(None),
    detected_text_hints: Optional[str] = Form(None),
    current_user: AuthenticatedUser = Depends(get_current_user),
) -> RecognitionResponse:
    """
    Primary recognition endpoint accepting multipart/form-data multi-sided coin captures.
    Server-authoritative authentication resolves user identity, tier, and enforces daily scan quotas.
    """
    is_guest = not current_user.is_authenticated
    rate_limiter.check_rate_limit(
        get_client_ip(request),
        user_id=None if is_guest else current_user.user_id,
        tier=current_user.tier,
    )

    # Refuse oversized uploads before any quota is reserved or bytes are read.
    for label, upload in (("Front", front_image), ("Reverse", reverse_image), ("Edge", edge_image)):
        if upload is not None and upload.size is not None and upload.size > _upload_limit_bytes():
            raise _upload_too_large(label)

    # 1. Pre-flight: reserve one scan before any paid provider call.
    #    Guests use the separate guest allowance (no user rows, no UUIDs);
    #    signed-in users use the account quota.
    if is_guest:
        reservation = await guest_allowance.reserve(request)
    else:
        _require_account_id(current_user)
        reservation = await quota_engine.reserve_slot(
            identifier=current_user.user_id,
            tier=current_user.tier,
        )

    try:
        start_time = time.time()

        # 1. Read and validate front image (any error below releases the reservation)
        front_bytes = await _read_upload(front_image, "Front")

        # 2. Inspect front image quality (oversized images are refused before decoding)
        try:
            front_quality, front_pil = inspect_image_quality(
                front_bytes,
                min_dimension=settings.min_image_dimension,
                max_dimension=settings.max_image_dimension,
                max_pixels=settings.max_image_pixels,
            )
        except ImageTooLargeError as e:
            raise _image_too_large("Front", e) from None

        if not front_quality.isAcceptable or front_pil is None:
            await reservation.release()
            return RecognitionResponse(
                status=RecognitionStatus.INSUFFICIENT_QUALITY,
                message="The front image quality is insufficient for reliable numismatic identification.",
                candidates=[],
                qualityReport=front_quality,
                processingMetadata={"latency_ms": int((time.time() - start_time) * 1000)},
                warnings=front_quality.warnings,
            )

        # 3. Read and validate optional reverse image
        reverse_pil = None
        reverse_b64 = None
        if reverse_image:
            reverse_bytes = await _read_upload(reverse_image, "Reverse")
            if reverse_bytes:
                try:
                    rev_quality, rev_pil = inspect_image_quality(
                        reverse_bytes,
                        min_dimension=settings.min_image_dimension,
                        max_dimension=settings.max_image_dimension,
                        max_pixels=settings.max_image_pixels,
                    )
                except ImageTooLargeError as e:
                    raise _image_too_large("Reverse", e) from None
                if rev_pil:
                    reverse_pil = rev_pil
                    _, reverse_b64 = normalize_image_for_analysis(reverse_pil)

        # 4. Read and validate optional edge image
        edge_b64 = None
        if edge_image:
            edge_bytes = await _read_upload(edge_image, "Edge")
            if edge_bytes:
                try:
                    _, edge_pil = inspect_image_quality(
                        edge_bytes,
                        min_dimension=60,
                        max_dimension=settings.max_image_dimension,
                        max_pixels=settings.max_image_pixels,
                    )
                except ImageTooLargeError as e:
                    raise _image_too_large("Edge", e) from None
                if edge_pil:
                    _, edge_b64 = normalize_image_for_analysis(edge_pil)

        # 5. Normalize front image for vision analysis
        _, front_b64 = normalize_image_for_analysis(front_pil)

        # 6. Parse client hints
        hints_list = []
        if detected_text_hints:
            hints_list = [h.strip() for h in detected_text_hints.split(",") if h.strip()]

        # 7. Execute Vision AI Extraction
        try:
            vision_provider = get_vision_provider()
        except HTTPException:
            await reservation.release()
            raise
        try:
            vision_obs = await vision_provider.analyze_coin_images(
                front_b64=front_b64,
                reverse_b64=reverse_b64,
                edge_b64=edge_b64,
                detected_text_hints=hints_list if hints_list else None,
            )
        except Exception as e:
            await reservation.release()
            # Provider errors can contain request URLs or other sensitive details:
            # log server-side only, return a generic message to the client.
            request_id = getattr(request.state, "request_id", None)
            if isinstance(e, VisionProviderError):
                logger.error(f"request_id={request_id} vision provider failure: {e}")
            else:
                logger.error(
                    f"request_id={request_id} unexpected vision provider failure: {type(e).__name__}"
                )
            return RecognitionResponse(
                status=RecognitionStatus.ERROR,
                message="The coin analysis service is temporarily unavailable. Your scan was not counted.",
                candidates=[],
                processingMetadata={"latency_ms": int((time.time() - start_time) * 1000)},
                warnings=["Please retry your scan in a moment."],
            )

        # 8. Extract OCR Signals
        all_tokens = list(vision_obs.visible_inscriptions) + hints_list
        ocr_signals = extract_ocr_signals(all_tokens)

        # 9. Query Numismatic Catalogue (Numista)
        query_parts = []
        if vision_obs.country:
            query_parts.append(vision_obs.country)
        if vision_obs.denomination:
            query_parts.append(vision_obs.denomination)
        if vision_obs.km_number_guess:
            query_parts.append(vision_obs.km_number_guess)

        catalog_query = " ".join(query_parts) if query_parts else (vision_obs.denomination or "coin")
        try:
            catalog_types = await numista_client.search_types(catalog_query, count=4)
        except CatalogueUnavailableError as e:
            # Never substitute invented catalogue data: report the outage honestly
            # and do not charge the user's quota.
            await reservation.release()
            logger.warning(
                f"request_id={getattr(request.state, 'request_id', None)} catalogue unavailable: {e}"
            )
            return RecognitionResponse(
                status=RecognitionStatus.UNAVAILABLE,
                message="The coin catalogue is temporarily unavailable, so this coin could not be verified. Your scan was not counted.",
                candidates=[],
                qualityReport=front_quality,
                processingMetadata={
                    "latency_ms": int((time.time() - start_time) * 1000),
                    "catalogue_source": "unavailable",
                },
                warnings=["Please try again in a few minutes."],
            )

        if not catalog_types and not vision_obs.country:
            await reservation.release()
            return RecognitionResponse(
                status=RecognitionStatus.UNKNOWN,
                message="We could not confidently identify this coin. Try scanning with better lighting and a clear view of both sides.",
                candidates=[],
                qualityReport=front_quality,
                processingMetadata={"latency_ms": int((time.time() - start_time) * 1000)},
                warnings=["No matching numismatic catalogue records found."],
            )

        # 10. Synthesize Candidates & Multi-Signal Evidence
        ranked_candidates = []
        for i, cat_type in enumerate(catalog_types[:3], start=1):
            candidate = build_candidate_from_evidence(
                vision=vision_obs,
                ocr=ocr_signals,
                catalog_match=cat_type,
                rank=i,
                reverse_captured=bool(reverse_b64),
            )
            ranked_candidates.append(candidate)

        if not ranked_candidates:
            await reservation.release()
            return RecognitionResponse(
                status=RecognitionStatus.UNKNOWN,
                message="We could not confidently match this coin against verified catalogue records.",
                candidates=[],
                qualityReport=front_quality,
                processingMetadata={"latency_ms": int((time.time() - start_time) * 1000)},
            )

        # Determine overall status from primary candidate
        primary = ranked_candidates[0]
        # Status follows the corroboration-gated confidence level (see evidence_engine):
        # only HIGH (>= 2 catalogue cross-checks, both sides, no contradiction) is "identified".
        overall_status = RecognitionStatus.LOW_CONFIDENCE
        if primary.confidence and vision_obs.obverse_reverse_consistent:
            if primary.confidence.level == ConfidenceLevel.HIGH:
                overall_status = RecognitionStatus.IDENTIFIED
            elif primary.confidence.level == ConfidenceLevel.MEDIUM:
                overall_status = RecognitionStatus.CANDIDATE

        catalogue_source = catalog_types[0].source if catalog_types else SOURCE_NUMISTA
        warnings = []

        # 11. Calculate Valuation & FX. Values are only converted with a real rate;
        # otherwise they stay in USD instead of relabelling USD amounts.
        valuation_currency = (preferred_currency or "USD").strip().upper()
        fx_rate = await fx_service.get_rate(valuation_currency)
        if fx_rate is None:
            warnings.append(
                f"An exchange rate for {valuation_currency} is not available right now; values are shown in USD."
            )
            valuation_currency = "USD"
            fx_rate = 1.0
        valuation_result = await valuation_engine.calculate_valuation(
            identity=primary.identity,
            currency_code=valuation_currency,
            fx_rate_to_usd=fx_rate,
            # Melt value may only use a composition that came from the catalogue record,
            # never one the vision model guessed from the photo.
            composition_verified=bool(catalog_types and catalog_types[0].composition),
        )

        if catalogue_source == SOURCE_OFFLINE_FIXTURE:
            warnings.append("DEVELOPMENT ONLY: catalogue data came from the offline test fixture, not Numista.")
        if not reverse_b64:
            warnings.append("Reverse side was not captured; scanning the reverse improves identification certainty.")
        if not vision_obs.obverse_reverse_consistent:
            warnings.append("Warning: Front and reverse design elements appear inconsistent with standard single-issue dies.")

        latency_ms = int((time.time() - start_time) * 1000)

        # Atomically commit reserved quota upon successful analysis completion
        remaining_scans = await reservation.commit()

        # Only signed-in users have server-side scan history. Guest results are
        # returned to the device and nothing about them is stored.
        if current_user.is_authenticated:
            identity = primary.identity if primary else None
            coin_title = (
                f"{identity.year or ''} {identity.country} {identity.denomination}".strip()
                if identity else "Unidentified Coin"
            )
            try:
                await account_store.add_scan_async(
                    user_id=current_user.user_id,
                    scan={
                        "id": str(uuid.uuid4()),
                        "user_id": current_user.user_id,
                        "scanned_at": time.time(),
                        "coin_name": coin_title,
                        "country": identity.country if identity else None,
                        "denomination": identity.denomination if identity else None,
                        "year": str(identity.year) if identity and identity.year else None,
                        "mint_mark": identity.mint if identity else None,
                        "confidence_score": primary.confidence.overallScore if primary and primary.confidence else None,
                        "numista_id": identity.numistaId if identity else None,
                        "status_label": overall_status.value,
                    },
                )
            except Exception as e:
                # History is a convenience record; never fail a completed scan over it.
                logger.error(f"Could not save scan history: {type(e).__name__}")

        return RecognitionResponse(
            status=overall_status,
            message=primary.confidence.explanation if primary.confidence else "Coin analyzed successfully.",
            candidates=ranked_candidates,
            qualityReport=front_quality,
            valuation=valuation_result,
            processingMetadata={
                "latency_ms": latency_ms,
                "provider": settings.vision_provider,
                "catalogue_source": catalogue_source,
                "numista_attributed": catalogue_source == SOURCE_NUMISTA,
                "guest": is_guest,
                **({"guest_scans_remaining": remaining_scans} if is_guest else {}),
            },
            warnings=warnings,
        )
    except BaseException:
        # Any failure after the reservation gives the slot back, so an error
        # never consumes a guest's allowance or an account's daily quota.
        # (release() is a no-op once the scan has been committed.)
        await reservation.release()
        raise
