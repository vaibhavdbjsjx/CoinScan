"""
Upload and resource protection for the recognition endpoint.

- Normal app-sized photos (JPEG, at most 1920 px) are processed and charged once.
- Oversized uploads are refused (413) before any image is decoded and are
  never charged; so are images whose header declares too many pixels
  (decompression bombs), however small the file.
- Malformed, HEIC and other unsupported images get a clean "insufficient
  quality" answer without raw decoder errors, and are never charged.
- Request bodies are capped while they are received, with or without a
  Content-Length header.
"""

import asyncio
import io
import json
import os
import struct
import time
import zlib

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from backend.app.api import recognition as recognition_module
from backend.app.config import settings
from backend.app.main import app
from backend.app.preprocessing.image_quality import ImageTooLargeError, probe_image
from backend.app.security.guest_quota import guest_allowance
from backend.app.security.request_limits import RequestSizeLimitMiddleware
from backend.app.services.numista.client import NumistaClient, NumistaTypeDetail


class _Catalogue(NumistaClient):
    def __init__(self):
        super().__init__(api_key="unused")

    async def search_types(self, query, category="coin", count=5):
        return [NumistaTypeDetail(id=1492, title="1 Dollar", country="United States",
                                  denomination="1 Dollar", min_year=1878, max_year=1921)]


@pytest.fixture(autouse=True)
def _catalogue(monkeypatch):
    monkeypatch.setattr(recognition_module, "numista_client", _Catalogue())


def _jpeg(width=1920, height=1920, quality=88) -> bytes:
    """An app-sized photo with enough structure to pass the quality checks."""
    img = Image.new("RGB", (width, height), (120, 110, 90))
    for x in range(0, width, 16):
        img.paste((250, 250, 250), (x, 0, x + 3, height))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=quality)
    return buf.getvalue()


def _png_header_only(width: int, height: int) -> bytes:
    """A tiny PNG whose header declares width x height (no pixel data)."""
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IEND", b"")


HEIC_BYTES = b"\x00\x00\x00\x18ftypheic\x00\x00\x00\x00mif1heic" + b"\x00" * 64


def _gif() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (400, 400), (90, 80, 70)).save(buf, "GIF")
    return buf.getvalue()


def _scan(files, client=None):
    return (client or TestClient(app)).post("/v1/recognition", files=files)


def _charged() -> int:
    return sum(guest_allowance.store._local.values())


# ── Normal photos ────────────────────────────────────────────────────────────

def test_normal_app_photo_is_processed_and_charged_once():
    photo = _jpeg()
    assert len(photo) < 2 * 1024 * 1024  # what the app actually uploads
    resp = _scan({"front_image": ("f.jpg", photo, "image/jpeg")})

    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] not in ("error", "unavailable", "insufficientQuality")
    assert resp.json()["processingMetadata"]["guest_scans_remaining"] == 1
    assert _charged() == 1  # a guest without an install ID has a single (network) allowance key


def test_full_size_phone_photo_within_limits_is_accepted():
    _, width, height = probe_image(_jpeg(4000, 3000, quality=70))
    assert (width, height) == (4000, 3000)  # 12 MP: the largest accepted size


# ── Oversized uploads ────────────────────────────────────────────────────────

@pytest.mark.parametrize("field", ["front_image", "reverse_image", "edge_image"])
def test_image_over_the_per_image_limit_is_refused_and_not_charged(monkeypatch, field):
    monkeypatch.setattr(settings, "max_upload_mb", 1)
    files = {"front_image": ("f.jpg", _jpeg(800, 800), "image/jpeg")}
    files[field] = ("big.jpg", b"\xff\xd8\xff" + os.urandom(1024 * 1024 + 10), "image/jpeg")

    resp = _scan(files)

    assert resp.status_code == 413
    assert "exceeds maximum upload size of 1MB" in resp.json()["detail"]
    assert _charged() == 0


@pytest.mark.parametrize("width,height", [(20_000, 20_000), (5_000, 5_000), (4_200, 300)])
def test_images_declaring_too_many_pixels_are_refused_before_decoding(width, height):
    bomb = _png_header_only(width, height)
    assert len(bomb) < 100

    started = time.perf_counter()
    resp = _scan({"front_image": ("bomb.png", bomb, "image/png")})

    assert resp.status_code == 413
    assert "too large to process" in resp.json()["detail"]
    assert time.perf_counter() - started < 2.0
    assert _charged() == 0
    with pytest.raises(ImageTooLargeError):
        probe_image(bomb)


# ── Malformed and unsupported images ─────────────────────────────────────────

@pytest.mark.parametrize("name,data,expected", [
    ("garbage.jpg", b"definitely not an image " * 40, "corrupted or unreadable"),
    ("truncated.jpg", _jpeg(800, 800)[:600], "corrupted or unreadable"),
    ("photo.heic", HEIC_BYTES, "HEIC/HEIF photos are not supported"),
    ("anim.gif", _gif(), "GIF images are not supported"),
])
def test_unusable_images_are_answered_cleanly_and_not_charged(name, data, expected):
    resp = _scan({"front_image": (name, data, "application/octet-stream")})

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "insufficientQuality"
    assert any(expected in w for w in body["qualityReport"]["warnings"])
    assert "BytesIO" not in resp.text and "Traceback" not in resp.text
    assert _charged() == 0


# ── Request body caps ────────────────────────────────────────────────────────

def test_json_endpoint_body_over_the_cap_is_refused():
    big = {"category": "other", "title": "x", "description": "a" * (1024 * 1024 + 1)}
    resp = TestClient(app).post("/v1/feedback", json=big)
    assert resp.status_code == 413


def test_streamed_body_without_content_length_is_capped():
    def chunks():
        for _ in range(9):
            yield b"a" * (128 * 1024)

    resp = TestClient(app).post(
        "/v1/feedback", content=chunks(), headers={"Content-Type": "application/json"}
    )
    assert resp.status_code == 413


def _run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def _call_middleware(headers, body_chunks, limit=1000):
    """Drives the middleware directly around an app that reads the whole body."""
    seen = {"app_called": False, "body": b""}

    async def inner_app(scope, receive, send):
        seen["app_called"] = True
        while True:
            message = await receive()
            seen["body"] += message.get("body", b"")
            if not message.get("more_body"):
                break
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"ok"})

    messages = [{"type": "http.request", "body": c, "more_body": i < len(body_chunks) - 1}
                for i, c in enumerate(body_chunks)]
    sent = []

    async def receive():
        return messages.pop(0)

    async def send(message):
        sent.append(message)

    middleware = RequestSizeLimitMiddleware(inner_app, default_max_bytes=limit, path_limits={})
    scope = {"type": "http", "path": "/anything", "headers": headers}
    error = None
    try:
        _run(middleware(scope, receive, send))
    except Exception as exc:  # FastAPI turns this into a 413 in the real app
        error = exc
    status = next((m["status"] for m in sent if m["type"] == "http.response.start"), None)
    return status, error, seen


def test_middleware_refuses_declared_oversize_without_reading_the_body():
    status, _, seen = _call_middleware([(b"content-length", b"5000")], [b"x" * 5000])
    assert status == 413 and seen["app_called"] is False


def test_middleware_stops_streamed_oversize_bodies():
    _, error, seen = _call_middleware([], [b"x" * 600, b"x" * 600])
    assert getattr(error, "status_code", None) == 413
    assert len(seen["body"]) <= 600


def test_middleware_lets_normal_bodies_through_and_rejects_bad_content_length():
    status, error, seen = _call_middleware([(b"content-length", b"10")], [b"0123456789"])
    assert status == 200 and error is None and seen["body"] == b"0123456789"
    status, _, seen = _call_middleware([(b"content-length", b"ten")], [b"0123456789"])
    assert status == 400 and seen["app_called"] is False
