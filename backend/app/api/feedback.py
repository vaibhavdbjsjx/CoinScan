"""
User Feedback and Bug Reporting API.

Accepts structured user feedback, app diagnostics, and issue reports.
Enforces category validation, rate limiting, and spam protection.
Never logs or persists raw user authentication secrets or tokens.
"""

import time
import logging
from enum import Enum
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, status, Request

from backend.app.config import settings
from backend.app.security.auth import get_current_user, AuthenticatedUser
from backend.app.db.session import is_db_configured, get_session_factory
from backend.app.db.models import Feedback as DBFeedback, User

logger = logging.getLogger("coinscan.feedback")
router = APIRouter(prefix="/v1/feedback", tags=["Feedback"])


class FeedbackCategory(str, Enum):
    RECOGNITION_INCORRECT = "recognition_incorrect"
    VALUATION_INCORRECT = "valuation_incorrect"
    CAMERA_PROBLEM = "camera_problem"
    GALLERY_PROBLEM = "gallery_problem"
    SUBSCRIPTION_PROBLEM = "subscription_problem"
    APP_CRASH = "app_crash"
    PERFORMANCE = "performance"
    FEATURE_REQUEST = "feature_request"
    OTHER = "other"


class FeedbackSubmission(BaseModel):
    category: FeedbackCategory
    title: str = Field(..., min_length=3, max_length=150)
    description: str = Field(..., min_length=5, max_length=2000)
    app_version: Optional[str] = "1.0.0"
    build_number: Optional[str] = "1"
    platform: Optional[str] = "ios"  # 'ios', 'android', 'web'
    os_version: Optional[str] = None
    device_model: Optional[str] = None
    request_id: Optional[str] = None  # Reference to failed scan if applicable


class FeedbackRecord(BaseModel):
    feedback_id: str
    user_id: str
    category: FeedbackCategory
    title: str
    description: str
    app_version: str
    platform: str
    created_at: float


class FeedbackStore:
    """In-memory & DB-backed feedback storage with sliding-window anti-spam rate limiting.

    In production: Backed by PostgreSQL / Supabase table `feedback`.
    In development: Uses in-memory structures when DATABASE_URL is not configured.
    """

    def __init__(self):
        self._records: List[FeedbackRecord] = []
        # user_id / ip -> list of timestamps
        self._submission_history: Dict[str, List[float]] = {}

    def _check_persistence_mode(self):
        """Fails closed in production if database persistence is not configured."""
        if settings.app_env == "production" and not is_db_configured():
            logger.critical("Persistence failure: DATABASE_URL is not configured in production.")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database persistence unconfigured in production.",
            )

    def submit_feedback(
        self,
        submission: FeedbackSubmission,
        user: AuthenticatedUser,
        client_ip: str,
    ) -> FeedbackRecord:
        self._check_persistence_mode()
        now = time.time()
        identifier = user.user_id if user.is_authenticated else f"ip_{client_ip}"

        # Rate limiting: Maximum 5 feedback submissions per 10 minutes
        history = self._submission_history.setdefault(identifier, [])
        self._submission_history[identifier] = [t for t in history if now - t < 600]

        if len(self._submission_history[identifier]) >= 5:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many feedback submissions. Please wait a few minutes before submitting another report.",
            )

        feedback_id = f"fb_{int(now)}_{len(self._records) + 1}"
        record = FeedbackRecord(
            feedback_id=feedback_id,
            user_id=user.user_id,
            category=submission.category,
            title=submission.title,
            description=submission.description,
            app_version=submission.app_version or "1.0.0",
            platform=submission.platform or "ios",
            created_at=now,
        )

        self._records.append(record)
        self._submission_history[identifier].append(now)

        logger.info(
            f"Feedback received: id={feedback_id} user={user.user_id} "
            f"category={submission.category.value} title='{submission.title[:30]}'"
        )
        return record

    async def submit_feedback_async(
        self,
        submission: FeedbackSubmission,
        user: AuthenticatedUser,
        client_ip: str,
    ) -> FeedbackRecord:
        self._check_persistence_mode()
        record = self.submit_feedback(submission, user, client_ip)

        if is_db_configured():
            factory = get_session_factory()
            if factory:
                async with factory() as session:
                    db_user_id = None
                    if user.is_authenticated:
                        db_user = await session.get(User, user.user_id)
                        if not db_user:
                            db_user = User(id=user.user_id, email=f"{user.user_id}@coinscan.app")
                            session.add(db_user)
                            await session.flush()
                        db_user_id = user.user_id

                    db_entry = DBFeedback(
                        user_id=db_user_id,
                        category=submission.category.value,
                        title=submission.title,
                        description=submission.description,
                        app_version=submission.app_version or "1.0.0",
                        platform=submission.platform or "ios",
                        request_id=submission.request_id,
                        client_ip=client_ip,
                    )
                    session.add(db_entry)
                    await session.commit()
        return record

    def list_user_feedback(self, user_id: str) -> List[FeedbackRecord]:
        return [r for r in self._records if r.user_id == user_id]

    def reset_for_test(self):
        self._records.clear()
        self._submission_history.clear()


feedback_store = FeedbackStore()


@router.post("", response_model=Dict[str, Any])
async def submit_feedback(
    submission: FeedbackSubmission,
    request: Request,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Submits a user feedback report or bug inquiry with device diagnostic context.
    """
    client_ip = request.client.host if request.client else "127.0.0.1"
    record = await feedback_store.submit_feedback_async(submission, current_user, client_ip)

    return {
        "status": "success",
        "message": "Thank you for your feedback! Our numismatic engineering team has received your report.",
        "feedback_id": record.feedback_id,
        "received_at": record.created_at,
    }

