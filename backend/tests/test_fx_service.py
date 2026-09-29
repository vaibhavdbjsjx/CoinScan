import httpx
import pytest

from backend.app.services.currency import fx_service as fx_module
from backend.app.services.currency.fx_service import FxService


def _patch_transport(monkeypatch, handler):
    original = httpx.AsyncClient

    class _Client(original):
        def __init__(self, *args, **kwargs):
            kwargs["transport"] = httpx.MockTransport(handler)
            super().__init__(*args, **kwargs)

    monkeypatch.setattr(fx_module.httpx, "AsyncClient", _Client)


@pytest.mark.asyncio
async def test_fx_service_rates(monkeypatch):
    _patch_transport(
        monkeypatch,
        lambda req: httpx.Response(200, json={"result": "success", "rates": {"USD": 1, "EUR": 0.9, "INR": 88.1}}),
    )
    fx = FxService()
    usd_rate = await fx.get_rate("USD")
    assert usd_rate == 1.0

    eur_rate = await fx.get_rate("EUR")
    assert eur_rate == 0.9

    inr_rate = await fx.get_rate("inr")
    assert inr_rate == 88.1


@pytest.mark.asyncio
async def test_no_builtin_rates_when_provider_unreachable(monkeypatch):
    """Regression: hardcoded seed rates (EUR 0.92, INR 83.5, ...) were used as if live."""

    def handler(req):
        raise httpx.ConnectError("offline", request=req)

    _patch_transport(monkeypatch, handler)
    fx = FxService()
    assert await fx.get_rate("EUR") is None
    assert await fx.get_rate("USD") == 1.0


@pytest.mark.asyncio
async def test_unknown_or_invalid_currency_returns_none(monkeypatch):
    """Regression: unknown currencies silently used a 1.0 rate (USD values labelled as XYZ)."""
    _patch_transport(
        monkeypatch,
        lambda req: httpx.Response(200, json={"result": "success", "rates": {"EUR": 0.9}}),
    )
    fx = FxService()
    assert await fx.get_rate("XYZ") is None
    assert await fx.get_rate("euro") is None
    assert await fx.get_rate("") is None


@pytest.mark.asyncio
async def test_provider_error_result_is_rejected(monkeypatch):
    _patch_transport(monkeypatch, lambda req: httpx.Response(200, json={"result": "error"}))
    assert await FxService().get_rate("EUR") is None
