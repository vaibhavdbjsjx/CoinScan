import io
from PIL import Image, ImageDraw
import pytest
from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.models.domain import RecognitionStatus

client = TestClient(app)


def create_sample_coin_image(width: int = 500, height: int = 500, label: str = "1882") -> bytes:
    img = Image.new("RGB", (width, height), color="#333333")
    draw = ImageDraw.Draw(img)
    draw.ellipse([40, 40, width - 40, height - 40], outline="gold", width=4)
    draw.text((width // 2 - 20, height // 2 - 10), label, fill="white")
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


def test_recognition_api_valid_multipart_request(monkeypatch):
    """Test valid multipart recognition request returns a well-formed response.

    Local development uses the mock vision provider; the catalogue is the
    explicitly-enabled, labelled offline fixture (never an implicit fallback).
    """
    from backend.app.api import recognition as recognition_module
    from backend.app.services.numista.client import NumistaClient

    monkeypatch.setattr(recognition_module, "numista_client", NumistaClient(offline_fixture=True))
    front_bytes = create_sample_coin_image(500, 500, "1882")
    reverse_bytes = create_sample_coin_image(500, 500, "ONE DOLLAR")

    files = {
        "front_image": ("front.jpg", front_bytes, "image/jpeg"),
        "reverse_image": ("reverse.jpg", reverse_bytes, "image/jpeg"),
    }
    data = {
        "preferred_currency": "USD",
        "locale": "en-US",
        "detected_text_hints": "1882, LIBERTY",
    }

    response = client.post("/v1/recognition", files=files, data=data)
    assert response.status_code == 200
    res_json = response.json()

    assert "status" in res_json
    valid_statuses = [
        RecognitionStatus.IDENTIFIED.value,
        RecognitionStatus.CANDIDATE.value,
        RecognitionStatus.LOW_CONFIDENCE.value,
        RecognitionStatus.UNKNOWN.value,
    ]
    assert res_json["status"] in valid_statuses, (
        f"Unexpected status '{res_json['status']}' — expected one of {valid_statuses}"
    )

    # Response shape must always include these keys
    assert "candidates" in res_json
    assert isinstance(res_json["candidates"], list)
    assert "qualityReport" in res_json
    assert "processingMetadata" in res_json

    # If identified/candidate, must have at least one candidate
    if res_json["status"] in [RecognitionStatus.IDENTIFIED.value, RecognitionStatus.CANDIDATE.value]:
        assert len(res_json["candidates"]) >= 1
        assert "valuation" in res_json


def test_recognition_api_low_resolution_image():
    low_res_bytes = create_sample_coin_image(100, 100, "TINY")

    files = {
        "front_image": ("front.jpg", low_res_bytes, "image/jpeg"),
    }

    response = client.post("/v1/recognition", files=files)
    assert response.status_code == 200
    res_json = response.json()

    assert res_json["status"] == RecognitionStatus.INSUFFICIENT_QUALITY.value
    assert len(res_json["candidates"]) == 0
    assert res_json["qualityReport"]["isAcceptable"] is False


def test_recognition_api_staging_rejects_missing_credentials():
    from backend.app.config import settings

    original_env = settings.app_env
    original_key = settings.gemini_api_key
    try:
        settings.app_env = "staging"
        settings.gemini_api_key = None

        front_bytes = create_sample_coin_image(500, 500, "1882")
        files = {"front_image": ("front.jpg", front_bytes, "image/jpeg")}

        response = client.post("/v1/recognition", files=files)
        assert response.status_code == 503
        assert "not configured on this staging service" in response.json()["detail"]
    finally:
        settings.app_env = original_env
        settings.gemini_api_key = original_key
