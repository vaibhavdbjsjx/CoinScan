"""
Response models for the CoinScan backend API.
Serializes precisely to match Flutter's RecognitionResult.fromJson(...) schema.
"""

from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field, ConfigDict
from backend.app.models.domain import (
    RecognitionStatus,
    RecognitionCandidate,
    ImageQualityReport,
    ValuationResult,
)


class HealthResponse(BaseModel):
    status: str = "ok"
    service: str = "coinscan-backend"
    version: str = "1.0.0"
    environment: str = "development"
    providers: Dict[str, str] = Field(default_factory=dict)
    timestamp: str


class RecognitionResponse(BaseModel):
    status: RecognitionStatus
    message: str
    candidates: List[RecognitionCandidate] = Field(default_factory=list)
    qualityReport: Optional[ImageQualityReport] = Field(default=None, serialization_alias="qualityReport")
    valuation: Optional[ValuationResult] = None
    processingMetadata: Dict[str, Any] = Field(default_factory=dict, serialization_alias="processingMetadata")
    warnings: List[str] = Field(default_factory=list)

    model_config = ConfigDict(populate_by_name=True)
