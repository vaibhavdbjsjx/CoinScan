# CoinScan Phase 4: Recognition & Numismatic Data Architecture

**Date:** 2026-08-26  
**Status:** Approved Architecture Foundation  
**Target:** Production iOS Mobile Application (CoinScan)

---

## 1. System Architecture Overview

CoinScan separates **Visual Evidence Generation** (AI / OCR / Preprocessing) from **Ground-Truth Numismatic Validation** (Catalogue Databases / Bullion Spot Feeds / Realized Auction Indices). 

```
                                 [ Mobile Client (iOS / Flutter) ]
                                                │
                                    1. Front + Reverse + Edge
                                    2. Local Quality Inspection
                                    3. On-Device OCR Signals
                                                ▼
                                    [ CoinScan Backend API ]
                                     (POST /v1/recognition)
                                                │
                      ┌─────────────────────────┼─────────────────────────┐
                      ▼                         ▼                         ▼
            [ Image Preprocessing ]     [ Multi-Script OCR ]    [ Multimodal Vision AI ]
             • Circular segmentation     • Latin / Arabic /      (Gemini Flash / 4o-mini)
             • Glare & blur scoring        Greek / Indic          • Visual design vectors
             • Perspective rectifying    • Date extraction        • Inscription extraction
                      │                         │                         │
                      └─────────────────────────┼─────────────────────────┘
                                                ▼
                                  [ Candidate Generation Engine ]
                                  • Semantic query compilation
                                  • Type & issuer identification
                                                │
                                                ▼
                                  [ Numismatic Catalogue Layer ]
                                   (Numista API v3 + Local Cache)
                                  • Precise KM# / N# resolution
                                  • Physical specs (weight/diameter)
                                  • Mintage & variety validation
                                                │
                                                ▼
                                 [ Multi-Signal Evidence Aggregator ]
                                  • Visual similarity (45%)
                                  • Inscription / Date OCR (30%)
                                  • Physical & mint metadata (25%)
                                  • Obverse/Reverse agreement
                                                │
                                                ▼
                                       [ Valuation Engine ]
                                  ┌─────────────┴─────────────┐
                                  ▼                           ▼
                        [ Live Metal Spot Feed ]     [ Market Comparables ]
                        • Fine silver/gold ASW        • Realized auction sales
                        • Melt value range            • Grade tier adjustments
                                  │                           │
                                  └─────────────┬─────────────┘
                                                ▼
                                    [ FX Conversion Engine ]
                                     (Hourly Caching Layer)
                                                │
                                                ▼
                                 [ Normalized JSON Response ]
                                                │
                                                ▼
                                   [ Mobile Client Rendering ]
                                  • Candidate rankings
                                  • Evidence explanation panel
                                  • Valuation range with caveats
```

---

## 2. Provider Research & Comparative Evaluation

| Provider / Model | Category | Image Search / Vision | Catalogue Depth | Speed / Latency | Pricing / Unit Cost | Commercial License Terms | Fit for CoinScan |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Numista API v3** | Specialized Catalogue | Yes (Paid tier) | 350,000+ types, 1.8M+ issues | 200–500 ms | Free: 2,000 req/mo. Paid: €100 setup + €100/mo min + per-request search fees | Commercial permitted with attribution (must show N# id). Bulk redistribution/reselling prohibited. | **Primary Catalogue & Type Authority** |
| **Google Gemini 1.5 Flash** | Multimodal LLM | Multimodal Token Vision | N/A (General knowledge) | 400–800 ms | ~$0.075 / 1M input tokens (~$0.00002–$0.0001 / image) | Commercial API permitted via Google AI Studio / Vertex AI | **Primary Visual Candidate Extractor** |
| **OpenAI GPT-4o mini** | Multimodal LLM | Multimodal Tiled Vision | N/A (General knowledge) | 500–900 ms | $0.15 / 1M input tokens (Tiled image cost: ~$0.001–$0.003 / image) | Commercial API permitted | **Secondary / Fallback Vision Extractor** |
| **PCGS Public API** | Grading Authority | No (Barcode/Cert only) | US & select world certified coins | 300–600 ms | Free 1,000 calls/day; higher tiers require dealer partner agreement | Strict OAuth; cannot be used as a public reverse-image search engine | **Future Slab / Cert Verification Only** |
| **Coinoscope** | Mobile App | Visual similarity | Broad world coins | N/A | **No public developer API** | N/A (Consumer app only) | **Rejected (No Public API)** |
| **Colnect API** | Collector Catalogue | Text search only | 150,000+ coins | 500–1200 ms | Partner approval required | Non-commercial focus; rate-limited | **Secondary Backup Catalogue** |
| **Custom ResNet / ViT Embeddings** | Proprietary ML | Vector cosine similarity | Custom indexed corpus | 50–150 ms | Hosting compute ($50–$200/mo on GPU instance) | Full IP ownership | **Future Phase 6 Optimization** |

---

## 3. Numista API Assessment & Integration Rules

### 3.1 Capabilities & Endpoints
- **Base URL:** `https://api.numista.com/v3`
- **Authentication:** `Numista-API-Key: <key>` header (Server-side only).
- **Key Endpoints:**
  - `GET /v3/types`: Text, issuer, category, year range query.
  - `GET /v3/types/{id}`: Detailed specifications (weight, diameter, thickness, composition, edge lettering, KM#, designer).
  - `GET /v3/types/{id}/issues`: Year-by-year mintage figures, mint marks, rarity index, and community market price indicators.
  - `POST /v3/types/search_by_image`: Image-based catalogue lookup (Paid tier only).

### 3.2 Licensing, Attribution & Data Storage Constraints
1. **Attribution:** Any data rendered from Numista must visibly acknowledge Numista and display the canonical `N#` identifier (e.g. `Numista N# 1492`).
2. **Bulk Redistribution Prohibition:** We **cannot** dump or mirror the Numista catalogue into a standalone public database or resell it as our own dataset.
3. **Caching:** Local caching for active session performance (e.g. 24–48 hours for coin specifications) is standard and compliant, but permanent offline replication of their entire database without partnership is strictly prohibited.
4. **Secret Isolation:** The Numista API key **must never** be compiled into the Flutter iOS app. All requests must route through our backend proxy.

---

## 4. OCR Strategy

### 4.1 On-Device (Apple Vision Framework)
- **Engine:** `VNRecognizeTextRequest` (`.accurate` mode with `usesLanguageCorrection = true`).
- **Target Extraction:** Dates (4-digit Gregorian years `1700–2026`), Roman numerals (`MDCCCCVII`), Arabic numerals, denomination tokens (`ONE DOLLAR`, `1 RUPEE`, `5 FRANCS`, `50 CENTS`), country names (`UNITED STATES`, `DEUTSCHES REICH`, `GEORGIVS V`).
- **Advantage:** Zero latency, zero cloud cost, instant user feedback if date is obscured.

### 4.2 Backend OCR Fallback
- **Engine:** Integrated multimodal vision prompt or specialized Tesseract/Cloud Vision OCR.
- **Role:** Handles non-Latin historical scripts (Ottoman Turkish, Persian, Arabic, Devanagari, Classical Greek, Cyrillic, Chinese dynasty seal scripts).
- **Architecture Role:** OCR is treated as **one weighted signal (30%)** in candidate scoring, not an absolute filter (preventing coin wear/damage from causing false negatives).

---

## 5. Confidence & Evidence Calculation Model

CoinScan does not display fake or arbitrary confidence numbers. Confidence is derived from a transparent multi-factor weighted equation:

$$\text{Overall Score} = (S_{\text{visual}} \times 0.45) + (S_{\text{ocr}} \times 0.30) + (S_{\text{metadata}} \times 0.25)$$

### 5.1 Component Definitions
1. **$S_{\text{visual}}$ (Visual Similarity - 45%):**
   - Obverse design match (bust, emblem, crest).
   - Reverse design match (coat of arms, wreath, denomination design).
   - Obverse/Reverse agreement (verifies that both sides correspond to the same historical issue).
2. **$S_{\text{ocr}}$ (Text & Inscription - 30%):**
   - Date verification (extracted year matches catalogue issue range).
   - Denomination match.
   - Legend/issuer match.
3. **$S_{\text{metadata}}$ (Physical & Mint Evidence - 25%):**
   - Mint mark identification (e.g., 'CC', 'O', 'S', 'D', 'None').
   - Edge description match (reeded vs lettered vs plain).
   - Geometry agreement (aspect ratio, circularity).

### 5.2 Confidence Tier Mapping
- **High Confidence ($\ge 85\%$):** Primary candidate strongly matches all visual, date, and mint attributes across both faces.
- **Medium Confidence ($60\% - 84\%$):** Coin type identified; minor variety or exact die state/mint mark requires verification.
- **Low Confidence ($35\% - 59\%$):** Multiple similar coin types exist; user prompted to capture clearer reverse or edge photo.
- **Indeterminate ($< 35\%$):** Insufficient evidence; triggers the **Unknown Coin Flow** with actionable recapture tips.

---

## 6. Valuation Architecture

CoinScan strictly prohibits single, fabricated price points. The valuation engine decomposes value into four real economic layers:

```
                                  [ Total Valuation Model ]
                                              │
         ┌──────────────────┬─────────────────┼──────────────────┐
         ▼                  ▼                 ▼                  ▼
    [ Face Value ]    [ Metal / Melt ]  [ Catalogue Guide ] [ Realized Market ]
    • Legal tender    • Live spot rate  • Numista / Krause  • Heritage Auctions
    • Nominal unit    • Pure ASW / AGW    condition index   • eBay Sold / PCGS
```

1. **Face Value:** Historical or circulating legal tender denomination (e.g., 1 USD, 50 Euro Cents).
2. **Metal / Melt Value:** $\text{Weight (grams)} \times \text{Purity (\%)} \times \text{Live Spot Price per gram}$. Updated via cached financial feeds (Metals-API / Goldprice).
3. **Catalogue Collector Guide:** Baseline historical collector indices stratified by Sheldon/European grade tiers (Good to Mint State).
4. **Realized Market Comparables:** Timestamped historical transactions from verified auction archives (Heritage, Stack's Bowers, GreatCollections) including grade caveats.

If no reliable pricing data is available for a rare or ancient coin, the engine explicitly returns:
`ValuationStatus.unavailable` with a transparent note rather than inventing a speculative figure.

---

## 7. Currency & FX Architecture

- **Engine:** `CurrencyRateService` with `InMemoryCachedCurrencyService` (mobile) and Redis-backed FX rates (backend).
- **TTL Strategy:** 4-hour caching for standard fiat currencies (USD, EUR, GBP, CAD, AUD, JPY, INR, CHF).
- **Offline Resilience:** If network is unavailable, the app uses the last known cached rate with a visual `cached at [timestamp]` indicator.

---

## 8. Backend Contract Specification (`POST /v1/recognition`)

### 8.1 Request Payload
```json
{
  "front_image_base64": "...",
  "reverse_image_base64": "...",
  "edge_image_base64": "...",
  "preferred_currency": "USD",
  "locale": "en-US",
  "client_metadata": {
    "app_version": "1.0.0",
    "device_model": "iPhone 15 Pro",
    "on_device_ocr_hints": {
      "detected_year": 1882,
      "detected_text": ["E PLURIBUS UNUM", "LIBERTY"]
    }
  }
}
```

### 8.2 Response Payload
```json
{
  "status": "identified",
  "message": "Coin identified with high confidence.",
  "quality_report": {
    "is_acceptable": true,
    "overall_score": 0.94,
    "issues": [],
    "warnings": []
  },
  "candidates": [
    {
      "coin_id": "us_morgan_dollar_1882_cc",
      "identity": {
        "country": "United States",
        "denomination": "$1",
        "currency": "USD",
        "year": 1882,
        "mint": "Carson City (CC)",
        "composition": "90% Silver, 10% Copper",
        "weight_g": 26.73,
        "diameter_mm": 38.1,
        "edge_type": "Reeded",
        "km_number": "KM# 110",
        "numista_id": 1492
      },
      "provider_name": "CoinScan Hybrid Vision Engine",
      "confidence": {
        "level": "high",
        "overall_score": 0.92,
        "visual_score": 0.94,
        "ocr_score": 0.90,
        "metadata_score": 0.92,
        "explanation": "Strong visual agreement with Carson City Morgan Dollar dies and clear 1882 obverse date."
      },
      "evidence": [
        {
          "type": "visualSimilarity",
          "label": "Obverse & Reverse Strike",
          "detail": "Design matches George T. Morgan Liberty head and heraldic eagle.",
          "strength": "strong",
          "score": 0.94
        },
        {
          "type": "year",
          "label": "Date 1882",
          "detail": "Confirmed via OCR on obverse lower rim.",
          "strength": "strong",
          "score": 0.98
        },
        {
          "type": "mintMark",
          "label": "CC Mint Mark",
          "detail": "Carson City CC mint mark visible below eagle wreath.",
          "strength": "strong",
          "score": 0.90
        }
      ],
      "rank": 1
    }
  ],
  "valuation": {
    "status": "available",
    "currency_code": "USD",
    "estimates": [
      {
        "type": "metalValue",
        "currency_code": "USD",
        "low": 24.50,
        "high": 25.10,
        "mid": 24.80,
        "source": "Live Spot Feed (0.7734 oz ASW @ $32.10/oz)",
        "caveat": "Melt value based on 90% silver content only.",
        "confidence_score": 0.99
      },
      {
        "type": "collectorValue",
        "currency_code": "USD",
        "low": 320.00,
        "high": 450.00,
        "mid": 385.00,
        "source": "Numismatic Catalogue & Auction Realized Indices",
        "caveat": "Estimated for standard uncirculated MS64 condition.",
        "confidence_score": 0.88
      }
    ]
  },
  "processing_metadata": {
    "server_duration_ms": 342,
    "pipeline_version": "v1.0"
  }
}
```

---

## 9. Backend Platform & Infrastructure Decision

### 9.1 Hosting: Google Cloud Run / Fly.io (Containerized Node.js or Python FastAPI)
- **Zero Cold-Start Provisioning:** Scale-to-min-1 instance in production ensures < 400ms request latency.
- **Compute:** 2 vCPU, 2GB RAM per worker node comfortably processes image buffers and concurrency.
- **Estimated Hosting Cost:** $15–$35 / month at initial production volume (10k–50k scans/month).

### 9.2 Database: Supabase / Managed PostgreSQL + pgvector
- **Stores:** User collections, scan history, user authentication, subscription entitlements, and cached numismatic metadata.
- **Privacy & Image Retention:** User-uploaded scan images in temporary memory are purged immediately after recognition unless explicitly saved by the user into their Collection Vault.

---

## 10. Estimated Per-Scan Cost Breakdown

| Component | Service Provider | Cost per 1,000 Scans | Cost per Single Scan |
| :--- | :--- | :--- | :--- |
| **Vision Candidate Extraction** | Google Gemini 1.5 Flash | $0.05 – $0.15 | **$0.00005 – $0.00015** |
| **Catalogue & Issue Verification** | Numista API v3 (Paid Tier) | $1.00 – $2.50 | **$0.00100 – $0.00250** |
| **Bullion Metal Spot Feed** | Metals-API / GoldAPI (Cached) | $0.05 | **$0.00005** |
| **Server Compute (Cloud Run)** | Google Cloud Run | $0.20 – $0.40 | **$0.00020 – $0.00040** |
| **Total Estimated Cost Per Scan** | | **$1.30 – $3.10** | **$0.0013 – $0.0031** |

*(At ~\$0.0025 per scan, a \$4.99/mo premium subscriber scanning 100 coins/month incurs only ~\$0.25 in API COGS, delivering a >94% gross margin).*
