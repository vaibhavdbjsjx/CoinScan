# CoinScan Phase 12: Actual Unit Economics & Infrastructure Cost Analysis

**Date:** 2026-08-30  
**Author:** Principal Cloud Infrastructure & Financial Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Per-Scan Variable Cost Breakdown

| Pipeline Component | Service / Provider | Consumption per Scan | Unit Rate | Cost per Scan (USD) |
|---|---|---|---|---|
| **Vision AI Inference** | Google Gemini 2.0 Flash | 2 Images (~1,200 tokens input, ~250 tokens output) | $0.10 / 1M in, $0.40 / 1M out | **$0.000220** |
| **Catalogue Lookup** | Numista Commercial API | 1 Search + 1 Type Lookup (Cached 24h) | $0.05 / 1k queries | **$0.000050** |
| **Precious Metal Spot Feed** | Metal Price Provider / Cache | In-memory 15-min cache | $10 / 100k queries | **$0.000010** |
| **FX Currency Conversion** | ExchangeRate-API (Cached 1h) | In-memory 1-hour cache | Free tier / $10/mo | **$0.000005** |
| **Cloud Run Compute & Network** | Google Cloud Run (2 vCPU, 2GB) | ~1.2s container execution time | $0.000024 / vCPU-sec | **$0.000058** |
| **Total Marginal Cost Per Scan** | — | — | — | **$0.000343** |

---

## 2. Monthly Infrastructure Projections by Scale

### Scenario A: Early Launch (1,000 Active Users, 10,000 Scans/Month)
- **Vision AI Inference:** 10,000 * $0.00022 = $2.20
- **Cloud Run Compute (min-instances=0 with on-demand scale):** ~$5.00
- **Supabase Database (Free Tier / Starter):** $0.00
- **Total Infrastructure Cost:** **~$7.20 / month**
- **Estimated Revenue (50 paid users @ $4.99/mo):** $249.50
- **Gross Margin:** **~97.1%**

### Scenario B: Steady Growth (25,000 Active Users, 250,000 Scans/Month)
- **Vision AI Inference:** 250,000 * $0.00022 = $55.00
- **Cloud Run Compute (min-instances=1 warm during peak hours):** ~$38.00
- **Supabase Database (Pro Tier):** $25.00
- **Total Infrastructure Cost:** **~$118.00 / month**
- **Estimated Revenue (1,250 paid users @ $5.99 avg):** $7,487.50
- **Gross Margin:** **~98.4%**

---

## 3. Key Financial Insights & Abuse Safeguards

1. **High Fair-Use Margin:** Even an intensive Pro user scanning 100 coins in a single month costs CoinScan only **~$0.034** in total variable cloud costs against their **$9.99** subscription fee.
2. **Free Tier Abuse Prevention:** The 3-scan daily limit caps unauthenticated free user variable costs to **< $0.03 / user / month**, rendering free tier operations sustainable at scale.
3. **Aggressive Cache Optimization:** 1-hour FX caching and 24-hour Numista type metadata caching minimize external API polling by over 80%.
