"""
Confidence integrity: identification confidence is capped by independent catalogue
corroboration, never reaches "identified" on the AI's reading alone, and never
claims to authenticate a coin.
"""

import io

from fastapi.testclient import TestClient
from PIL import Image

from backend.app.api import recognition as recognition_module
from backend.app.main import app
from backend.app.models.domain import ConfidenceLevel
from backend.app.services.numista.client import NumistaClient, NumistaIssue, NumistaTypeDetail
from backend.app.services.recognition.evidence_engine import build_candidate_from_evidence
from backend.app.services.recognition.ocr_service import ExtractedOcrSignals
from backend.app.services.recognition.vision_provider import (
    MockVisionProvider,
    RawVisionObservation,
)

client = TestClient(app)


def _catalog(**kw):
    base = dict(id=1, title="1 Dollar", country="United States", denomination="1 Dollar")
    base.update(kw)
    return NumistaTypeDetail(**base)


def test_ai_reading_alone_is_capped_at_low():
    """Previously scored 0.64 'Probable match' with zero corroboration."""
    vision = RawVisionObservation(country="France", visual_similarity_score=0.99)
    cand = build_candidate_from_evidence(vision, ExtractedOcrSignals(), _catalog(country="France"))
    assert cand.confidence.level == ConfidenceLevel.LOW
    assert cand.confidence.overallScore <= 0.59
    assert cand.confidence.corroboratingChecks == 0
    assert "no detail could be cross-checked" in cand.confidence.explanation


def test_single_corroboration_is_capped_at_medium():
    """Previously a year inside the catalogue range alone reached 0.76 => 'identified'."""
    vision = RawVisionObservation(country="France", year=1999, visual_similarity_score=0.99)
    cand = build_candidate_from_evidence(
        vision, ExtractedOcrSignals(), _catalog(country="France", min_year=1960, max_year=2001)
    )
    assert cand.confidence.corroboratingChecks == 1
    assert cand.confidence.level == ConfidenceLevel.MEDIUM
    assert cand.confidence.overallScore <= 0.84


def test_high_requires_two_checks_and_reverse():
    vision = RawVisionObservation(
        country="United States", year=1882, mint_mark="CC", visual_similarity_score=0.95
    )
    catalog = _catalog(min_year=1878, max_year=1921, issues=[NumistaIssue(year=1882, mint_mark="CC")])

    both_sides = build_candidate_from_evidence(vision, ExtractedOcrSignals(), catalog, reverse_captured=True)
    front_only = build_candidate_from_evidence(vision, ExtractedOcrSignals(), catalog, reverse_captured=False)

    assert both_sides.confidence.corroboratingChecks == 2
    assert both_sides.confidence.level == ConfidenceLevel.HIGH
    assert front_only.confidence.level == ConfidenceLevel.MEDIUM
    assert "Photograph the reverse" in front_only.confidence.explanation


def test_high_confidence_never_claims_authentication():
    vision = RawVisionObservation(country="United States", year=1882, mint_mark="CC", visual_similarity_score=0.95)
    catalog = _catalog(min_year=1878, max_year=1921, issues=[NumistaIssue(year=1882, mint_mark="CC")])
    cand = build_candidate_from_evidence(vision, ExtractedOcrSignals(), catalog)
    assert cand.confidence.level == ConfidenceLevel.HIGH
    assert "does not authenticate" in cand.confidence.explanation
    for ev in cand.evidence:
        assert "authentic" not in (ev.detail or "").lower()


def test_two_sided_agreement_is_labelled_as_model_judgement():
    vision = RawVisionObservation(country="France", obverse_reverse_consistent=True)
    cand = build_candidate_from_evidence(vision, ExtractedOcrSignals(), _catalog(country="France"))
    agreement = [e for e in cand.evidence if e.label == "Two-Sided Agreement"][0]
    assert "model" in agreement.source.lower()


class _StaticCatalogue(NumistaClient):
    def __init__(self, record):
        super().__init__(api_key="unused")
        self.record = record

    async def search_types(self, query, category="coin", count=5):
        return [self.record]


def _jpeg_bytes(size: int = 400) -> bytes:
    img = Image.new("RGB", (size, size), color=(120, 110, 90))
    for x in range(0, size, 8):
        for y in range(size):
            img.putpixel((x, y), (250, 250, 250))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=92)
    return buf.getvalue()


def test_api_status_is_not_identified_without_corroboration(monkeypatch):
    # Vision reads only a country and a very confident self-rating; nothing else to verify.
    monkeypatch.setattr(
        recognition_module,
        "get_vision_provider",
        lambda: MockVisionProvider(RawVisionObservation(country="France", visual_similarity_score=0.99)),
    )
    monkeypatch.setattr(recognition_module, "numista_client", _StaticCatalogue(_catalog(country="France")))

    resp = client.post("/v1/recognition", files={"front_image": ("f.jpg", _jpeg_bytes(), "image/jpeg")})
    body = resp.json()
    assert body["status"] == "lowConfidence"
    assert body["candidates"][0]["confidence"]["corroboratingChecks"] == 0
