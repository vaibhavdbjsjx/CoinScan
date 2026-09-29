# CoinScan Provider & Architecture Decision Record (ADR)

**Date:** 2026-08-26  
**Status:** Approved  
**Decision Maker:** Antigravity Architecture Team

---

## 1. Selected Architecture: Hybrid Multi-Tier Pipeline

### Primary Stack:
1. **Visual Candidate Extraction:** Multimodal Vision Model (**Google Gemini 1.5 Flash** with **OpenAI GPT-4o mini** fallback).
2. **Ground-Truth Numismatic Authority:** **Numista API v3** (Type details, issue mintage figures, KM# numbers, composition & physical dimensions).
3. **On-Device OCR & Quality:** **Apple Vision Framework** (`VNRecognizeTextRequest`) on iOS + deterministic blur/resolution filters.
4. **Valuation Engine:** Composite engine (Metals-API spot prices + Numista catalogue grade indices + Realized auction comparables).

---

## 2. Rejected Alternatives & Detailed Rationale

### A. Standalone Multimodal Vision Model as Database (e.g. Asking ChatGPT/Gemini directly "What is this coin and what is it worth?")
- **Status:** **REJECTED**
- **Reasons:**
  1. **Hallucination of Fine Varieties & Mintage:** Multimodal LLMs frequently hallucinate mint marks (e.g. inventing a 'CC' mint mark on an un-mint-marked coin) and guess inaccurate mintage numbers.
  2. **Fabricated Valuations:** LLMs cannot reliably access real-time bullion spot prices or accurate auction realized records; they produce outdated, speculative, or flatly incorrect dollar numbers.
  3. **Lack of Structured Identifiers:** LLMs do not consistently output standardized catalogue numbers (KM#, Numista N#, PCGS#) needed for portfolio synchronization.

### B. Pure Numista "Search by Image" as Sole Recognition Engine
- **Status:** **REJECTED AS SOLE PROVIDER** (Retained as Secondary / Enrichment Layer)
- **Reasons:**
  1. **High Initial Cost & Ongoing Fees:** Requires €100 setup fee + €100/mo minimum commitment plus per-image search fees before testing accuracy at scale.
  2. **Black-Box Matching:** Does not return granular tokenized OCR text, segmented legend analysis, or multi-signal confidence reasoning (which CoinScan requires for transparent evidence presentation).
  3. **Multi-Step Advantage:** Using lightweight vision models to extract OCR/features and querying Numista's structured catalogue API yields higher accuracy and lower marginal cost than blind image search alone.

### C. Coinoscope API
- **Status:** **REJECTED**
- **Reasons:**
  1. **No Public API:** Coinoscope does not offer a public developer API or self-service commercial platform. It operates exclusively as a standalone consumer B2C application.

### D. PCGS Public API as Primary Recognition Engine
- **Status:** **REJECTED AS GENERAL RECOGNITION ENGINE** (Retained for future Slab/Cert verification)
- **Reasons:**
  1. **Coverage Limited to Graded Holders:** The PCGS Public API requires a PCGS Certification Number or Barcode; it does not perform raw image visual matching.
  2. **Quota Limits:** Restricted to 1,000 requests/day for standard developer accounts.

---

## 3. Comparison Matrix

| Factor | Standalone Vision LLM | Pure Numista Search-by-Image | **Selected Hybrid Multi-Tier** |
| :--- | :--- | :--- | :--- |
| **Identification Accuracy** | Moderate (Good macro, weak variety) | High (Standard world coins) | **Very High (Macro vision + catalogue validation)** |
| **Evidence Transparency** | Low (Generic text) | Low (Raw candidate list) | **High (Discrete visual, date, mint mark signals)** |
| **Cost per 1,000 Scans** | $0.15 – $0.50 | $2.50 – $5.00+ | **$1.30 – $3.10** |
| **Valuation Reliability** | Unreliable / Hallucinatory | Medium (Catalog index only) | **High (Separate face, spot melt, & auction comparables)** |
| **Offline Resilience** | None | None | **High (Cached specifications & offline on-device OCR)** |
| **Legal / License Compliance** | Full | Strict Attribution Required | **Full (Numista N# attributed, zero bulk copying)** |

---

## 4. Implementation Guidelines

1. **Client Isolation:** The Flutter mobile application communicates **only** with the CoinScan backend API (`POST /v1/recognition`). Zero API keys for Numista, Google AI, or Metals-API exist in client code.
2. **Truthful Fallbacks:** If evidence is weak or catalogue lookup returns no exact match, return `RecognitionStatus.unknown` or `RecognitionStatus.candidate` with user recapture guidance. Never synthesize a false high-confidence match.
3. **Attribution:** When rendering coin type details sourced from Numista, display the `Numista N#` badge with appropriate link/attribution.
