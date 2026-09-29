# CoinScan API Contract: Recognition & Valuation Engine

**Version:** 1.0.0  
**Protocol:** HTTPS / HTTP  
**Content-Type:** `multipart/form-data` or `application/json`

---

## 1. Overview

The CoinScan Recognition API accepts multi-sided coin photographic captures (Front, Reverse, and optional Edge), validates physical and visual image quality, extracts structured numismatic observations using multimodal Vision AI, cross-checks observations against the official Numista v3 catalogue, aggregates multi-signal evidence with contradiction scoring, and provides multi-tiered valuation and FX localization.

---

## 2. Endpoints

### 2.1 Health Check
`GET /health`

#### Response: `200 OK`
```json
{
  "status": "ok",
  "service": "coinscan-backend",
  "version": "1.0.0",
  "environment": "development",
  "providers": {
    "vision": "ready",
    "numista": "ready",
    "valuation": "ready",
    "fx": "ready"
  },
  "timestamp": "2026-08-26T10:30:00Z"
}
```

---

### 2.2 Coin Recognition
`POST /v1/recognition`

#### Request (Multipart Form Data):
| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `front_image` | `Binary File (JPEG/PNG/HEIC)` | **Yes** | High-resolution obverse capture (Max 20MB, Min 240x240px) |
| `reverse_image` | `Binary File (JPEG/PNG/HEIC)` | Optional | Reverse capture (strongly recommended for 2-sided die consistency) |
| `edge_image` | `Binary File (JPEG/PNG/HEIC)` | Optional | Edge rim capture for third-side collar/reed inspection |
| `preferred_currency` | `String` | Optional | Target 3-letter ISO currency code (Default: `USD`) |
| `locale` | `String` | Optional | Client language/locale (e.g. `en-US`, `es-ES`, `de-DE`) |
| `detected_text_hints` | `String` | Optional | Comma-delimited OCR tokens extracted client-side |

#### Response: `200 OK`
```json
{
  "status": "identified",
  "message": "High certainty match for 1 Dollar 'Morgan Dollar'. Obverse and reverse dies verified.",
  "candidates": [
    {
      "coinId": "numista_1492",
      "identity": {
        "country": "United States",
        "denomination": "1 Dollar",
        "currency": "USD",
        "year": 1882,
        "mint": "CC",
        "composition": "90% Silver, 10% Copper",
        "weightG": 26.73,
        "diameterMm": 38.1,
        "thicknessMm": 2.4,
        "edgeType": "Reeded",
        "kmNumber": "KM# 110",
        "numistaId": 1492
      },
      "providerName": "CoinScan Hybrid Engine",
      "confidence": {
        "level": "high",
        "overallScore": 0.94,
        "visualScore": 0.95,
        "ocrScore": 0.92,
        "metadataScore": 0.96,
        "explanation": "High certainty match for 1 Dollar 'Morgan Dollar'. Visual features, date, and denomination agree across both sides."
      },
      "evidence": [
        {
          "type": "visualSimilarity",
          "label": "Visual Motif Match",
          "detail": "Head of Liberty facing left, hair in Phrygian cap.",
          "strength": "strong",
          "score": 0.95,
          "source": "Vision AI Model"
        },
        {
          "type": "year",
          "label": "Date 1882",
          "detail": "Extracted year 1882 matches catalogue mintage span (1878–1921).",
          "strength": "strong",
          "score": 0.95,
          "source": "OCR Date Analysis"
        },
        {
          "type": "mintMark",
          "label": "Mint Mark 'CC'",
          "detail": "Mint mark 'CC' verified against Carson City production facilities.",
          "strength": "strong",
          "score": 0.92,
          "source": "Numista Issues Archive"
        },
        {
          "type": "obverseReverseAgreement",
          "label": "Two-Sided Agreement",
          "detail": "Front and reverse motifs correspond consistently to the same catalogue type.",
          "strength": "strong",
          "score": 0.95,
          "source": "Joint Multi-Side Analysis"
        }
      ],
      "rank": 1
    }
  ],
  "qualityReport": {
    "isAcceptable": true,
    "overallScore": 0.96,
    "issues": [],
    "warnings": [],
    "recommendedActions": []
  },
  "valuation": {
    "status": "available",
    "currencyCode": "USD",
    "estimates": [
      {
        "type": "metalValue",
        "currencyCode": "USD",
        "low": 24.62,
        "high": 25.62,
        "mid": 25.12,
        "valuedAt": "2026-08-26T10:30:00Z",
        "source": "Live Silver Spot (0.7734 oz ASW @ $32.50/oz)",
        "caveat": "Intrinsic bullion value based strictly on 90.0% fine silver content.",
        "confidenceScore": 0.98
      },
      {
        "type": "collectorValue",
        "currencyCode": "USD",
        "low": 300.0,
        "high": 480.0,
        "mid": 390.0,
        "valuedAt": "2026-08-26T10:30:00Z",
        "source": "Numismatic Catalogue & Auction Indices",
        "caveat": "Collector estimate for raw/circulated state. Condition, strike, and eye appeal create significant variance.",
        "confidenceScore": 0.85,
        "comparables": [
          {
            "source": "Heritage Auctions",
            "title": "1882-CC $1 Morgan Dollar MS64 NGC",
            "currencyCode": "USD",
            "price": 410.0,
            "observedAt": "2026-05-14T00:00:00Z",
            "gradeTier": "mintState"
          }
        ]
      }
    ],
    "valuationNotes": "Valuations are market estimates based on raw/circulated condition. Coins are not professionally certified.",
    "updatedAt": "2026-08-26T10:30:00Z"
  },
  "processingMetadata": {
    "latency_ms": 412,
    "provider": "gemini",
    "numista_attributed": true
  },
  "warnings": []
}
```

---

## 3. Error Responses

| HTTP Status | Error Message | Description |
| :--- | :--- | :--- |
| `413 Payload Too Large` | `Front image exceeds maximum upload size of 20MB.` | Upload exceeds `MAX_UPLOAD_MB`. |
| `429 Too Many Requests` | `Too many scan requests. Please wait a moment.` | IP sliding-window rate limit exceeded (60 req/min). |
| `500 Internal Server Error` | `An internal server error occurred.` | Safe generic message concealing internal traces. |
