"""
P0 regression tests: catalogue data is never invented, and evidence states
honestly whether a fact came from the catalogue or from AI reading the photo.
"""

import io

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from backend.app.api import recognition as recognition_module
from backend.app.api.account import account_store
from backend.app.main import app
from backend.app.models.domain import RecognitionEvidenceType
from backend.app.security.quota_service import quota_engine
from backend.app.services.numista.client import (
    NumistaClient,
    NumistaTypeDetail,
    SOURCE_OFFLINE_FIXTURE,
)
from backend.app.services.recognition.evidence_engine import build_candidate_from_evidence
from backend.app.services.recognition.ocr_service import ExtractedOcrSignals
from backend.app.services.recognition.vision_provider import RawVisionObservation

client = TestClient(app)


def _jpeg_bytes(size: int = 400) -> bytes:
    img = Image.new("RGB", (size, size), color=(120, 110, 90))
    for x in range(0, size, 8):
        for y in range(size):
            img.putpixel((x, y), (250, 250, 250))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=92)
    return buf.getvalue()


class _FixtureMorganClient(NumistaClient):
    """Answers every query with the labelled offline fixture's Morgan Dollar record."""

    def __init__(self):
        super().__init__(offline_fixture=True)

    async def search_types(self, query, category="coin", count=5):
        return self._get_fallback_catalog("morgan")


def test_recognition_reports_unavailable_when_catalogue_not_configured(monkeypatch):
    monkeypatch.setattr(recognition_module, "numista_client", NumistaClient(api_key=None))
    quota_engine.reset_usage_for_test()

    resp = client.post("/v1/recognition", files={"front_image": ("f.jpg", _jpeg_bytes(), "image/jpeg")})

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "unavailable"
    assert body["candidates"] == []
    assert body.get("valuation") is None
    assert body["processingMetadata"]["catalogue_source"] == "unavailable"
    # Nothing that looks like a fixture/fake coin leaks through
    assert "Morgan" not in resp.text and "George V" not in resp.text
    # The user is not charged for an outage
    assert quota_engine.get_current_usage("anon_ip_testclient") == 0


def test_fixture_results_are_labelled_and_not_attributed_to_numista(monkeypatch):
    monkeypatch.setattr(recognition_module, "numista_client", _FixtureMorganClient())

    resp = client.post("/v1/recognition", files={"front_image": ("f.jpg", _jpeg_bytes(), "image/jpeg")})
    body = resp.json()

    assert body["processingMetadata"]["catalogue_source"] == SOURCE_OFFLINE_FIXTURE
    assert body["processingMetadata"]["numista_attributed"] is False
    assert any("offline test fixture" in w.lower() for w in body["warnings"])
    sources = [e.get("source") or "" for e in body["candidates"][0]["evidence"]]
    assert not any("Numista" in s and "not Numista" not in s for s in sources)


def test_front_only_scan_never_claims_two_sided_agreement(monkeypatch):
    monkeypatch.setattr(recognition_module, "numista_client", _FixtureMorganClient())

    resp = client.post("/v1/recognition", files={"front_image": ("f.jpg", _jpeg_bytes(), "image/jpeg")})
    evidence = resp.json()["candidates"][0]["evidence"]
    labels = [e["label"] for e in evidence]

    assert "Two-Sided Agreement" not in labels
    assert "Reverse Not Captured" in labels
    assert "both sides" not in resp.json()["message"]


def test_two_sided_scan_still_reports_agreement(monkeypatch):
    monkeypatch.setattr(recognition_module, "numista_client", _FixtureMorganClient())

    resp = client.post(
        "/v1/recognition",
        files={
            "front_image": ("f.jpg", _jpeg_bytes(), "image/jpeg"),
            "reverse_image": ("r.jpg", _jpeg_bytes(), "image/jpeg"),
        },
    )
    labels = [e["label"] for e in resp.json()["candidates"][0]["evidence"]]
    assert "Two-Sided Agreement" in labels


def test_signed_in_scan_succeeds_and_saves_history(monkeypatch):
    """Regression: saving history for signed-in users crashed with
    AttributeError ('CoinIdentity' has no attribute 'mintMark') after quota was charged."""
    monkeypatch.setattr(recognition_module, "numista_client", _FixtureMorganClient())
    account_store.reset_for_test()
    safe_client = TestClient(app, raise_server_exceptions=False)

    resp = safe_client.post(
        "/v1/recognition",
        files={"front_image": ("f.jpg", _jpeg_bytes(), "image/jpeg")},
        headers={"Authorization": "Bearer usr_history_regression"},
    )

    assert resp.status_code == 200, resp.text
    scans = account_store.get_scans("usr_history_regression")
    assert len(scans) == 1
    assert scans[0]["mint_mark"] == "CC"  # mock vision reads "CC"


def test_year_without_catalogue_range_is_reported_as_unverified():
    vision = RawVisionObservation(country="France", year=1999, visual_similarity_score=0.8)
    catalog = NumistaTypeDetail(id=7, title="1 Franc", country="France")  # no min/max year

    candidate = build_candidate_from_evidence(vision, ExtractedOcrSignals(), catalog)
    year_ev = [e for e in candidate.evidence if e.type == RecognitionEvidenceType.YEAR]

    assert len(year_ev) == 1
    assert "unverified" in year_ev[0].label.lower()
    assert "Numista" not in (year_ev[0].source or "")
    # No verification credit for an unverifiable year
    assert candidate.confidence.ocrScore == 0.5


def test_year_within_catalogue_range_names_both_sources():
    vision = RawVisionObservation(country="France", year=1999)
    catalog = NumistaTypeDetail(id=7, title="1 Franc", country="France", min_year=1960, max_year=2001)

    candidate = build_candidate_from_evidence(vision, ExtractedOcrSignals(), catalog)
    year_ev = [e for e in candidate.evidence if e.type == RecognitionEvidenceType.YEAR][0]

    assert "Vision AI" in year_ev.source
    assert "Numista catalogue" in year_ev.source
    assert candidate.confidence.ocrScore == 0.92


def test_visual_evidence_does_not_claim_catalogue_image_match():
    vision = RawVisionObservation(country="France")
    catalog = NumistaTypeDetail(id=7, title="1 Franc", country="France", min_year=1960, max_year=2001)

    candidate = build_candidate_from_evidence(vision, ExtractedOcrSignals(), catalog)
    visual = [e for e in candidate.evidence if e.type == RecognitionEvidenceType.VISUAL_SIMILARITY][0]

    assert "align with" not in visual.detail
    assert "self-assessed" in visual.source


def test_fixture_evidence_is_never_labelled_numista():
    vision = RawVisionObservation(country="United States", year=1882, mint_mark="CC")
    fixture_record = NumistaClient(offline_fixture=True)._get_fallback_catalog("morgan")[0]

    candidate = build_candidate_from_evidence(vision, ExtractedOcrSignals(), fixture_record)
    for ev in candidate.evidence:
        src = ev.source or ""
        assert not ("Numista" in src and "not Numista" not in src), src
