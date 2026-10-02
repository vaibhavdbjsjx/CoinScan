# CoinScan Recognition & Valuation Backend

Production-grade Python FastAPI backend providing:
- Image quality validation (blur, glare, resolution, brightness)
- Multi-sided coin analysis (Front + Reverse + Edge)
- Multimodal Vision AI extraction (OpenAI GPT-4o mini; Gemini kept as a legacy option)
- Numista API v3 catalogue verification & attribution
- Multi-signal evidence aggregation & contradiction scoring
- Live metal spot melt & collector valuation
- Multi-currency FX conversion with caching

## Security mode

`APP_ENV` alone decides how the API behaves — never the hosting platform:

| APP_ENV | Behaviour |
|---|---|
| `production`, `staging` | Hardened. Strict Supabase token verification, required settings checked at startup, `/health/ready` gates deploys, no API docs, no development aids. |
| `development`, `test` | Local only. Mock bearer tokens (`usr_…`, `dev_…`, `jwt_token_…`), mock vision provider, offline catalogue fixture, static dev API keys. |

**If `APP_ENV` is not set, the API runs as `production`.**

## Quick Start (Local Development)

All commands run from the repository root.

### 1. Setup Virtual Environment
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements-dev.txt
```

### 2. Configure Environment
```bash
cp backend/.env.example backend/.env
# backend/.env keeps APP_ENV=development for local work.
# Add OPENAI_API_KEY / NUMISTA_API_KEY for real recognition (optional for mock testing).
```

### 3. Run Server
```bash
uvicorn backend.app.main:app --host 127.0.0.1 --port 8080 --reload
```

### 4. Health Checks
```bash
curl http://127.0.0.1:8080/health/live    # process is up
curl http://127.0.0.1:8080/health/ready   # dependencies and configuration
```

### 5. API Documentation
In development, open `http://127.0.0.1:8080/docs`. Docs and the OpenAPI schema are disabled in staging and production.

### 6. Run Tests
```bash
pytest backend/tests
```
The test suite runs with `APP_ENV=test` and never uses `DATABASE_URL`. PostgreSQL integration tests run only when `TEST_POSTGRES_URL` points at a disposable PostgreSQL database.

## Deploying on Railway

`railway.toml` (repository root) configures the service: Docker build from `backend/Dockerfile`, deploy healthcheck on `/health/ready`, restart on failure, 30 s draining for in-flight scans.

The container binds `0.0.0.0:$PORT` (Railway injects `PORT`), runs one worker unless `WEB_CONCURRENCY` is set, and shuts down gracefully on SIGTERM.

Required variables (see `backend/.env.example` for all of them):

- `APP_ENV=production`
- `DATABASE_URL` — the Supabase **session pooler** URI (IPv4). Railway has no outbound IPv6, so the direct `db.<ref>.supabase.co` host cannot be used.
- `SUPABASE_URL` — token issuer and signing keys are derived from it.
- `SUPABASE_JWT_SECRET` — only while the Supabase project still issues legacy HS256 tokens.
- `SUPABASE_SECRET_KEY` (an `sb_secret_…` key; the legacy `SUPABASE_SERVICE_ROLE_KEY` is still accepted) — used only to delete the user's Supabase login on account deletion. Without it account deletion is refused and `/health/ready` stays 503.
- `OPENAI_API_KEY`, `NUMISTA_API_KEY`, `GUEST_QUOTA_HMAC_SECRET`, `REVENUECAT_WEBHOOK_SECRET`
- `CLIENT_IP_HEADER=X-Real-IP` — Railway's edge sets this header; confirm after the first deploy that it carries real client addresses (otherwise all guests would share one network allowance).

Without `DATABASE_URL` and Supabase token verification the service refuses to start; without the provider settings `/health/ready` stays 503, so Railway never routes traffic to a half-configured deployment.

Do not set `FORWARDED_ALLOW_IPS`; client addresses come only from `CLIENT_IP_HEADER` / `TRUSTED_PROXY_HOPS`.
