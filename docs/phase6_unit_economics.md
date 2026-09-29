# CoinScan Phase 6: Unit Economics & API Cost Analysis

**Date:** 2026-08-26  
**Auditor:** Senior Principal Platform Engineer  
**Objective:** Accurate measurement and mathematical modeling of recognition cost per scan at scale to inform subscription pricing and infrastructure architecture.

---

## 1. Per-Scan Cost Breakdown (Primary Pipeline: Gemini 2.0 Flash)

### A. Multimodal Vision AI Inference
* **Image Input (Obverse + Reverse @ 1536px):** ~516 vision tokens.
* **System Prompt + Schema + OCR Context:** ~620 text tokens.
* **Total Input Tokens per Scan:** ~1,136 tokens.
* **Output Structured JSON Tokens:** ~320 tokens.
* **Pricing (Gemini 2.0 Flash):**
  - Input: $0.10 / 1,000,000 tokens ($0.00000010 / token)
  - Output: $0.40 / 1,000,000 tokens ($0.00000040 / token)
* **Cost per Scan (AI Inference):**
  $$\text{AI Cost} = (1136 \times 0.00000010) + (320 \times 0.00000040) = \$0.0001136 + \$0.0001280 = \mathbf{\$0.0002416\text{ USD}}$$

### B. Numismatic Catalogue Verification (Numista API v3)
* **Calls per Scan:** 1–2 cached asynchronous queries.
* **Cost:** Free tier / partner API agreement ($0 direct cost per query; backend proxy caching).

### C. Financial Feeds (Metals Spot & FX)
* **Precious Metals (GoldAPI / Metals-API):** Fixed $15–$30/month plan with 1-hour in-memory cache (744 queries/month max). Amortized cost at scale: **<$0.00002 / scan**.
* **Exchange Rates (ExchangeRate-API):** 4-hour cache. Amortized cost at scale: **<$0.00001 / scan**.

### D. Serverless Compute & Network (Google Cloud Run)
* **Execution Duration:** ~420ms average @ 1 vCPU / 1GB RAM ($0.000024/sec).
* **Cost per Execution:** $0.000010 USD.
* **Network Egress:** ~1.2KB JSON payload ($0.0000001 USD).

---

## 2. Total Cost Scale Projections

| Volume (Scans / Month) | Multimodal AI Cost | Infrastructure & Feeds | Total Monthly Cost | Cost per Completed Scan |
| :--- | :--- | :--- | :--- | :--- |
| **1,000** | $0.24 | $25.00 (base min instance) | $25.24 | $0.0252 |
| **10,000** | $2.42 | $27.50 | $29.92 | $0.00299 |
| **100,000** | $24.16 | $42.00 | $66.16 | **$0.00066** |
| **1,000,000** | $241.60 | $110.00 | $351.60 | **$0.00035** |

---

## 3. Subscription & Monetization Recommendations for Phase 7
* **User Profile:** Collectors scan an average of 15–40 coins/month.
* **Pro Tier Pricing Model:**
  - **Monthly:** $4.99 / month (Cost to serve: ~$0.015 $\to$ **99.7% Gross Margin**).
  - **Annual:** $39.99 / year ($3.33 / month $\to$ **99.5% Gross Margin**).
* **Free Tier Quota:** 3 free scans / month (Cost to acquire & activate user: < $0.001).
