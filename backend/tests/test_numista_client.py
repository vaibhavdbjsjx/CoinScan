import httpx
import pytest

from backend.app.services.numista import client as numista_module
from backend.app.services.numista.client import (
    CatalogueUnavailableError,
    NumistaClient,
    SOURCE_NUMISTA,
    SOURCE_OFFLINE_FIXTURE,
)


# ─── Offline fixture (tests / benchmark only, explicit opt-in) ────────────────

@pytest.mark.asyncio
async def test_numista_fallback_catalog_search():
    client = NumistaClient(api_key=None, offline_fixture=True)
    results = await client.search_types("Morgan Dollar")
    assert len(results) >= 1
    primary = results[0]
    assert primary.id == 1492
    assert "Morgan" in primary.title
    assert primary.country == "United States"
    assert primary.weight_g == 26.73
    # Fixture data must always be labelled as such, never as Numista
    assert primary.source == SOURCE_OFFLINE_FIXTURE


@pytest.mark.asyncio
async def test_numista_fallback_type_details():
    client = NumistaClient(api_key=None, offline_fixture=True)
    item = await client.get_type_details(4378)
    assert item is not None
    assert item.id == 4378
    assert "George V" in item.title
    assert item.country == "British India"
    assert item.source == SOURCE_OFFLINE_FIXTURE


# ─── P0: no invented catalogue data in normal operation ──────────────────────

@pytest.mark.asyncio
async def test_missing_api_key_raises_instead_of_inventing_data():
    client = NumistaClient(api_key=None)
    with pytest.raises(CatalogueUnavailableError):
        await client.search_types("british india")
    with pytest.raises(CatalogueUnavailableError):
        await client.get_type_details(4378)


def _patch_transport(monkeypatch, handler):
    original = httpx.AsyncClient

    class _Client(original):
        def __init__(self, *args, **kwargs):
            kwargs["transport"] = httpx.MockTransport(handler)
            super().__init__(*args, **kwargs)

    monkeypatch.setattr(numista_module.httpx, "AsyncClient", _Client)


@pytest.mark.asyncio
@pytest.mark.parametrize("status_code", [401, 429, 500, 503])
async def test_http_error_raises_instead_of_fixture(monkeypatch, status_code):
    _patch_transport(monkeypatch, lambda req: httpx.Response(status_code, json={}))
    client = NumistaClient(api_key="test-key")
    with pytest.raises(CatalogueUnavailableError):
        await client.search_types("british india")


@pytest.mark.asyncio
async def test_timeout_raises_instead_of_fixture(monkeypatch):
    def handler(req):
        raise httpx.ReadTimeout("timed out", request=req)

    _patch_transport(monkeypatch, handler)
    with pytest.raises(CatalogueUnavailableError):
        await NumistaClient(api_key="test-key").search_types("british india")


@pytest.mark.asyncio
async def test_live_results_are_labelled_numista_and_empty_means_no_match(monkeypatch):
    def handler(req):
        assert req.headers["Numista-API-Key"] == "test-key"
        if req.url.params.get("q") == "nothing":
            return httpx.Response(200, json={"count": 0, "types": []})
        return httpx.Response(
            200,
            json={
                "count": 1,
                "types": [
                    {"id": 99, "title": "10 Cents", "issuer": {"name": "Canada"}, "min_year": 1937, "max_year": 1947}
                ],
            },
        )

    _patch_transport(monkeypatch, handler)
    client = NumistaClient(api_key="test-key")
    results = await client.search_types("canada 10 cents")
    assert len(results) == 1
    assert results[0].source == SOURCE_NUMISTA
    assert results[0].country == "Canada"
    assert await client.search_types("nothing") == []


@pytest.mark.asyncio
async def test_type_details_404_returns_none(monkeypatch):
    _patch_transport(monkeypatch, lambda req: httpx.Response(404, json={}))
    assert await NumistaClient(api_key="test-key").get_type_details(123456) is None
