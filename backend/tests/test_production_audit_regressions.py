"""
Regression tests for bugs found and fixed during the CoinScan production audit.

Each test targets a specific real bug that was discovered and patched:

1. safe_parse_vision_response — Markdown fences, preamble, year clamping, score clamping
2. Valuation guards — Zero/negative spot price, FX rate, and weight
3. Numista fallback — No silent Morgan Dollar fallback on unmatched queries
4. JWT prefix — jwt_token_ prefix is accepted by JwtAuthVerifier
"""

import json
import pytest

# ─── 1. Vision response defensive parsing ────────────────────────────────────

from backend.app.services.recognition.vision_provider import (
    safe_parse_vision_response,
    RawVisionObservation,
)


class TestSafeParseVisionResponse:
    """Regression: AI models sometimes wrap JSON in markdown fences or add conversational text."""

    def test_strips_markdown_code_fences(self):
        raw = '```json\n{"country": "United States", "denomination": "1 Dollar"}\n```'
        obs = safe_parse_vision_response(raw)
        assert obs.country == "United States"
        assert obs.denomination == "1 Dollar"

    def test_strips_preamble_and_postscript(self):
        raw = 'Here is the analysis:\n\n{"country": "France", "denomination": "5 Francs"}\n\nLet me know if you need anything else.'
        obs = safe_parse_vision_response(raw)
        assert obs.country == "France"
        assert obs.denomination == "5 Francs"

    def test_clamps_year_string_to_valid_range(self):
        raw = json.dumps({"country": "Test", "denomination": "1 Coin", "year": "99999"})
        obs = safe_parse_vision_response(raw)
        assert obs.year is None

    def test_parses_year_from_string(self):
        raw = json.dumps({"country": "Test", "denomination": "1 Coin", "year": "circa 1882"})
        obs = safe_parse_vision_response(raw)
        assert obs.year == 1882

    def test_accepts_negative_year_for_ancient_coins(self):
        raw = json.dumps({"country": "Ancient Greece", "denomination": "Tetradrachm", "year": -440})
        obs = safe_parse_vision_response(raw)
        assert obs.year == -440

    def test_clamps_visual_similarity_score_above_one(self):
        raw = json.dumps({"country": "Test", "denomination": "1 Coin", "visual_similarity_score": 1.5})
        obs = safe_parse_vision_response(raw)
        assert obs.visual_similarity_score == 1.0

    def test_clamps_visual_similarity_score_below_zero(self):
        raw = json.dumps({"country": "Test", "denomination": "1 Coin", "visual_similarity_score": -0.3})
        obs = safe_parse_vision_response(raw)
        assert obs.visual_similarity_score == 0.0

    def test_defaults_visual_similarity_score_when_missing(self):
        raw = json.dumps({"country": "Test", "denomination": "1 Coin"})
        obs = safe_parse_vision_response(raw)
        assert obs.visual_similarity_score == 0.8

    def test_fallback_for_unparsable_score(self):
        raw = json.dumps({"country": "Test", "denomination": "1 Coin", "visual_similarity_score": "very high"})
        obs = safe_parse_vision_response(raw)
        assert obs.visual_similarity_score == 0.5

    def test_strips_unknown_extra_fields(self):
        """AI might return keys not in our schema — they should be silently dropped."""
        raw = json.dumps({"country": "UK", "denomination": "1 Penny", "ai_internal_notes": "very cool coin"})
        obs = safe_parse_vision_response(raw)
        assert obs.country == "UK"
        assert not hasattr(obs, "ai_internal_notes")


# ─── 2. Valuation safety guards ──────────────────────────────────────────────

from backend.app.services.valuation.valuation_service import ValuationEngine
from backend.app.models.domain import CoinIdentity, ValuationStatus, ValuationType


class TestValuationSafetyGuards:
    """Regression: Valuation must not produce absurd numbers from zero/negative inputs."""

    @pytest.mark.asyncio
    async def test_zero_fx_rate_returns_no_metal_estimate(self):
        engine = ValuationEngine()
        identity = CoinIdentity(
            country="United States",
            denomination="1 Dollar",
            year=1882,
            composition="90% Silver, 10% Copper",
            weightG=26.73,
        )
        result = await engine.calculate_valuation(identity, currency_code="USD", fx_rate_to_usd=0.0)
        # Should not crash or produce infinite values
        metal_est = next((e for e in result.estimates if e.type == ValuationType.METAL_VALUE), None)
        assert metal_est is None  # Guard rejects zero FX rate

    @pytest.mark.asyncio
    async def test_negative_fx_rate_returns_no_metal_estimate(self):
        engine = ValuationEngine()
        identity = CoinIdentity(
            country="United States",
            denomination="1 Dollar",
            year=1882,
            composition="90% Silver, 10% Copper",
            weightG=26.73,
        )
        result = await engine.calculate_valuation(identity, currency_code="USD", fx_rate_to_usd=-1.5)
        metal_est = next((e for e in result.estimates if e.type == ValuationType.METAL_VALUE), None)
        assert metal_est is None

    @pytest.mark.asyncio
    async def test_missing_weight_returns_no_metal_estimate(self):
        engine = ValuationEngine()
        identity = CoinIdentity(
            country="United States",
            denomination="1 Dollar",
            year=1882,
            composition="90% Silver, 10% Copper",
            # No weightG specified
        )
        result = await engine.calculate_valuation(identity, currency_code="USD")
        metal_est = next((e for e in result.estimates if e.type == ValuationType.METAL_VALUE), None)
        assert metal_est is None

    @pytest.mark.asyncio
    async def test_non_precious_metal_returns_no_metal_estimate(self):
        engine = ValuationEngine()
        identity = CoinIdentity(
            country="United States",
            denomination="1 Cent",
            year=2020,
            composition="Copper Plated Zinc",
            weightG=2.5,
        )
        result = await engine.calculate_valuation(identity, currency_code="USD")
        metal_est = next((e for e in result.estimates if e.type == ValuationType.METAL_VALUE), None)
        assert metal_est is None


# ─── 3. Numista catalogue: no silent fallback ────────────────────────────────

from backend.app.services.numista.client import NumistaClient


class TestNumistaNoSilentFallback:
    """Regression: the (explicitly enabled) offline fixture must not return Morgan Dollar for unmatched queries."""

    @pytest.mark.asyncio
    async def test_unmatched_query_returns_empty_list(self):
        client = NumistaClient(api_key=None, offline_fixture=True)
        results = await client.search_types("xyzzy nonexistent coin pattern")
        assert results == [], (
            f"Expected empty list for unmatched query, got {len(results)} records — "
            "silent fallback bug has regressed."
        )

    @pytest.mark.asyncio
    async def test_matching_query_returns_relevant_records(self):
        client = NumistaClient(api_key=None, offline_fixture=True)
        results = await client.search_types("dollar")
        # Should find the Morgan Dollar in the fallback catalog
        assert len(results) >= 1
        assert any("Dollar" in r.title for r in results)

    @pytest.mark.asyncio
    async def test_empty_query_returns_all_fallback_records(self):
        client = NumistaClient(api_key=None, offline_fixture=True)
        results = await client.search_types("")
        assert len(results) >= 1  # Should return all records for empty query


# ─── 4. JWT token prefix support ─────────────────────────────────────────────

from backend.app.security.jwt_auth import JwtAuthVerifier, AuthenticatedUser


class TestJwtTokenPrefixRegression:
    """Regression: jwt_token_ prefix must be accepted alongside usr_ and dev_."""

    def test_jwt_token_prefix_resolves_authenticated_user(self):
        verifier = JwtAuthVerifier()
        user = verifier.verify_token("jwt_token_abc123")
        assert user is not None
        assert user.is_authenticated is True
        assert user.user_id is not None
        assert user.auth_method == "jwt"

    def test_usr_prefix_still_works(self):
        verifier = JwtAuthVerifier()
        user = verifier.verify_token("usr_test456")
        assert user is not None
        assert user.is_authenticated is True

    def test_dev_prefix_still_works(self):
        verifier = JwtAuthVerifier()
        user = verifier.verify_token("dev_test789")
        assert user is not None
        assert user.is_authenticated is True

    def test_bearer_prefix_stripped(self):
        verifier = JwtAuthVerifier()
        user = verifier.verify_token("Bearer jwt_token_abc123")
        assert user is not None
        assert user.is_authenticated is True

    def test_unknown_prefix_returns_none(self):
        verifier = JwtAuthVerifier()
        user = verifier.verify_token("random_invalid_token_xxx")
        assert user is None

    def test_empty_token_returns_none(self):
        verifier = JwtAuthVerifier()
        user = verifier.verify_token("")
        assert user is None

    def test_none_token_returns_none(self):
        verifier = JwtAuthVerifier()
        user = verifier.verify_token(None)
        assert user is None
