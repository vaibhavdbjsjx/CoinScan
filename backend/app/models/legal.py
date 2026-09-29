"""
Pydantic schemas for versioned legal consent (Terms & Conditions and Privacy Policy).
"""

from typing import Optional
from pydantic import BaseModel, Field


class TermsConsentRequest(BaseModel):
    terms_version: str = Field(..., min_length=1, max_length=20, description="Accepted Terms version, e.g. '1.0.0'")
    privacy_version: str = Field(..., min_length=1, max_length=20, description="Accepted Privacy Policy version, e.g. '1.0.0'")
    accepted_at: Optional[float] = None


class TermsConsentResponse(BaseModel):
    status: str
    user_id: str
    terms_version: str
    privacy_version: str
    is_current: bool
    accepted_at: float
    required_terms_version: str
    required_privacy_version: str
