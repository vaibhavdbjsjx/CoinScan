"""
CLI script to run CoinScan accuracy benchmarks across multiple ablation modes.
Generates comprehensive benchmark summary tables and metrics.
"""

import asyncio
import json
import sys
from backend.benchmark.dataset import BENCHMARK_DATASET
from backend.benchmark.benchmark_engine import BenchmarkRunner, AggregateMetrics


async def main():
    print("=" * 80)
    print("COINSCAN NUMISMATIC RECOGNITION ACCURACY & RELIABILITY BENCHMARK")
    print(f"Total Dataset Size: {len(BENCHMARK_DATASET)} ground-truth samples across Categories A through V")
    print("=" * 80)

    runner = BenchmarkRunner()

    modes = [
        ("Full Pipeline (Front + Reverse + Edge + OCR + Numista)", "full"),
        ("Ablation Mode A (Front Only)", "front_only"),
        ("Ablation Mode B (Front + Reverse)", "front_reverse"),
        ("Ablation Mode C (Front + Reverse + Edge)", "front_reverse_edge"),
        ("Ablation Mode D (Vision Only - No OCR, No Numista)", "vision_only"),
        ("Ablation Mode E (Vision + OCR - No Numista)", "vision_ocr"),
        ("Ablation Mode F (Vision + Numista - No OCR)", "vision_numista"),
    ]

    all_metrics: dict[str, AggregateMetrics] = {}

    for label, mode_key in modes:
        print(f"\nEvaluating: {label}...")
        metrics = await runner.run_suite(BENCHMARK_DATASET, mode=mode_key)
        all_metrics[mode_key] = metrics
        print(f"  -> Top-1 Accuracy: {metrics.top_1_accuracy}% | Top-3 Accuracy: {metrics.top_3_accuracy}%")
        print(f"  -> Refusal Precision: {metrics.refusal_precision}% | Contradiction Detection: {metrics.contradiction_detection_rate}%")
        print(f"  -> Hallucination Rate: {metrics.hallucination_rate}% | Latency P50: {metrics.latency_p50_ms}ms")

    # Print Comparison Table
    print("\n" + "=" * 80)
    print("ABLATION & ACCURACY COMPARISON SUMMARY")
    print("=" * 80)
    print(f"{'Ablation Mode':<35} | {'Top-1':<7} | {'Top-3':<7} | {'Refusal':<8} | {'Contra':<7} | {'P50 (ms)':<8}")
    print("-" * 80)
    for label, mode_key in modes:
        m = all_metrics[mode_key]
        print(f"{label[:35]:<35} | {str(m.top_1_accuracy)+'%':<7} | {str(m.top_3_accuracy)+'%':<7} | {str(m.refusal_precision)+'%':<8} | {str(m.contradiction_detection_rate)+'%':<7} | {str(m.latency_p50_ms):<8}")
    print("=" * 80)

    # Print Confidence Calibration Table for Full Pipeline
    full_m = all_metrics["full"]
    print("\n" + "=" * 80)
    print("CONFIDENCE CALIBRATION ANALYSIS (Full Pipeline)")
    print("=" * 80)
    print(f"{'Confidence Range':<20} | {'Sample Count':<14} | {'Correct Count':<14} | {'Actual Accuracy':<15}")
    print("-" * 80)
    for b_range, b_data in full_m.calibration_bins.items():
        print(f"{b_range:<20} | {b_data['count']:<14} | {b_data['correct']:<14} | {str(b_data['accuracy'])+'%':<15}")
    print("=" * 80)

    # Export results to JSON
    summary_data = {k: v.model_dump() for k, v in all_metrics.items()}
    with open("backend/benchmark/benchmark_results.json", "w") as f:
        json.dump(summary_data, f, indent=2)
    print("\nBenchmark results saved to backend/benchmark/benchmark_results.json")


if __name__ == "__main__":
    asyncio.run(main())
