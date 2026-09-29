import pytest
from backend.app.services.recognition.evidence_engine import build_candidate_from_evidence
from backend.app.services.recognition.vision_provider import RawVisionObservation
from backend.app.services.recognition.ocr_service import ExtractedOcrSignals
from backend.app.services.numista.client import NumistaTypeDetail, NumistaIssue
from backend.app.models.domain import ConfidenceLevel, RecognitionEvidenceType


def test_strong_evidence_candidate_scoring():
    vision = RawVisionObservation(
        country="United States",
        denomination="1 Dollar",
        year=1882,
        mint_mark="CC",
        visual_similarity_score=0.95,
        confidence_reasoning="Matches Carson City Liberty head die strike.",
        obverse_reverse_consistent=True,
    )
    ocr = ExtractedOcrSignals(
        detected_years=[1882],
        detected_denominations=["ONE DOLLAR"],
        detected_country_tokens=["UNITED STATES"],
    )
    catalog = NumistaTypeDetail(
        id=1492,
        title="1 Dollar 'Morgan Dollar'",
        country="United States",
        denomination="1 Dollar",
        currency="USD",
        min_year=1878,
        max_year=1921,
        composition="90% Silver, 10% Copper",
        issues=[NumistaIssue(year=1882, mint_mark="CC", mintage=1133000)],
    )

    candidate = build_candidate_from_evidence(vision, ocr, catalog, rank=1)
    assert candidate.coinId == "numista_1492"
    assert candidate.rank == 1
    assert candidate.confidence is not None
    assert candidate.confidence.level == ConfidenceLevel.HIGH
    assert candidate.confidence.overallScore >= 0.85
    assert len(candidate.evidence) >= 3


def test_obverse_reverse_contradiction_penalty():
    vision = RawVisionObservation(
        country="United States",
        denomination="1 Dollar",
        year=1882,
        visual_similarity_score=0.85,
        obverse_reverse_consistent=False,
        contradiction_notes="Reverse depicts an Indian Head cent shield rather than an eagle.",
    )
    ocr = ExtractedOcrSignals()
    catalog = NumistaTypeDetail(
        id=1492,
        title="1 Dollar 'Morgan Dollar'",
        country="United States",
        min_year=1878,
        max_year=1921,
    )

    candidate = build_candidate_from_evidence(vision, ocr, catalog, rank=1)
    assert candidate.confidence is not None
    assert candidate.confidence.overallScore < 0.60
    # Confirms contradiction evidence was attached
    contradictions = [e for e in candidate.evidence if e.type == RecognitionEvidenceType.OBVERSE_REVERSE_AGREEMENT]
    assert len(contradictions) == 1
    assert contradictions[0].score == 0.10
