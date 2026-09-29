import io
from PIL import Image, ImageDraw
import pytest
from backend.app.preprocessing.image_quality import inspect_image_quality
from backend.app.preprocessing.image_normalization import normalize_image_for_analysis
from backend.app.models.domain import ImageQualityIssue


def create_test_image(width: int = 400, height: int = 400, color: str = "gray") -> bytes:
    img = Image.new("RGB", (width, height), color=color)
    draw = ImageDraw.Draw(img)
    # Draw simulated coin circle with details
    draw.ellipse([50, 50, width - 50, height - 50], outline="gold", width=4)
    draw.text((width // 2 - 20, height // 2 - 10), "1882", fill="white")
    draw.text((width // 2 - 30, height // 2 + 10), "LIBERTY", fill="white")
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


def test_empty_image_inspection():
    report, img = inspect_image_quality(b"")
    assert report.isAcceptable is False
    assert report.overallScore == 0.0
    assert ImageQualityIssue.RESOLUTION_TOO_LOW in report.issues
    assert img is None


def test_corrupted_image_inspection():
    report, img = inspect_image_quality(b"random_corrupted_bytes_12345")
    assert report.isAcceptable is False
    assert report.overallScore == 0.0
    assert img is None


def test_low_resolution_image():
    low_res_bytes = create_test_image(width=120, height=120)
    report, _ = inspect_image_quality(low_res_bytes, min_dimension=240)
    assert report.isAcceptable is False
    assert ImageQualityIssue.RESOLUTION_TOO_LOW in report.issues


def test_valid_image_quality_pass():
    valid_bytes = create_test_image(width=600, height=600)
    report, img = inspect_image_quality(valid_bytes, min_dimension=240)
    assert report.isAcceptable is True
    assert report.overallScore >= 0.5
    assert img is not None
    assert img.size == (600, 600)


def test_image_normalization_downscaling():
    large_img = Image.new("RGB", (3000, 2000), color="blue")
    jpeg_bytes, b64_str = normalize_image_for_analysis(large_img, max_dimension=1536)
    assert len(jpeg_bytes) > 0
    assert len(b64_str) > 0

    decoded = Image.open(io.BytesIO(jpeg_bytes))
    assert max(decoded.size) <= 1536
