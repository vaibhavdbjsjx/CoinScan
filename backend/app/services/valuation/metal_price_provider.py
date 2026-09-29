"""
Precious metal spot price provider with in-memory TTL caching.
Provides live bullion valuations for gold, silver, and platinum coins.

Only prices actually fetched from the configured provider are ever returned,
together with the time they were fetched. There are no built-in "baseline"
prices: when no provider is configured, or the last successful fetch is older
than max_staleness, no price is returned and callers must report the metal
value as unavailable.
"""

import math
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Dict, Optional
import logging

import httpx

logger = logging.getLogger("coinscan.valuation.metals")

TROY_OUNCE_GRAMS = 31.1034768

# Plausibility bounds (USD per troy ounce) used to reject corrupt provider payloads.
_PLAUSIBLE_USD_PER_OZ = {
    "XAG": (1.0, 1_000.0),
    "XAU": (100.0, 100_000.0),
    "XPT": (50.0, 50_000.0),
}


@dataclass(frozen=True)
class SpotQuote:
    """A spot price that was actually fetched from a provider."""

    symbol: str
    price_usd_per_oz: float
    fetched_at: datetime
    provider: str

    @property
    def price_usd_per_gram(self) -> float:
        return self.price_usd_per_oz / TROY_OUNCE_GRAMS


class MetalSpotPriceProvider:
    """Provides precious metal spot rates (USD per troy ounce / gram) with caching."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        base_url: str = "https://metals-api.com/api/latest",
        cache_ttl_hours: float = 1.0,
        max_staleness_hours: float = 24.0,
    ):
        self.api_key = api_key
        self.base_url = base_url
        self.cache_ttl = timedelta(hours=cache_ttl_hours)
        self.max_staleness = timedelta(hours=max_staleness_hours)
        self._quotes: Dict[str, SpotQuote] = {}

    async def get_spot_quote(self, metal_symbol: str = "XAG") -> Optional[SpotQuote]:
        """Returns a real, sufficiently fresh quote, or None if none is available."""
        symbol = metal_symbol.upper()
        now = datetime.now(timezone.utc)

        cached = self._quotes.get(symbol)
        if cached is not None and now - cached.fetched_at < self.cache_ttl:
            return cached

        if self.api_key:
            await self._refresh(now)

        cached = self._quotes.get(symbol)
        if cached is not None and now - cached.fetched_at <= self.max_staleness:
            return cached
        return None

    async def get_spot_price_per_troy_oz(self, metal_symbol: str = "XAG") -> Optional[float]:
        quote = await self.get_spot_quote(metal_symbol)
        return quote.price_usd_per_oz if quote else None

    async def get_spot_price_per_gram(self, metal_symbol: str = "XAG") -> Optional[float]:
        """Returns spot price in USD per gram (1 Troy Oz = 31.1035 grams), or None."""
        quote = await self.get_spot_quote(metal_symbol)
        return quote.price_usd_per_gram if quote else None

    async def _refresh(self, now: datetime) -> None:
        params = {
            "access_key": self.api_key,
            "base": "USD",
            "symbols": "XAG,XAU,XPT",
        }
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                resp = await client.get(self.base_url, params=params)
        except httpx.HTTPError as exc:
            # Never log the exception text: it contains the URL with access_key.
            logger.warning(f"Metal spot price fetch failed: {type(exc).__name__}")
            return

        if resp.status_code != 200:
            logger.warning(f"Metal spot price provider returned HTTP {resp.status_code}")
            return
        try:
            data = resp.json()
        except ValueError:
            logger.warning("Metal spot price provider returned invalid JSON")
            return
        if not isinstance(data, dict) or data.get("success") is False:
            logger.warning("Metal spot price provider reported an unsuccessful response")
            return

        rates = data.get("rates") or {}
        for symbol, (low, high) in _PLAUSIBLE_USD_PER_OZ.items():
            raw = rates.get(symbol)
            if not isinstance(raw, (int, float)) or raw <= 0 or math.isnan(raw) or math.isinf(raw):
                continue
            # Metals-API quotes ounces per 1 USD when base=USD; invert to USD per ounce.
            price = (1.0 / raw) if raw < 1.0 else float(raw)
            if not (low <= price <= high):
                logger.warning(f"Rejected implausible {symbol} spot price: {price}")
                continue
            self._quotes[symbol] = SpotQuote(
                symbol=symbol,
                price_usd_per_oz=price,
                fetched_at=now,
                provider="Metals-API",
            )
