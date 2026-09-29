# CoinScan Phase 5: Provider Verification & Infrastructure Analysis

**Date:** 2026-08-26  
**Status:** Verified Against Official Documentation  
**Target:** Production Backend Integration

---

## 1. Vision & Multimodal AI Providers

### Primary: Google Gemini API (Gemini 2.0 Flash / Gemini 1.5 Flash)
- **Model Endpoints:** `gemini-2.0-flash`, `gemini-1.5-flash`
- **Capabilities:** High-throughput native multimodal vision, sub-second latency (350–700ms), 1M token context window, native Pydantic/Structured Output schema enforcement (`response_schema` / `response_mime_type="application/json"`).
- **Pricing:**
  - Gemini 1.5/2.0 Flash: ~$0.075–$0.10 per 1M input tokens.
  - Image token consumption: ~258 tokens per standard coin image crop.
  - Cost per 2-sided coin scan (Front + Reverse + prompt): **~$0.00008 – $0.00018** (less than $0.20 per 1,000 scans).
- **Privacy & Commercial Terms:** Paid tier requests are not used to train Google models. Commercial API usage is fully supported via Google AI Studio / Vertex AI.
- **Verdict:** **Selected as Primary Vision Provider.**

### Fallback: OpenAI API (GPT-4o mini)
- **Model Endpoint:** `gpt-4o-mini`
- **Capabilities:** Strong structured JSON schema output (`json_schema` strict mode), visual detail extraction.
- **Pricing:** $0.15 per 1M input tokens, with tiled image pricing (~$0.001–$0.002 per scan).
- **Verdict:** **Selected as Secondary / Redundant Provider.**

---

## 2. Numismatic Catalogue Layer: Numista API v3

### Endpoints & Operational Rules
- **Base URL:** `https://api.numista.com/v3`
- **Authentication:** `Numista-API-Key: <key>` header (Server-side proxy strictly required).
- **Key Endpoints:**
  - `GET /v3/types`: Search by issuer, category, denomination, and year.
  - `GET /v3/types/{id}`: Detailed physical specifications (weight, diameter, thickness, composition, edge type, KM# reference).
  - `GET /v3/types/{id}/issues`: Year-by-year mintage figures, mint marks, and rarity index.
- **Licensing & Attribution Compliance:**
  1. **Attribution Requirement:** Numista data must visibly display the canonical `N#` identifier (e.g. `Numista N# 1492`) and attribute Numista as the data source.
  2. **Bulk Redistribution Prohibition:** CoinScan cannot bulk download, mirror, or resell the Numista database.
  3. **Operational Architecture:** The CoinScan backend uses Numista strictly as an enrichment/verification layer for generated candidates.
- **Verdict:** **Selected as Authoritative Numismatic Catalogue.**

---

## 3. Financial & Spot Valuation Feeds

### Metals Spot Price Provider: Metals-API / GoldAPI
- **Capabilities:** Live real-time spot rates for Gold (XAU), Silver (XAG), Platinum (XPT), and Palladium (XPD).
- **Caching Strategy:** 1-hour in-memory/Redis TTL cache on the backend. A single cached spot quote satisfies thousands of scans, keeping external API calls below 750/month.
- **Valuation Formula:**
  $$\text{Melt Value} = \text{Pure Metal Weight (Troy Oz)} \times \text{Spot Price (USD/Oz)}$$
- **Verdict:** **Selected for Bullion & Intrinsic Metal Valuation.**

### FX Conversion: ExchangeRate-API / Open Exchange Rates
- **Capabilities:** Conversion between base USD and international collector currencies (EUR, GBP, CAD, AUD, JPY, CHF, INR, etc.).
- **Caching Strategy:** 4-hour backend cache with graceful stale-rate fallback.
- **Verdict:** **Selected for Multi-Currency Localization.**

---

## 4. Hosting Platform Evaluation

| Platform | Cold Start Characteristics | Concurrency Support | Baseline Monthly Cost | Production Suitability |
| :--- | :--- | :--- | :--- | :--- |
| **Google Cloud Run** | 100–300ms (near instant with `min-instances: 1`) | Up to 80 concurrent requests per container instance | $15–$35 / month | **Recommended for Production (High reliability, fast container startup, native Google Cloud VPC/Vertex integration)** |
| **Fly.io** | Fast global edge routing, 200–400ms cold start | Multi-region container instances | $10–$25 / month | **Strong Secondary Option** |
| **Render** | Free tier sleeps after 15m (50+ second cold start); Paid tier ($7/mo per service) | Standard single-instance | $7–$20 / month | **Acceptable for Dev/Staging only; Free tier unacceptable for production scan latency** |

---

## 5. Security & Isolation Summary

1. **Zero Client Secrets:** No API keys for Gemini, OpenAI, Numista, or Metals-API are ever compiled into or exposed by the Flutter iOS/Android binary.
2. **Backend Authentication:** The mobile client communicates with the backend via secure HTTPS (`POST /v1/recognition`) using application-level API token headers or user session JWTs.
3. **Data Protection:** Scan images uploaded to the backend are processed in memory and purged immediately unless explicitly saved by the user into their Collection Vault.
