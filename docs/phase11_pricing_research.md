# CoinScan Phase 11: Competitor Pricing & Worldwide Monetization Research

**Date:** 2026-08-30  
**Author:** Principal Product Strategist & Monetization Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Competitive Landscape Analysis

| Application | Weekly / Monthly Price | Annual Price | Free Tier Scans | Key Strengths | User Pain Points & Vulnerabilities |
|---|---|---|---|---|---|
| **CoinSnap** *(Market Leader)* | $4.99 / week (~$19.96/mo) | $29.99 / year | 1–2 scans then hard paywall | Polished UI, aggressive marketing | Deceptive weekly billing, hallucinated error coin valuations, poor support |
| **Coinoscope** | $1.99 / month | $14.99 / year | Free with heavy banner ads | Fast reverse-image search | Raw image search without true die verification or melt calculators |
| **PCGS CoinFacts** | Free (requires $25–$149/yr PCGS club for grading) | N/A | Reference only (no camera AI) | Authoritative census & auction data | No automated camera identification or multi-angle matching |
| **Numista Mobile Web** | Free (Ad-supported / Donations) | N/A | Catalogue lookup only | Comprehensive world coin database | No automated visual die alignment or automated grading |

---

## 2. CoinScan Value Proposition & Differentiation

1. **Two-Sided Die Consistency Verification:** Solves the single greatest flaw in single-shot apps (mules, counterfeit portrait mismatches, multi-denomination re-strikes).
2. **Transparent Multi-Signal Confidence:** Separates visual similarity, OCR inscription agreement, and Numista physical specifications.
3. **Honest Valuation Realism:** Strict separation of Face Value, Melt/Metal Value, and Auction Comps. Displays *"Insufficient market data"* rather than fabricating speculative prices.
4. **Transparent, Fair Billing:** Simple monthly/yearly subscriptions without deceptive weekly auto-renew traps.

---

## 3. Recommended Worldwide Tier Structure

```
+---------------------------------------------------------------------------------------------------+
|                                 COINSCAN PRODUCTION PRICING MODEL                                 |
+---------------------------------------------------------------------------------------------------+

1. FREE / EXPLORER TIER ($0.00)
   • 3 daily scans (UTC midnight reset)
   • Front + Reverse two-sided capture
   • Live precious metal melt calculations (Gold/Silver/Platinum)
   • Basic Numista catalogue identification
   • Local device scan history

2. COINSCAN PLUS
   • $4.99 USD / Month
   • $29.99 USD / Year ($2.50/mo — Save 50%)
   • 30 daily scans
   • Sheldon condition grade estimation (MS60–MS70, AU50, VF, etc.)
   • Multi-currency valuation converter (USD, EUR, GBP, JPY, CAD, AUD, INR)
   • Cloud Collection Vault (up to 250 items)

3. COINSCAN PRO
   • $9.99 USD / Month
   • $59.99 USD / Year ($5.00/mo — Save 50%)
   • Fair-use daily scans (150 scans/day)
   • Rare variety & mint mark detection (e.g. 1882-CC, 1909-S VDB)
   • Historical auction comparables (Heritage, Stacks Bowers, GreatCollections)
   • Unlimited Cloud Collection Vault items with custom notes & photos
   • CSV / PDF Collection Export for insurance & inventory
   • Priority Vision AI processing queue (< 1.5s latency target)
```

---

## 4. Product ID Registry for App Store Connect

- `com.coinscan.plus.monthly` — $4.99 Tier 5
- `com.coinscan.plus.yearly` — $29.99 Tier 30
- `com.coinscan.pro.monthly` — $9.99 Tier 10
- `com.coinscan.pro.yearly` — $59.99 Tier 60
