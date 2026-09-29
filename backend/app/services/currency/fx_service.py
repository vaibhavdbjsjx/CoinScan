"""
Foreign exchange (FX) conversion service with TTL caching.
Provides multi-currency support for international collector valuations.

Only rates actually fetched from the provider are used. There are no built-in
seed rates: if no fresh rate is available for a currency, get_rate returns None
and callers must fall back to USD rather than label USD amounts as another
currency.
"""

import math
import re
import logging
from typing import Dict, Optional
from datetime import datetime, timedelta, timezone
import httpx

logger = logging.getLogger("coinscan.fx")

_CURRENCY_CODE = re.compile(r"^[A-Z]{3}$")


class FxService:
    """Provides currency conversion rates against USD with in-memory TTL caching."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        base_url: str = "https://open.er-api.com/v6/latest",
        cache_ttl_hours: float = 4.0,
        max_staleness_hours: float = 24.0,
    ):
        self.api_key = api_key
        self.base_url = base_url
        self.cache_ttl = timedelta(hours=cache_ttl_hours)
        self.max_staleness = timedelta(hours=max_staleness_hours)
        self._rates: Dict[str, float] = {}
        self._fetched_at: Optional[datetime] = None

    async def get_rate(self, target_currency: str) -> Optional[float]:
        """Returns units of target_currency per 1 USD, or None if no reliable rate is available."""
        curr = (target_currency or "").strip().upper()
        if curr == "USD":
            return 1.0
        if not _CURRENCY_CODE.match(curr):
            return None

        now = datetime.now(timezone.utc)
        if self._fetched_at is None or now - self._fetched_at >= self.cache_ttl:
            await self._refresh(now)

        if self._fetched_at is None or now - self._fetched_at > self.max_staleness:
            return None
        rate = self._rates.get(curr)
        if rate is None or rate <= 0 or math.isnan(rate) or math.isinf(rate):
            return None
        return rate

    async def _refresh(self, now: datetime) -> None:
        try:
            async with httpx.AsyncClient(timeout=6.0) as client:
                resp = await client.get(f"{self.base_url}/USD")
        except httpx.HTTPError as exc:
            logger.warning(f"FX rate fetch failed: {type(exc).__name__}")
            return
        if resp.status_code != 200:
            logger.warning(f"FX provider returned HTTP {resp.status_code}")
            return
        try:
            data = resp.json()
        except ValueError:
            logger.warning("FX provider returned invalid JSON")
            return
        if not isinstance(data, dict) or data.get("result") == "error":
            logger.warning("FX provider reported an error result")
            return
        rates = data.get("rates") or {}
        parsed: Dict[str, float] = {}
        for code, value in rates.items():
            try:
                parsed[str(code).upper()] = float(value)
            except (TypeError, ValueError):
                continue
        if parsed:
            self._rates = parsed
            self._fetched_at = now
