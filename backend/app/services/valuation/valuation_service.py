"""
Comprehensive numismatic valuation service.
Separates Face Value, Intrinsic Melt Value, Catalogue Guide, and Realized Comparables.

Integrity rules (never present invented prices as real data):
- Melt value is calculated only from a catalogue-verified composition with an
  explicitly stated fineness, a catalogue weight, and a real, timestamped spot
  quote. Alloy names are never guessed from keywords ("Nordic gold" and
  "nickel silver" contain no precious metal), and purity is never assumed.
- Collector / market layers are only returned from a verified market-data
  source. None is connected yet, so those layers are reported as unavailable
  instead of being filled with placeholder numbers.
- When nothing reliable is available, the result says so explicitly.
"""

from typing import Optional, List, Tuple
from datetime import datetime, timezone
import re
import math

from backend.app.models.domain import (
    ValuationResult,
    ValuationEstimate,
    ValuationType,
    ValuationStatus,
    CoinIdentity,
)
from backend.app.config import settings
from backend.app.services.valuation.metal_price_provider import MetalSpotPriceProvider

_METAL_SYMBOLS = {"silver": "XAG", "gold": "XAU", "platinum": "XPT"}
_METAL_NAMES = {"XAG": "Silver", "XAU": "Gold", "XPT": "Platinum"}

# Compositions containing these markers do not have a meaningful precious-metal
# fineness even if a metal name appears in them.
_NON_PRECIOUS_MARKERS = (
    "plated",
    "gilt",
    "gilded",
    "coated",
    "nickel silver",
    "german silver",
    "nordic gold",
    "gold-colored",
    "gold coloured",
    "gold-coloured",
    "silver-colored",
    "silver coloured",
)

_METAL = r"(silver|gold|platinum)"
_FINENESS_PATTERNS = [
    # Numista style: "Silver (.900)", "Gold (0.9167)", "Silver (925)"
    (re.compile(_METAL + r"\s*\(\s*(0?\.\d{2,4}|\d{3,4}(?:\.\d+)?)\s*\)"), "metal_first"),
    # "90% silver", "98.6% Gold"
    (re.compile(r"(\d{1,3}(?:\.\d+)?)\s*%\s*" + _METAL), "percent"),
    # ".925 silver", "0.999 fine gold"
    (re.compile(r"(?<![\d.])(0?\.\d{3,4})\s*(?:fine\s+)?" + _METAL), "decimal"),
    # "999 fine silver", "925 silver"
    (re.compile(r"(?<![\d.%])(\d{3}(?:\.\d)?)\s*(?:fine\s+)?" + _METAL), "millesimal"),
]


def parse_precious_metal_fineness(composition: Optional[str]) -> Optional[Tuple[str, float]]:
    """Returns (metal_symbol, fineness 0..1) only when the composition states it explicitly.

    Returns None for base-metal alloys, plated/gilt coins, compositions without
    an explicit fineness, and ambiguous multi-metal compositions.
    """
    if not composition:
        return None
    text = composition.lower()
    if any(marker in text for marker in _NON_PRECIOUS_MARKERS):
        return None

    found = {}
    for pattern, kind in _FINENESS_PATTERNS:
        for match in pattern.finditer(text):
            if kind == "metal_first":
                metal, raw = match.group(1), match.group(2)
            else:
                raw, metal = match.group(1), match.group(2)
            try:
                value = float(raw)
            except ValueError:
                continue
            if kind == "percent":
                value = value / 100.0
            elif value > 1.0:
                value = value / 1000.0
            if 0.0 < value <= 1.0:
                found.setdefault(_METAL_SYMBOLS[metal], set()).add(round(value, 4))

    if len(found) != 1:
        return None  # nothing explicit, or ambiguous (e.g. bimetallic)
    symbol, values = next(iter(found.items()))
    if len(values) != 1:
        return None  # contradictory fineness statements
    return symbol, next(iter(values))


def _mentions_precious_metal(composition: Optional[str]) -> bool:
    return bool(composition) and bool(re.search(_METAL, composition.lower()))


class ValuationEngine:
    """Calculates factual valuation breakdown across multiple economic dimensions."""

    def __init__(self, metal_provider: Optional[MetalSpotPriceProvider] = None):
        self.metal_provider = metal_provider or MetalSpotPriceProvider(
            api_key=settings.metals_api_key,
            base_url=settings.metals_api_base_url,
        )

    async def calculate_valuation(
        self,
        identity: CoinIdentity,
        currency_code: str = "USD",
        fx_rate_to_usd: float = 1.0,
        composition_verified: bool = True,
    ) -> ValuationResult:
        """Builds the valuation breakdown.

        composition_verified must be False when identity.composition was inferred
        by AI from the photo rather than taken from a catalogue record.
        """
        now_str = datetime.now(timezone.utc).isoformat()
        notes: List[str] = []

        fx_ok = not (
            fx_rate_to_usd is None
            or math.isnan(fx_rate_to_usd)
            or math.isinf(fx_rate_to_usd)
            or fx_rate_to_usd <= 0.0
        )
        if not fx_ok:
            return ValuationResult(
                status=ValuationStatus.UNAVAILABLE,
                currencyCode=currency_code,
                estimates=[],
                valuationNotes="A valid currency conversion rate is not available, so no values are shown.",
                updatedAt=now_str,
            )

        estimates: List[ValuationEstimate] = []

        # Layer 1 - Face value: legal-tender value is shown by the client from the
        # denomination; it is not a monetary estimate and is not computed here.

        # Layer 2 - Intrinsic metal (melt) value
        metal_estimate, metal_note = await self._calculate_melt_value(
            identity, currency_code, fx_rate_to_usd, composition_verified
        )
        if metal_estimate:
            estimates.append(metal_estimate)
        if metal_note:
            notes.append(metal_note)

        # Layers 3 & 4 - Collector guide and realized market comparables
        notes.append(
            "Collector and market values are not shown because no verified numismatic "
            "price source is connected yet."
        )

        status = ValuationStatus.PARTIAL if estimates else ValuationStatus.UNAVAILABLE
        return ValuationResult(
            status=status,
            currencyCode=currency_code,
            estimates=estimates,
            valuationNotes=" ".join(notes),
            updatedAt=now_str,
        )

    async def _calculate_melt_value(
        self,
        identity: CoinIdentity,
        currency_code: str,
        fx_rate: float,
        composition_verified: bool,
    ) -> Tuple[Optional[ValuationEstimate], Optional[str]]:
        """Returns (estimate, None) or (None, reason-shown-to-user-or-None)."""
        composition = identity.composition
        if not composition:
            return None, None

        parsed = parse_precious_metal_fineness(composition)
        if parsed is None:
            if _mentions_precious_metal(composition):
                return None, (
                    "The catalogue composition does not state an explicit precious-metal "
                    "fineness, so no melt value is shown."
                )
            return None, None  # base-metal coin: no melt layer

        if not composition_verified:
            return None, (
                "The metal content was estimated from the photo rather than taken from a "
                "catalogue record, so no melt value is shown."
            )

        weight = identity.weightG
        if weight is None or math.isnan(weight) or math.isinf(weight) or weight <= 0:
            return None, "The catalogue record has no coin weight, so no melt value can be calculated."

        symbol, fineness = parsed
        metal_name = _METAL_NAMES[symbol]
        quote = await self.metal_provider.get_spot_quote(symbol)
        if quote is None:
            return None, f"No live {metal_name.lower()} spot price is available right now, so no melt value is shown."

        pure_grams = weight * fineness
        melt_usd = pure_grams * quote.price_usd_per_gram
        melt_converted = melt_usd * fx_rate
        pure_oz = pure_grams / 31.1034768
        fetched = quote.fetched_at.astimezone(timezone.utc)

        return ValuationEstimate(
            type=ValuationType.METAL_VALUE,
            currencyCode=currency_code,
            low=round(melt_converted * 0.98, 2),
            high=round(melt_converted * 1.02, 2),
            mid=round(melt_converted, 2),
            valuedAt=fetched.isoformat(),
            source=(
                f"{quote.provider} {metal_name.lower()} spot ${quote.price_usd_per_oz:,.2f}/oz "
                f"as of {fetched:%Y-%m-%d %H:%M} UTC; {pure_oz:.4f} oz fine "
                f"({fineness * 1000:.0f}/1000 x {weight:g} g catalogue weight)"
            ),
            caveat=(
                "Bullion (melt) value only - not a collector or market price. Based on "
                "catalogue weight and fineness; worn or damaged coins contain less metal."
            ),
            confidenceScore=0.9,
        ), None
