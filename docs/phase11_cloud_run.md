# CoinScan Phase 11: Google Cloud Run Architecture & Production Sizing

**Date:** 2026-08-30  
**Author:** Principal Cloud Infrastructure & Platform Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Cloud Run Deployment Specification

```
+---------------------------------------------------------------------------------------------------+
|                                GOOGLE CLOUD RUN SERVERLESS TOPOLOGY                               |
+---------------------------------------------------------------------------------------------------+

                           +-------------------------------------+
                           | Custom Domain: api.coinscan.app     |
                           | Google Cloud Managed TLS 1.3        |
                           +------------------+------------------+
                                              |
                                              v
                           +-------------------------------------+
                           | Google Cloud Run Service            |
                           | Container: gcr.io/coinscan/backend  |
                           | • Base: python:3.11-slim            |
                           | • Non-Root User: appuser (UID 10001)|
                           | • Port: 8080                        |
                           | • Concurrency: 80 requests/instance |
                           | • Request Timeout: 30 seconds       |
                           +------------------+------------------+
                                              |
                     +------------------------+------------------------+
                     |                                                 |
                     v                                                 v
  +-------------------------------------+           +-------------------------------------+
  | Google Secret Manager               |           | Supabase / Cloud SQL                |
  | • GEMINI_API_KEY                    |           | PostgreSQL Database                 |
  | • SUPABASE_JWT_SECRET               |           | • Port: 5432 / Transaction Pooler   |
  | • REVENUECAT_WEBHOOK_SECRET         |           | • Strict Row Level Security (RLS)   |
  +-------------------------------------+           +-------------------------------------+
```

---

## 2. Cold-Start & Scaling Strategy

| Metric / Parameter | Staging / Development | Production (Initial Launch) | Production (Growth > 50k MAU) | Rationale |
|---|---|---|---|---|
| **Minimum Instances** | `0` | `1` | `2` | Guarantees instant sub-200ms response time during peak hours without cold starts. |
| **Maximum Instances** | `5` | `20` | `100` | Limits runaway billing during abnormal spikes while handling viral traffic. |
| **vCPU Allocation** | `1 vCPU` | `2 vCPU` | `2 vCPU` | Handles concurrent Pillow/OpenCV image normalization effortlessly. |
| **Memory Allocation** | `1 GiB` | `2 GiB` | `2 GiB` | Accommodates concurrent 10MB multi-sided image buffers in RAM. |
| **Request Concurrency** | `40` | `80` | `80` | High-throughput asynchronous I/O utilizing FastAPI + Uvicorn asyncio loop. |
| **Request Timeout** | `30s` | `15s` | `15s` | Enforces fast failover if upstream Vision AI or Numista stalls. |

---

## 3. Cost Tradeoff & Unit Economics

### Monthly Traffic Scenario (10,000 Active Users, 50,000 Scans/Day = 1.5M Scans/Month)

1. **Google Cloud Run (Compute & RAM):**
   - 1 baseline warm instance 24/7 = 720 hours @ $0.038/hr = ~$27.36/mo.
   - Dynamic scaling compute (1.5M requests @ 1.2s avg latency) = ~$18.20/mo.
   - **Total Cloud Run Compute:** **~$45.56 / month**
2. **Vision AI Inference (Google Gemini 2.0 Flash):**
   - Input: 2 normalized images (obverse + reverse) = ~1,200 tokens.
   - Output: ~250 tokens structured JSON.
   - Pricing: $0.10 / 1M input tokens + $0.40 / 1M output tokens = ~$0.00022 per scan.
   - 1.5M scans * $0.00022 = **~$330.00 / month**
3. **Supabase Database (Pro Plan):**
   - **$25.00 / month** (includes 8GB storage, daily backups, auth, and realtime).
4. **Total Monthly Infrastructure Cost:** **~$400.56 / month**

### Revenue Comparison:
- 10,000 users @ 5% paid conversion = 500 subscribers @ $4.99/mo = **$2,495 / month** (plus annual plans).
- **Gross Margin:** **~84%** even under conservative conversion assumptions.
