"""
P0 regression tests: the recognition API never returns invented prices.
"""

import io

from fastapi.testclient import TestClient
from PIL import Image

from backend.app.api import recognition as recognition_module
from backend.app.main import app
from backend.app.services.currency.fx_service import FxService
from backend.app.services.numista.client import NumistaClient, NumistaTypeDetail
from backend.app.services.valuation.valuation_service import ValuationEngine
from backend.app.services.valuation.metal_price_provider import MetalSpotPriceProvider

client = TestClient(app)


def _jpeg_bytes(size: int = 400) -> bytes:
    img = Image.new("RGB", (size, size), color=(120, 110, 90))
    for x in range(0, size, 8):
        for y in range(size):
            img.putpixel((x, y), (250, 250, 250))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=92)
    return buf.getvalue()


class _StaticCatalogue(NumistaClient):
    def __init__(self, record: NumistaTypeDetail):
        super().__init__(api_key="unused")
        self.record = record

    async def search_types(self, query, category="coin", count=5):
        return [self.record]


class _NoRatesFx(FxService):
    async def get_rate(self, target_currency):
        return 1.0 if target_currency.upper() == "USD" else None


def test_scan_without_price_sources_returns_explicit_unavailable_valuation(monkeypatch):
    record = NumistaTypeDetail(
        id=1492, title="1 Dollar 'Morgan Dollar'", country="United States",
        denomination="1 Dollar", min_year=1878, max_year=1921,
        composition="Silver (.900)", weight_g=26.73,
    )
    monkeypatch.setattr(recognition_module, "numista_client", _StaticCatalogue(record))
    # No metals provider configured: there is no real spot price
    monkeypatch.setattr(
        recognition_module,
        "valuation_engine",
        ValuationEngine(metal_provider=MetalSpotPriceProvider(api_key=None)),
    )

    resp = client.post("/v1/recognition", files={"front_image": ("f.jpg", _jpeg_bytes(), "image/jpeg")})
    body = resp.json()

    valuation = body["valuation"]
    assert valuation["status"] == "unavailable"
    assert valuation["estimates"] == []
    assert "No live silver spot price" in valuation["valuationNotes"]
    for invented in ("Heritage", "Stack's Bowers", "Live Silver Spot", "32.5", "2680"):
        assert invented not in resp.text


def test_unavailable_currency_falls_back_to_usd_with_warning(monkeypatch):
    record = NumistaTypeDetail(id=1, title="1 Franc", country="France", min_year=1960, max_year=2001)
    monkeypatch.setattr(recognition_module, "numista_client", _StaticCatalogue(record))
    monkeypatch.setattr(recognition_module, "fx_service", _NoRatesFx())

    resp = client.post(
        "/v1/recognition",
        files={"front_image": ("f.jpg", _jpeg_bytes(), "image/jpeg")},
        data={"preferred_currency": "EUR"},
    )
    body = resp.json()

    assert body["valuation"]["currencyCode"] == "USD"
    assert any("EUR" in w and "USD" in w for w in body["warnings"])
