"""
Pytest integration tests for Benchmark Accuracy, Ablations, Contradiction, and Hallucination Resistance.
"""

import pytest
from backend.benchmark.dataset import BENCHMARK_DATASET
from backend.benchmark.benchmark_engine import BenchmarkRunner


@pytest.mark.asyncio
async def test_full_pipeline_accuracy_benchmark():
    runner = BenchmarkRunner()
    metrics = await runner.run_suite(BENCHMARK_DATASET, mode="full")

    # Primary pipeline benchmarks
    assert metrics.top_1_accuracy >= 90.0, f"Top-1 accuracy {metrics.top_1_accuracy}% is below required 90% threshold"
    assert metrics.top_3_accuracy == 100.0
    assert metrics.refusal_precision == 100.0
    assert metrics.contradiction_detection_rate == 100.0
    assert metrics.hallucination_rate == 0.0


@pytest.mark.asyncio
async def test_front_only_ablation_penalty():
    runner = BenchmarkRunner()
    metrics = await runner.run_suite(BENCHMARK_DATASET, mode="front_only")

    # Front-only must show reduced Top-1 accuracy compared to 2-sided captures due to missing reverse mint marks
    assert metrics.top_1_accuracy < 85.0, "Front-only mode should show realistic accuracy drop for reverse mint mark coins"
    assert metrics.top_3_accuracy == 100.0


@pytest.mark.asyncio
async def test_contradiction_mismatch_detection():
    runner = BenchmarkRunner()
    contra_case = next(c for c in BENCHMARK_DATASET if c.is_contradiction)
    result = await runner.evaluate_single_coin(contra_case, mode="full")

    assert result.is_contradiction_detected is True
    assert result.confidence_level in ["low", "indeterminate"]
    assert result.raw_confidence < 0.60


@pytest.mark.asyncio
async def test_non_coin_token_hallucination_refusal():
    runner = BenchmarkRunner()
    token_case = next(c for c in BENCHMARK_DATASET if c.id == "CAT-M-01")
    result = await runner.evaluate_single_coin(token_case, mode="full")

    assert result.status == "unknown"
    assert result.is_hallucination_detected is False
    assert result.numista_attributed is False


@pytest.mark.asyncio
async def test_metal_melt_valuation_integrity():
    from datetime import datetime, timezone
    from backend.app.services.valuation.valuation_service import ValuationEngine
    from backend.app.services.valuation.metal_price_provider import MetalSpotPriceProvider, SpotQuote
    from backend.app.models.domain import CoinIdentity, ValuationStatus, ValuationType

    class _LiveQuote(MetalSpotPriceProvider):
        """Simulates a real, timestamped silver quote of $32.50/oz (no built-in prices exist)."""

        async def get_spot_quote(self, metal_symbol="XAG"):
            return SpotQuote(metal_symbol, 32.50, datetime(2026, 9, 29, tzinfo=timezone.utc), "Test-Metals")

    engine = ValuationEngine(metal_provider=_LiveQuote())
    # 1882 Morgan Dollar: 26.73g @ 90% silver = 24.057g pure silver = ~0.77344 troy oz
    silver_coin = CoinIdentity(
        country="United States",
        denomination="1 Dollar",
        year=1882,
        composition="90% Silver, 10% Copper",
        weightG=26.73,
        numistaId=1492,
    )

    val_res = await engine.calculate_valuation(silver_coin, "USD", 1.0)
    # Only the melt layer is available (no verified collector price source), hence PARTIAL
    assert val_res.status == ValuationStatus.PARTIAL
    assert len(val_res.estimates) >= 1

    melt_est = next(e for e in val_res.estimates if e.type == ValuationType.METAL_VALUE)
    assert melt_est is not None
    # With spot silver ~$32.50/oz, 0.7734 oz * $32.50 = ~$25.13
    assert 20.0 <= melt_est.mid <= 30.0
    assert "900/1000" in melt_est.source
    assert "not a collector or market price" in melt_est.caveat
