# CoinScan Phase 8: Production Hosting Platform Evaluation & Decision

**Date:** 2026-08-27  
**Author:** Senior Staff Platform & Cloud Infrastructure Architect  
**Document Version:** 1.0.0  
**Status:** **ACTIVE / VERIFIED**

---

## 1. Hosting Architecture Comparison Matrix

| Evaluation Dimension | Google Cloud Run (Recommended) | Render (Web Service) | Fly.io (Apps) |
|---|---|---|---|
| **Platform Model** | Serverless Managed Containers (Knative) | Managed App Platform | Global Micro-VMs (Firecracker) |
| **Cold Starts** | **0 ms** with `min-instances=1` (~1.5s from zero) | ~50s on Free (Sleeps); ~0s on Paid ($7/mo+) | ~1-2s cold boot from 0 |
| **Minimum Instances** | Declarative (`--min-instances=1` prevents cold starts) | Paid plan ($7/mo standard) | `auto_stop_machines = false` |
| **Secret Management** | **Native Secret Manager integration** (`--set-secrets`) | Dashboard Environment Variables | `fly secrets set` CLI |
| **Global Regions** | 36+ Google Cloud regions (low latency globally) | 4 regions (US-East, US-West, EU-Central, Singapore) | 30+ regions |
| **Custom Domain & HTTPS** | Managed SSL + custom domain mapping (`api.coinscan.app`) | Managed SSL + CNAME | Managed SSL + Anycast IP |
| **DDoS & Network Security**| Google Cloud Armor & global Anycast edge | Cloudflare reverse proxy | Anycast edge proxy |
| **Horizontal Auto-scaling**| 0 to 1,000+ container instances in seconds | Auto-scaling on Pro plans ($25+/mo) | Metric-based auto-scaling |
| **Cost at Low Traffic** | ~$4 - $8 / month (with 1 warm CPU idle instance) | $7 / month (Starter plan) | ~$5 / month (Shared CPU VM) |
| **Cost at 50k Scans/Mo** | ~$15 - $25 / month | $25 / month | ~$20 / month |
| **CI/CD Integration** | `cloudbuild.yaml` automated build & deploy | Git push webhook / GitHub app | GitHub Actions (`flyctl deploy`) |

---

## 2. Platform Decision: Google Cloud Run

### 2.1 Key Justifications
1. **Zero Sleep / Low Latency for Mobile Scans:** Coin identification requires sub-2-second total latency. Render Free is strictly unacceptable because it sleeps after 15 minutes of inactivity and takes up to 50 seconds to wake. With Cloud Run configured with `min-instances=1`, container instances remain permanently warm and responsive.
2. **Enterprise Secret Isolation:** Google Cloud Run natively links secrets from Google Secret Manager directly to container environment variables at runtime without exposing them in git, build artifacts, or client source code.
3. **Colocation with AI APIs:** Google Cloud Run shares low-latency private Google backbone routing with Google Gemini APIs (`gemini-2.0-flash`), cutting external SSL handshake and network hops.
4. **Automated Zero-Downtime Traffic Splitting:** Supports canary deployments, instant rollbacks, and automated health check validations.

---

## 3. Production Deployment Topology & Specifications

```
+---------------------------------------------------------------------------------------------------+
|                                 PRODUCTION DEPLOYMENT TOPOLOGY                                    |
+---------------------------------------------------------------------------------------------------+

   DNS: api.coinscan.app
            │
            ▼
   Google Cloud Load Balancing / Google Cloud Armor (DDoS Protection + Managed SSL)
            │
            ▼
   Google Cloud Run Service (coinscan-backend)
   ├── Memory: 1024 MiB
   ├── CPU: 1 vCPU
   ├── Min Instances: 1 (warm standby)
   ├── Max Instances: 20
   ├── Concurrency: 80 requests / container
   ├── Timeout: 60 seconds
   ├── Non-root User: coinscan (UID 10001)
   └── Environment & Secrets (Injected from Secret Manager):
       ├── GEMINI_API_KEY (projects/$PROJECT_ID/secrets/GEMINI_API_KEY:latest)
       ├── NUMISTA_API_KEY (projects/$PROJECT_ID/secrets/NUMISTA_API_KEY:latest)
       ├── REVENUECAT_WEBHOOK_SECRET (projects/$PROJECT_ID/secrets/REVENUECAT_WEBHOOK_SECRET:latest)
       └── SUPABASE_JWT_SECRET (projects/$PROJECT_ID/secrets/SUPABASE_JWT_SECRET:latest)
```

---

## 4. Frontend Web Hosting: Vercel vs Netlify

| Criteria | Vercel (Recommended) | Netlify |
|---|---|---|
| **Flutter Web Support** | Static SPA deployment (`build/web` directory) | Static SPA deployment (`build/web` directory) |
| **Global CDN Performance**| Global Edge Network (sub-50ms TTFB worldwide) | High-performance Global CDN |
| **Custom Domain** | `coinscan.app` with automated SSL and Apex DNS | `coinscan.app` with automated SSL |
| **Preview Deployments** | Instant branch preview URLs for pull requests | Deploy previews for pull requests |
| **Cost** | Free hobby tier sufficient for web app & legal docs | Free tier |

**Decision:** Deploy Flutter Web build output (`build/web`) to **Vercel** with custom domain `coinscan.app`.
