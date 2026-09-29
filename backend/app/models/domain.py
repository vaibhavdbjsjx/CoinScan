"""
Domain models for CoinScan recognition, evidence, and valuation.
Aligned with client-side Flutter models in lib/core/recognition/.
"""

from enum import Enum
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field


class CaptureSide(str, Enum):
    FRONT = "front"
    REVERSE = "reverse"
    EDGE = "edge"


class CaptureSource(str, Enum):
    CAMERA = "camera"
    GALLERY = "gallery"


class RecognitionStatus(str, Enum):
    IDENTIFIED = "identified"
    CANDIDATE = "candidate"
    LOW_CONFIDENCE = "lowConfidence"
    INSUFFICIENT_QUALITY = "insufficientQuality"
    UNKNOWN = "unknown"
    UNAVAILABLE = "unavailable"
    ERROR = "error"


class ConfidenceLevel(str, Enum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INDETERMINATE = "indeterminate"


class RecognitionEvidenceType(str, Enum):
    VISUAL_SIMILARITY = "visualSimilarity"
    INSCRIPTION = "inscription"
    YEAR = "year"
    DENOMINATION = "denomination"
    COUNTRY = "country"
    MINT_MARK = "mintMark"
    OBVERSE_REVERSE_AGREEMENT = "obverseReverseAgreement"
    EDGE = "edge"
    GEOMETRY = "geometry"
    WEIGHT = "weight"
    DIAMETER = "diameter"
    COMPOSITION = "composition"


class SignalStrength(str, Enum):
    STRONG = "strong"
    MODERATE = "moderate"
    WEAK = "weak"
    INCONSISTENT = "inconsistent"


class ImageQualityIssue(str, Enum):
    TOO_BLURRY = "tooBlurry"
    TOO_DARK = "tooDark"
    EXCESSIVE_GLARE = "excessiveGlare"
    RESOLUTION_TOO_LOW = "resolutionTooLow"
    COIN_NOT_CENTERED = "coinNotCentered"
    COIN_PARTIALLY_CUT_OFF = "coinPartiallyCutOff"
    NON_COIN_DETECTED = "nonCoinDetected"


class ValuationType(str, Enum):
    FACE_VALUE = "faceValue"
    METAL_VALUE = "metalValue"
    COLLECTOR_VALUE = "collectorValue"
    MARKET_ESTIMATE = "marketEstimate"


class ValuationStatus(str, Enum):
    AVAILABLE = "available"
    PARTIAL = "partial"
    UNAVAILABLE = "unavailable"
    INSUFFICIENT_DATA = "insufficientData"


class CoinGradeTier(str, Enum):
    RAW_UNGRADED = "rawUngraded"
    GOOD = "good"
    VERY_GOOD = "veryGood"
    FINE = "fine"
    VERY_FINE = "veryFine"
    EXTREMELY_FINE = "extremelyFine"
    ABOUT_UNCIRCULATED = "aboutUncirculated"
    MINT_STATE = "mintState"
    PROOF = "proof"


class ImageQualityReport(BaseModel):
    isAcceptable: bool = Field(default=True, serialization_alias="isAcceptable")
    overallScore: float = Field(default=1.0, ge=0.0, le=1.0, serialization_alias="overallScore")
    issues: List[ImageQualityIssue] = Field(default_factory=list)
    warnings: List[str] = Field(default_factory=list)
    recommendedActions: List[str] = Field(default_factory=list, serialization_alias="recommendedActions")


class RecognitionEvidence(BaseModel):
    type: RecognitionEvidenceType
    label: str
    detail: str
    source: Optional[str] = None
    strength: SignalStrength = SignalStrength.STRONG
    score: Optional[float] = Field(default=None, ge=0.0, le=1.0)


class CoinIdentity(BaseModel):
    country: str
    denomination: str
    currency: Optional[str] = None
    year: Optional[int] = None
    mint: Optional[str] = None
    composition: Optional[str] = None
    weightG: Optional[float] = Field(default=None, serialization_alias="weightG")
    diameterMm: Optional[float] = Field(default=None, serialization_alias="diameterMm")
    thicknessMm: Optional[float] = Field(default=None, serialization_alias="thicknessMm")
    edgeType: Optional[str] = Field(default=None, serialization_alias="edgeType")
    kmNumber: Optional[str] = Field(default=None, serialization_alias="kmNumber")
    numistaId: Optional[int] = Field(default=None, serialization_alias="numistaId")
    pcgsNumber: Optional[str] = Field(default=None, serialization_alias="pcgsNumber")
    historicalPeriod: Optional[str] = Field(default=None, serialization_alias="historicalPeriod")
    designer: Optional[str] = None


class RecognitionConfidence(BaseModel):
    level: ConfidenceLevel
    overallScore: float = Field(default=0.0, ge=0.0, le=1.0, serialization_alias="overallScore")
    visualScore: float = Field(default=0.0, ge=0.0, le=1.0, serialization_alias="visualScore")
    ocrScore: float = Field(default=0.0, ge=0.0, le=1.0, serialization_alias="ocrScore")
    metadataScore: float = Field(default=0.0, ge=0.0, le=1.0, serialization_alias="metadataScore")
    explanation: str


class RecognitionCandidate(BaseModel):
    coinId: str = Field(serialization_alias="coinId")
    identity: CoinIdentity
    providerName: str = Field(default="CoinScan Recognition", serialization_alias="providerName")
    confidence: Optional[RecognitionConfidence] = None
    evidence: List[RecognitionEvidence] = Field(default_factory=list)
    rank: int = 1


class MarketComparable(BaseModel):
    source: str
    title: str
    currencyCode: str = Field(default="USD", serialization_alias="currencyCode")
    price: float
    observedAt: str = Field(serialization_alias="observedAt")
    url: Optional[str] = None
    condition: Optional[str] = None
    gradeTier: Optional[CoinGradeTier] = Field(default=None, serialization_alias="gradeTier")


class ValuationEstimate(BaseModel):
    type: ValuationType
    currencyCode: str = Field(default="USD", serialization_alias="currencyCode")
    low: Optional[float] = None
    high: Optional[float] = None
    mid: Optional[float] = None
    valuedAt: str = Field(serialization_alias="valuedAt")
    source: str
    caveat: str
    comparables: List[MarketComparable] = Field(default_factory=list)
    confidenceScore: float = Field(default=1.0, ge=0.0, le=1.0, serialization_alias="confidenceScore")


class ValuationResult(BaseModel):
    status: ValuationStatus = ValuationStatus.UNAVAILABLE
    currencyCode: str = Field(default="USD", serialization_alias="currencyCode")
    estimates: List[ValuationEstimate] = Field(default_factory=list)
    valuationNotes: Optional[str] = Field(default=None, serialization_alias="valuationNotes")
    updatedAt: str = Field(serialization_alias="updatedAt")
