from datetime import datetime, timedelta, timezone

import pytest

from backend.app.services.valuation.valuation_service import (
    ValuationEngine,
    parse_precious_metal_fineness,
)
from backend.app.services.valuation.metal_price_provider import MetalSpotPriceProvider, SpotQuote
from backend.app.models.domain import CoinIdentity, ValuationStatus, ValuationType


class FakeSpotProvider(MetalSpotPriceProvider):
    """Returns fixed, timestamped quotes as if fetched from a live provider."""

    def __init__(self, prices=None):
        super().__init__(api_key=None)
        self.prices = prices if prices is not None else {"XAG": 30.0, "XAU": 3000.0, "XPT": 1000.0}
        self.fetched_at = datetime(2026, 9, 29, 12, 0, tzinfo=timezone.utc)

    async def get_spot_quote(self, metal_symbol="XAG"):
        price = self.prices.get(metal_symbol)
        if price is None:
            return None
        return SpotQuote(metal_symbol, price, self.fetched_at, "Test-Metals")


def _live_engine():
    return ValuationEngine(metal_provider=FakeSpotProvider())


@pytest.mark.asyncio
async def test_valuation_for_silver_coin():
    """Catalogue silver coin + live spot => melt value only; no invented collector value."""
    engine = _live_engine()
    identity = CoinIdentity(
        country="United States",
        denomination="1 Dollar",
        year=1882,
        mint="CC",
        composition="90% Silver, 10% Copper",
        weightG=26.73,
    )

    valuation = await engine.calculate_valuation(identity, currency_code="USD", fx_rate_to_usd=1.0)
    assert valuation.status == ValuationStatus.PARTIAL
    assert len(valuation.estimates) == 1

    metal_est = next((e for e in valuation.estimates if e.type == ValuationType.METAL_VALUE), None)
    assert metal_est is not None
    # 26.73 g x 0.90 = 24.057 g fine = 0.7735 oz x $30 = $23.20
    assert metal_est.mid == pytest.approx(23.20, abs=0.01)
    assert "2026-09-29" in metal_est.source  # quote time is always disclosed
    assert "Test-Metals" in metal_est.source

    # No fabricated collector estimate or invented auction comparables
    collector_est = next((e for e in valuation.estimates if e.type == ValuationType.COLLECTOR_VALUE), None)
    assert collector_est is None
    assert "no verified numismatic price source" in valuation.valuationNotes


@pytest.mark.asyncio
async def test_valuation_unavailable_for_unknown_coin():
    engine = _live_engine()
    identity = CoinIdentity(
        country="Unknown Fantasy Kingdom",
        denomination="1 Token",
    )

    valuation = await engine.calculate_valuation(identity, currency_code="USD")
    assert valuation.status == ValuationStatus.UNAVAILABLE
    assert len(valuation.estimates) == 0


@pytest.mark.asyncio
async def test_unsupported_silver_coin_with_weight_returns_melt_only():
    """Unsupported silver coin with weight must return melt value ONLY, never a fabricated collector estimate."""
    engine = _live_engine()
    identity = CoinIdentity(
        country="Mexico",
        denomination="1 Peso",
        year=1960,
        composition="10% Silver, 70% Copper, 10% Nickel, 10% Zinc",
        weightG=16.0,
    )

    valuation = await engine.calculate_valuation(identity, currency_code="USD", fx_rate_to_usd=1.0)
    assert valuation.status == ValuationStatus.PARTIAL
    assert len(valuation.estimates) == 1

    melt_est = valuation.estimates[0]
    assert melt_est.type == ValuationType.METAL_VALUE
    assert melt_est.mid is not None
    assert melt_est.mid > 0.0

    # Guarantee NO fabricated collector estimate
    collector_est = next((e for e in valuation.estimates if e.type == ValuationType.COLLECTOR_VALUE), None)
    assert collector_est is None


@pytest.mark.asyncio
async def test_unsupported_gold_coin_with_weight_returns_melt_only():
    """Unsupported gold coin with weight must return melt value ONLY, never a fabricated collector estimate."""
    engine = _live_engine()
    identity = CoinIdentity(
        country="Austria",
        denomination="1 Ducat",
        year=1915,
        composition="98.6% Gold, 1.4% Copper",
        weightG=3.49,
    )

    valuation = await engine.calculate_valuation(identity, currency_code="USD", fx_rate_to_usd=1.0)
    assert valuation.status == ValuationStatus.PARTIAL
    assert len(valuation.estimates) == 1

    melt_est = valuation.estimates[0]
    assert melt_est.type == ValuationType.METAL_VALUE
    assert melt_est.mid is not None
    assert melt_est.mid > 0.0

    # Guarantee NO fabricated collector estimate
    collector_est = next((e for e in valuation.estimates if e.type == ValuationType.COLLECTOR_VALUE), None)
    assert collector_est is None


@pytest.mark.asyncio
async def test_unsupported_silver_coin_without_weight_returns_unavailable():
    """Unsupported silver coin without weight must return UNAVAILABLE, never fabricate a $25-$60 estimate."""
    engine = _live_engine()
    identity = CoinIdentity(
        country="France",
        denomination="5 Francs",
        year=1870,
        composition="90% Silver",
        # No weightG provided
    )

    valuation = await engine.calculate_valuation(identity, currency_code="USD")
    assert valuation.status == ValuationStatus.UNAVAILABLE
    assert len(valuation.estimates) == 0
    assert "no coin weight" in valuation.valuationNotes


@pytest.mark.asyncio
async def test_unsupported_gold_coin_without_weight_returns_unavailable():
    """Unsupported gold coin without weight must return UNAVAILABLE, never fabricate a collector estimate."""
    engine = _live_engine()
    identity = CoinIdentity(
        country="Germany",
        denomination="20 Mark",
        year=1900,
        composition="90% Gold",
        # No weightG provided
    )

    valuation = await engine.calculate_valuation(identity, currency_code="USD")
    assert valuation.status == ValuationStatus.UNAVAILABLE
    assert len(valuation.estimates) == 0


@pytest.mark.asyncio
async def test_previously_hardcoded_coin_gets_no_invented_collector_value():
    """Regression: the 1882-CC Morgan used to return a hardcoded $390 collector value
    with invented 'Heritage Auctions' / 'Stack's Bowers' comparables."""
    engine = _live_engine()
    identity = CoinIdentity(
        country="United States",
        denomination="1 Dollar",
        year=1882,
        mint="CC",
        composition="90% Silver, 10% Copper",
        weightG=26.73,
    )

    valuation = await engine.calculate_valuation(identity, currency_code="USD", fx_rate_to_usd=1.0)
    types = [e.type for e in valuation.estimates]
    assert ValuationType.COLLECTOR_VALUE not in types
    assert ValuationType.MARKET_ESTIMATE not in types
    assert all(e.comparables == [] for e in valuation.estimates)
    dumped = valuation.model_dump_json()
    for invented in ("Heritage", "Stack's Bowers", "CNG", "390"):
        assert invented not in dumped


@pytest.mark.asyncio
async def test_ancient_coin_gets_no_invented_collector_value():
    engine = _live_engine()
    identity = CoinIdentity(country="Ancient Greece (Athens)", denomination="Tetradrachm")
    valuation = await engine.calculate_valuation(identity, currency_code="USD")
    assert valuation.status == ValuationStatus.UNAVAILABLE
    assert valuation.estimates == []


# ─── P0: no built-in "live" spot prices ──────────────────────────────────────

@pytest.mark.asyncio
async def test_no_metal_value_without_live_spot_price():
    """Without a metals provider there is no spot price, so no melt value is invented."""
    engine = ValuationEngine(metal_provider=MetalSpotPriceProvider(api_key=None))
    identity = CoinIdentity(
        country="United States", denomination="1 Dollar", composition="Silver (.900)", weightG=26.73
    )
    valuation = await engine.calculate_valuation(identity, currency_code="USD")
    assert valuation.status == ValuationStatus.UNAVAILABLE
    assert valuation.estimates == []
    assert "No live silver spot price" in valuation.valuationNotes


@pytest.mark.asyncio
async def test_metal_provider_has_no_builtin_prices():
    provider = MetalSpotPriceProvider(api_key=None)
    assert await provider.get_spot_quote("XAU") is None
    assert await provider.get_spot_price_per_gram("XAG") is None


@pytest.mark.asyncio
async def test_stale_quote_is_not_used():
    provider = MetalSpotPriceProvider(api_key=None, max_staleness_hours=24)
    provider._quotes["XAG"] = SpotQuote(
        "XAG", 30.0, datetime.now(timezone.utc) - timedelta(hours=30), "Metals-API"
    )
    assert await provider.get_spot_quote("XAG") is None


# ─── P0: composition parsing never guesses precious-metal content ────────────

@pytest.mark.parametrize(
    "composition",
    [
        "Nordic gold",
        "Nordic gold (Cu89Al5Zn5Sn1)",
        "Nickel silver",
        "German silver",
        "Brass (gold-plated)",
        "Silver-plated copper",
        "Copper-nickel",
        "Bronze",
        "Gold",          # no explicit fineness
        "Silver",        # no explicit fineness
        "Bimetallic: gold (.900) centre, silver (.925) ring",  # ambiguous
    ],
)
def test_no_fineness_inferred_from_keywords(composition):
    assert parse_precious_metal_fineness(composition) is None


@pytest.mark.parametrize(
    "composition,expected",
    [
        ("Silver (.900)", ("XAG", 0.9)),
        ("Gold (.9167)", ("XAU", 0.9167)),
        ("Silver (925)", ("XAG", 0.925)),
        ("90% Silver, 10% Copper", ("XAG", 0.9)),
        ("98.6% Gold, 1.4% Copper", ("XAU", 0.986)),
        ("0.999 fine silver", ("XAG", 0.999)),
        ("999 fine gold", ("XAU", 0.999)),
        ("Platinum (.9995)", ("XPT", 0.9995)),
    ],
)
def test_explicit_fineness_is_parsed(composition, expected):
    assert parse_precious_metal_fineness(composition) == expected


@pytest.mark.asyncio
async def test_nordic_gold_euro_cent_gets_no_gold_melt_value():
    """Regression: a 50 euro cent in Nordic gold was valued at ~$616 as gold."""
    engine = _live_engine()
    identity = CoinIdentity(
        country="Eurozone", denomination="50 Euro Cent", composition="Nordic gold", weightG=7.8
    )
    valuation = await engine.calculate_valuation(identity, currency_code="USD")
    assert valuation.estimates == []
    assert valuation.status == ValuationStatus.UNAVAILABLE


@pytest.mark.asyncio
async def test_ai_inferred_composition_never_produces_melt_value():
    engine = _live_engine()
    identity = CoinIdentity(
        country="Mexico", denomination="1 Peso", composition="Silver (.720)", weightG=16.66
    )
    valuation = await engine.calculate_valuation(
        identity, currency_code="USD", composition_verified=False
    )
    assert valuation.estimates == []
    assert "estimated from the photo" in valuation.valuationNotes
