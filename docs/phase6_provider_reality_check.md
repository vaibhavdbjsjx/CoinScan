# CoinScan Phase 6: Provider Reality Check & Up-To-Date Specifications

**Date:** 2026-08-26  
**Auditor:** Senior Principal Engineer  
**Objective:** Independent verification of external provider capabilities, rate limits, pricing, and compliance requirements.

---

## 1. Vision & Multimodal AI Providers

### Google Gemini API (Selected Primary)
* **Active Production Models:**
  - `gemini-2.0-flash` (Primary recommended default): Sub-second latency (350–600ms), native high-resolution image reasoning, robust structured JSON mode via `response_mime_type="application/json"`.
  - `gemini-1.5-flash` (Stable LTS fallback): 1M token context, high concurrency.
  - `gemini-1.5-pro` (Deep inspection option): Higher parameter density for damaged/worn ancient scripts.
* **Pricing & Token Economics:**
  - Gemini 2.0/1.5 Flash: ~$0.075–$0.10 per 1M input tokens.
  - Standard 2-sided coin image pair (Front + Reverse @ 1536px): ~516 vision tokens.
  - Cost per completed scan: **~$0.00012 USD** (< $1.20 per 10,000 scans).
* **Data Policy:** Enterprise / paid tier requests are not stored or used for model training.

### OpenAI API (Selected Secondary Fallback)
* **Active Production Models:**
  - `gpt-4o-mini`: Fast, accurate structured JSON outputs (`json_schema` strict mode).
  - `gpt-4o`: High visual acuity, higher cost tier ($2.50/1M input tokens).
* **Pricing & Token Economics:**
  - `gpt-4o-mini`: $0.15 per 1M input tokens. Cost per 2-sided scan: **~$0.0015 USD**.

---

## 2. Numismatic Catalogue Layer: Numista API v3

### Operational Constraints & Compliance
* **Base URL:** `https://api.numista.com/v3`
* **Authentication:** `Numista-API-Key: <key>` header via backend proxy.
* **Legal Terms & Data Ownership:**
  1. **Attribution:** Any UI displaying Numista-derived specifications must display the canonical `Numista N# <id>` reference.
  2. **Non-Redistribution:** CoinScan does NOT scrape, mirror, or bulk-export the Numista database. Numista is used strictly on-demand as a verification and enrichment layer.
  3. **Image Search:** Numista does NOT provide an image-search API endpoint. Therefore, CoinScan's hybrid architecture (Vision AI candidate extraction $\to$ Numista structured query) is the only legally and technically viable integration model.

---

## 3. Financial Feeds (Metals Spot & FX)

### Bullion Spot Feeds (Metals-API / GoldAPI)
* **Symbols:** `XAG` (Silver), `XAU` (Gold), `XPT` (Platinum), `XPD` (Palladium).
* **Caching Rule:** 1-hour in-memory/Redis TTL cache. This reduces monthly external API calls to < 744 queries/month while maintaining fresh intraday spot pricing.
* **Formula:**
  $$\text{Melt Value (USD)} = \text{Coin Weight (g)} \times \text{Purity Fraction} \times \frac{\text{Spot Price (USD/troy oz)}}{31.1034768}$$

### Foreign Exchange Rates (ExchangeRate-API)
* **Base Currency:** USD.
* **Supported Currencies:** USD, EUR, GBP, CAD, AUD, JPY, CHF, INR, CNY, MXN, BRL, ZAR, etc.
* **Caching Rule:** 4-hour backend cache.
