# CoinScan — Phase 3: Production Readiness Report

Date: 2 October 2026
Scope: repository only.

What was not done:
- Nothing was deployed, committed or pushed.
- No dashboards were opened.
- No credentials were changed.
- No migrations were applied to any real database.
- Google Cloud configuration (`cloudbuild.yaml`) is untouched. The repository contains no Render configuration files.

Baseline, verified at the start of this phase rather than taken from earlier reports:
- `flutter analyze`: clean.
- Flutter tests: 194/194.
- Backend tests: 475/475 with PostgreSQL.
- HEAD: `130ceb4`.

---

## A. Current production architecture

```
Flutter app (iOS / Android)  ─┐
Flutter web (Vercel)         ─┼─ HTTPS ─▶ Railway: FastAPI (Docker, 1 worker, 1 replica)
                              │              │   ├─ Supabase PostgreSQL (session pooler, TLS)
Supabase Auth (client SDK) ◀──┘              │   ├─ Supabase Auth: JWKS / legacy HS256 verify, Admin API (account deletion)
RevenueCat SDK (mobile) ─▶ App Store / Play  │   ├─ OpenAI Chat Completions (gpt-4o-mini) — vision
RevenueCat ── webhook ───────────────────────┘   ├─ Numista API — catalogue
                                                 └─ metals-api / open.er-api (optional)
```

- **Identity:** a Supabase user UUID. The same UUID is the RevenueCat `appUserID`, set via `Purchases.logIn` on every sign-in.
- **Subscription state:** the backend's paid tier comes **only** from RevenueCat webhooks, stored in `entitlements`. The app shows the RevenueCat SDK's entitlement and syncs its quota from `/v1/account/quota`.
- **Guests:** keyed HMAC counters in `guest_scan_usage`. Guests never create user rows.

---

## B. Railway readiness — READY (container image not built locally)

| Item | Status |
|---|---|
| `railway.toml` | Dockerfile builder; healthcheck `/health/ready` (120 s); restart on failure (5 retries); 15 s overlap; 30 s draining; watch patterns limited to the API. Verified by tests. |
| Build context | `.dockerignore` lets only `backend/requirements.txt` and `backend/app/` through, and excludes `**/.env*`. |
| **Dependency install** | **BUG FIXED (would have prevented start-up).** The builder ran `pip install --user` as root into `/root/.local` and copied it to `/home/coinscan/.local`. The runtime user's home is `/app`, so Python searches `/app/.local`, and `uvicorn` would have failed with `ModuleNotFoundError`. This dated from the initial commit. Fixed by installing into a virtualenv at `/opt/venv`, copied into the runtime image and put on `PATH`. Regression test added. |
| **Pinned dependencies** | **FIXED.** The previous `>=` ranges would have installed newer, untested versions on the container's Python 3.11 (e.g. Starlette 0.52 instead of the tested 0.49). `requirements.txt` now pins every package, direct and transitive (35 in total), to the exact versions the suite runs on. Verified: the whole set resolves to binary wheels for CPython 3.11 / linux x86_64 (`pip download --only-binary`). |
| Production-only dependencies | No test tools in `requirements.txt`; `pytest`/`aiosqlite` live only in `requirements-dev.txt`. Tested. |
| PORT | `--port ${PORT:-8080}`; Railway injects `PORT`. Verified by running the exact `CMD`. |
| Workers | `${WEB_CONCURRENCY:-1}`. **Keep 1 worker and 1 replica**: the per-minute rate limits and in-flight scan reservations live in process memory. With more processes the signed-in daily quota could be overrun by a few concurrent scans. Guest quota and webhook ordering are database-backed and safe. |
| Graceful shutdown | `exec` makes uvicorn PID 1. Verified: SIGTERM leads to "Shutting down … Application shutdown complete". Graceful 25 s is below Railway's 30 s draining. |
| Container security | Non-root `coinscan` user; `PYTHONDONTWRITEBYTECODE`; `--no-proxy-headers`; `--no-access-log` (uvicorn's access log records client IPs). |
| APP_ENV | Defaults to `production` (hardened). In staging/production, start-up is refused without `DATABASE_URL` and Supabase verification settings. |
| Logging | `LOG_LEVEL` now honoured (it was ignored). **Secret leak fixed** (see H1). |
| Image size | Slim base. Build tools live only in the builder stage. Runtime adds libjpeg, zlib and curl (curl for the Docker `HEALTHCHECK`). |

**Local container validation.** Docker is not installed on this machine, so **no image was built**. What was verified instead:
1. The pinned requirements installed into a fresh virtualenv (production set only).
2. The exact Dockerfile `CMD` was run three times:
   - **development:** live 200, ready 200, docs 200.
   - **production against a reachable but unmigrated database:** ready **503** `schema: missing`. Missing table names were logged and not returned.
   - **production against a fully migrated database:** ready **200**, every check `ok`; `/docs` and `/openapi.json` 404; CORS preflight 200 for the configured origin and 400 for others; a spoofed `X-Forwarded-For` was ignored; no secret value appeared in any log.

**Must still be verified on Railway:**
- the image actually builds;
- the container starts and the healthcheck passes;
- `X-Real-IP` behaviour (section D).

---

## C. Supabase readiness — READY (pending the manual migrations)

| Item | Status |
|---|---|
| Connection | asyncpg via the **session pooler** (IPv4; Railway has no outbound IPv6). TLS `require` by default in staging/production. Transaction-pooler (6543) detection disables prepared statements. Small pool (5+5). Phase 1 tests. |
| UUID handling | Identity is the verified token `sub`, which must be a UUID in production. **Fixed:** non-UUID collection item ids reached PostgreSQL `uuid` columns and returned 500. They are now 404 on delete; on create, a non-UUID id is replaced with a server-generated one. Tested on PostgreSQL. |
| JWT / JWKS / rotation | ES256/RS256 via JWKS with a rotation refetch, plus legacy HS256. Rejects expired tokens, service-role/anon tokens, anonymous sessions, wrong issuer/audience and `alg=none` (Phase 2, 28 tests). |
| User deletion | Admin API first (`sb_secret_` or legacy key). On failure, nothing is deleted. Cascades from `auth.users` (Phase 2, tested on PostgreSQL). |
| RLS assumptions | The backend connects as the table owner (`postgres` via the pooler), so RLS doesn't restrict it. Client policies let users read their own rows and write only their own profile, collection and scan history. **No policy lets a client change entitlements or quota.** `guest_scan_usage` has no client access (REVOKE + RLS). |
| Required tables / indexes / constraints / FKs / cascades | The 13 ORM tables match the 13 migration tables exactly. Every user table cascades from `public.users`, which cascades from `auth.users`. Indexes exist for every hot lookup, including `subscription_events(app_user_id)`, which the new ordering check uses. |
| **Readiness checks the schema** | **ADDED.** `/health/ready` now reports `schema: missing` (503) when any table is absent, so a deployment with forgotten migrations never goes live. |

No new migration was needed in Phase 3; the RevenueCat fix uses existing tables.

---

## D. Guest scanning readiness — READY (one post-deploy verification)

Flow:
1. Request.
2. Client address: `CLIENT_IP_HEADER`, else `TRUSTED_PROXY_HOPS`, else the TCP peer. A missing, repeated or malformed header falls back to the peer.
3. Install ID: must be a UUID, otherwise ignored.
4. HMAC-SHA256 with `GUEST_QUOTA_HMAC_SECRET`. Missing in production: guests get 503 and readiness reports 503.
5. Per-minute rate limit.
6. **Atomic** reservation: a conditional upsert per install and per network (IPv6 grouped per /64), on the UTC day.
7. Recognition.
8. Commit on success; **release** on every failure path.
9. PostgreSQL stores hashes only.

All verified by tests:
- no raw IPs or install IDs stored or logged;
- no fake UUIDs and no rows in user tables;
- failed scans release their slot;
- 12 concurrent reservations give exactly 2 successes;
- IPv4 and IPv6 both work;
- spoofed `X-Forwarded-For`, `Forwarded` and `True-Client-IP` are ignored;
- the 2-scans-per-day product decision is unchanged.

**Post-deploy check.** Railway documents `X-Real-IP` as the client address. **It is not verified** that Railway overwrites a client-supplied `X-Real-IP` (test in section M).

If `CLIENT_IP_HEADER` is wrong or unset, every request appears to come from Railway's proxy:
- all guests share **one** 2-scan allowance;
- signed-out and Free users share **one** 60-per-minute limit.

That fails safe, but it is effectively an outage, so verify it right after deploying.

---

## E. RevenueCat readiness — READY after one fix (RevenueCat stays; nothing added)

**Audited and correct:**
- **Entitlement IDs** `pro` and `plus`, and **product IDs** `com.coinscan.{plus,pro}.{monthly,yearly}`, are identical in the app and backend. Matching is exact; Google `:base-plan` suffixes are handled.
- **Purchase and restore** require a signed-in account whose RevenueCat identity equals the Supabase UUID. Offerings come from the store, so no hard-coded prices reach the paywall. The hard-coded list belongs to `DevSubscriptionService`, which only tests use.
- **Login and logout:** `Purchases.logIn(uuid)` and `Purchases.logOut()` are wired to auth changes. Aliases are resolved to the Supabase UUID.
- **Webhook authentication:** fails closed, uses constant-time comparison, and accepts `Bearer <secret>` or `<secret>`.
- **Event handling:**

| Event | Handling |
|---|---|
| INITIAL_PURCHASE / RENEWAL | Grant with expiry. |
| CANCELLATION | Keeps access until expiry. A refund (`CUSTOMER_SUPPORT`) or a past expiry revokes now. |
| EXPIRATION | Revokes, except when stale or for a lower tier. |
| BILLING_ISSUE | Grace period kept. |
| REFUND_REVERSED | Restores. |
| TRANSFER | Moves the entitlement. |
| PRODUCT_CHANGE | Informational; the tier changes on the next RENEWAL. |
| Unknown products | Never downgrade. |
| Duplicates | Idempotent. |
| Persistence failure | 500, so RevenueCat retries. |

- **Expiry is enforced whenever the tier is read.**

**BUG FIXED — out-of-order protection was memory-only.**
- After a restart or redeploy, or on another worker, an older event delivered late (including a RevenueCat retry) could overwrite newer state. Examples:
  - a late RENEWAL arriving after a **refund** restored paid access;
  - a late refund from an earlier period revoked a renewed subscription.
- Now, before applying any state-changing event, the handler also checks the newest event already recorded for that subscriber in `subscription_events`. If that history can't be read, the webhook returns 500 and RevenueCat retries.
- 4 PostgreSQL tests simulate a restart between deliveries. Both bug scenarios fail with the old code and pass with the fix.
- Also fixed:
  - only a foreign-key violation is treated as "no such user"; any other database error is now retried instead of silently dropping the entitlement;
  - database exception text, which can include SQL parameters, is no longer logged.

**Known limitations (not bugs):**
- **The backend tier depends entirely on webhook delivery.** There's no server-side call to RevenueCat's REST API. If the webhook isn't configured, paying users stay Free on the backend.
- **SANDBOX events are applied in production.** This is needed for App Review and TestFlight.

---

## F. OpenAI readiness — READY

- **Key handling:** the key is sent only in the `Authorization` header. Errors are sanitised and never contain the URL, headers or key (tests).
- **Timeout and retries:** 15 s timeout; no automatic retry. A failed scan releases the quota and tells the user it wasn't counted.
- **Malformed responses:** fenced, partial or invalid JSON becomes a low-confidence result rather than a crash (tests).
- **Image limits:** oversized uploads are refused before any quota is reserved; a decompression bomb gets 413.
- **Image formats:** images are decoded server-side and re-encoded to JPEG (≤1536 px, RGB) before going to OpenAI. HEIC can't be decoded server-side and is reported as unreadable, with the quota released.
- **Logging:** prompts, images and responses are never logged.
- **Change made — output-token cap.** `max_completion_tokens: 1500` was added. JSON mode can otherwise run on until the model's limit, at cost. The expected output is a few hundred tokens, so this never binds normally. Prompt, images, parsing and confidence logic are unchanged.
- **Change made — provider selection.** `VISION_PROVIDER` is now normalised and validated; an unknown value refuses start-up. Previously readiness lower-cased it but selection didn't, so `OpenAI` would pass the healthcheck and then fail every scan with 503.
- **Gemini** is used only if `VISION_PROVIDER=gemini` *and* `GEMINI_API_KEY` are both set. Production start-up now logs a warning if Gemini is selected, or if an unused `GEMINI_API_KEY` is present. The mock provider can't run in staging or production (tested).
- **Retention:** Chat Completions doesn't store outputs unless `store: true`, which isn't sent. The app's legal text still claims Gemini zero retention (Phase 2 list); the wording was not changed.

---

## G. Flutter production readiness

| Item | Status |
|---|---|
| Build-time variables | Only public values: `APP_ENV`, `BACKEND_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` (anon or `sb_publishable_`), RevenueCat public keys, and `LEGAL_*`. No server secret is referenced anywhere in `lib/` or `web/`. |
| Web release build | Built with placeholder values and **13 fake server secrets planted** in the build environment: **none** reached `build/web`, and the build's own scan passed. Two localhost literals are compiled in from fallback code used only when configuration isn't initialised. |
| Mocks / fake data | `DevSubscriptionService` (hard-coded prices) is test-only. `MockApi` supplies only static educational "lessons". Debug RevenueCat logging is `kDebugMode`-only. No token is printed. |
| **Android HEIC** | **FIXED.** Without a size limit, `image_picker_android` returns the original HEIC file, which the Dart decoder can't read, so gallery scans failed. The gallery picker now sets `maxWidth`/`maxHeight` 4096, so Android re-encodes to JPEG. iOS already converts HEIC to JPEG (verified in `image_picker_ios` 0.8.13+6). |
| Permissions | iOS camera and photo-library descriptions are present. The camera uses `enableAudio: false`, so no microphone permission is needed. Android declares CAMERA, INTERNET, and READ_EXTERNAL_STORAGE (≤ API 32). |
| Release-mode configuration | `APP_ENV` defaults to `development` (localhost backend) **unless passed**. A production build without `BACKEND_URL` falls back to `https://api.coinscan.app`. **Confirm you own that domain, or always pass `BACKEND_URL`.** |
| Bundle IDs | iOS `com.coinvault.coinvaultAi`, Android `com.coinvault.coinvault_ai`. Must match App Store Connect, Play Console and the RevenueCat apps. |
| iOS build | **Not run.** The Xcode licence isn't accepted on this machine, and I didn't change system configuration. |
| Android release build | **Not run.** `android/key.properties` points at your real upload keystore, and I won't use your signing credentials. The release build type refuses debug signing (good). |

---

## H. Security findings (Phase 3)

| # | Severity | Finding | Status |
|---|---|---|---|
| H1 | **High** | httpx logs every request URL at INFO. metals-api takes its key as `?access_key=`, so `METALS_API_KEY` would be written to Railway logs on every spot-price fetch (reproduced). | **Fixed:** `httpx`/`httpcore` loggers set to WARNING. Regression test. |
| H2 | **High** | Dockerfile dependency path: the server would not start. | **Fixed** (B). |
| H3 | **High** | RevenueCat ordering lost on restart: refunds could be undone, and renewals revoked. | **Fixed** (E). |
| H4 | Medium | Unpinned dependencies: untested versions in production. | **Fixed** (B). |
| H5 | Medium | `/health/ready` passed without migrated tables. | **Fixed** (C). |
| H6 | Medium | `VISION_PROVIDER` case mismatch: every scan returned 503. | **Fixed** (F). |
| H7 | Medium | Non-UUID collection ids caused 500s. | **Fixed** (C). |
| H8 | Low | `RATE_LIMIT_PER_MINUTE` was ignored, and the rate-limiter memory grew with every client address and user ever seen. | **Fixed:** setting honoured; idle entries swept. |
| H9 | Low | Webhook database errors logged SQL parameters. | **Fixed.** |
| H10 | Low | SQL echo, which logs parameters, could be turned on in production via `LOG_LEVEL=debug`. | **Fixed:** development only. |
| H11 | Low | An `ALLOWED_ORIGINS` entry with a trailing slash never matched. | **Fixed:** normalised. Start-up warns about wildcard or non-https origins. |

Checked with no issue found:
- authentication bypass and dev tokens (production gives 401);
- anonymous access to account endpoints (401);
- IDOR (every query is scoped to the verified identity; no endpoint accepts a user id);
- admin endpoints (none);
- API docs (disabled in staging/production, verified);
- CORS credentials (never combined with `*`; preflight verified);
- oversized and malformed images (413/422 before decoding);
- logging of IPs, authorization headers, API keys and prompts (none);
- SQL injection (ORM bind parameters only);
- path traversal (no file system writes; ids are UUID-validated);
- SSRF (all outbound URLs come from configuration, never from requests);
- webhook replay (idempotent by event id) and out-of-order delivery (H3).

**Secret sweep** (patterns: OpenAI, Supabase secret/publishable, JWTs, Google, private keys, DB URLs with passwords, RevenueCat, GitHub, Slack, Stripe, AWS, bearer tokens, generic assignments):
- tracked and untracked files outside tests: **0 hits**;
- test files: only sentinel or fake values;
- **git history, all refs: 0 hits**;
- `.env` files in the repository: only the two `.env.example` templates, both placeholders.

---

## I. Environment-variable matrix (backend)

### REQUIRED PRODUCTION (Railway)
| Variable | Notes |
|---|---|
| `APP_ENV=production` | Unset also means production. |
| `DATABASE_URL` | Supabase **session pooler** URI (port 5432). Not the direct host (IPv6). |
| `SUPABASE_URL` | Issuer and JWKS URL are derived from it. |
| `SUPABASE_SECRET_KEY` | `sb_secret_…`; account deletion only. Alternative: legacy `SUPABASE_SERVICE_ROLE_KEY`. |
| `SUPABASE_JWT_SECRET` | **Only if** the project still signs with the legacy HS256 secret. |
| `OPENAI_API_KEY` | |
| `NUMISTA_API_KEY` | |
| `GUEST_QUOTA_HMAC_SECRET` | 32+ random characters. |
| `REVENUECAT_WEBHOOK_SECRET` | Must equal the Authorization value configured in RevenueCat. |
| `CLIENT_IP_HEADER=X-Real-IP` | Verify after deploying (D). |
| `ALLOWED_ORIGINS` | The web app's https origin(s), once chosen. Until then `*` works (no credentials) and logs a warning. |

### OPTIONAL PRODUCTION
- **Keys:** `METALS_API_KEY`, `EXCHANGERATE_API_KEY`.
- **Supabase JWT overrides:** `SUPABASE_JWKS_URL`, `SUPABASE_JWKS_CACHE_SECONDS`, `SUPABASE_JWT_AUDIENCE`, `SUPABASE_JWT_ISSUER`, `SUPABASE_JWT_PUBLIC_KEY`, `SUPABASE_JWT_ALGORITHM`.
- **Vision:** `VISION_PROVIDER` (`openai`, the default), `OPENAI_MODEL`.
- **Logging and rate limits:** `LOG_LEVEL`, `RATE_LIMIT_PER_MINUTE`.
- **Guest limits:** `GUEST_DAILY_SCAN_LIMIT` (2), `GUEST_NETWORK_DAILY_SCAN_LIMIT` (20).
- **Proxy:** `TRUSTED_PROXY_HOPS` (keep 0).
- **RevenueCat ids:** `REVENUECAT_{PRO,PLUS}_{ENTITLEMENT,PRODUCT}_IDS` (defaults match the app).
- **Legal versions:** `REQUIRED_TERMS_VERSION`, `REQUIRED_PRIVACY_VERSION`.
- **Database:** `DB_POOL_SIZE`, `DB_MAX_OVERFLOW`, `DB_*_TIMEOUT_SECONDS`, `DB_POOL_RECYCLE_SECONDS`, `DB_SSL_MODE`, `DB_TRANSACTION_POOLER`.
- **Upload and request limits:** `MAX_UPLOAD_MB`, `MAX_IMAGE_PIXELS`, `MAX_IMAGE_DIMENSION`, `MIN_IMAGE_DIMENSION`, `MAX_RECOGNITION_REQUEST_MB`, `MAX_REQUEST_KB`, `READINESS_TIMEOUT_SECONDS`.
- **Container:** `GRACEFUL_SHUTDOWN_SECONDS`, `WEB_CONCURRENCY` (**must stay 1**).
- **Provider endpoints:** `*_BASE_URL`.

### LOCAL DEVELOPMENT ONLY (ignored, with a warning, in staging/production)
- `APP_ENV=development`
- `API_SECRET`
- `API_KEYS_JSON`
- `NUMISTA_OFFLINE_FIXTURE`

### TEST ONLY
- `APP_ENV=test` (set by `conftest.py`)
- `TEST_POSTGRES_URL` (disposable PostgreSQL)

### DEPRECATED / SHOULD NEVER BE SET on Railway
- `GEMINI_API_KEY`, `GEMINI_MODEL`, `VISION_PROVIDER=gemini` (legacy).
- `SENTRY_DSN`, `CLOUD_RUN_SERVICE_URL`, `REQUEST_TIMEOUT_SECONDS`, `HOST` (not read by the code).
- `PORT` (Railway injects it).
- `FORWARDED_ALLOW_IPS` (proxy headers are disabled).
- `SUPABASE_SERVICE_ROLE_KEY` once `SUPABASE_SECRET_KEY` is set; Supabase retires legacy keys by the end of 2026.

### Flutter / Vercel (public, build-time)
- `APP_ENV`
- `BACKEND_URL`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `REVENUECAT_APPLE_KEY` / `REVENUECAT_GOOGLE_KEY` (mobile only)
- `LEGAL_*` (not yet passed by `tool/vercel_build.sh`)

---

## J. Database migration order (run manually in the Supabase SQL editor — NOT applied anywhere)

1. **Check what exists (read-only).** Apply only the files whose tables are missing. **The first two files are not safe to re-run** (`CREATE POLICY` has no `IF NOT EXISTS`).
   ```sql
   SELECT table_name FROM information_schema.tables
   WHERE table_schema = 'public' ORDER BY table_name;
   ```
2. `backend/migrations/20260830_phase11_production_schema.sql`
   - Creates enums and 11 tables, with RLS and owner-only policies.
   - Requires Supabase's `auth.users`.
   - Uses `uuid-ossp` and `pgcrypto`, which are preinstalled on Supabase.
3. `backend/migrations/20260925_user_legal_consents.sql`: `user_legal_consents` plus RLS.
4. `backend/migrations/20260930_guest_scan_usage.sql`
   - Guest counters with CHECK constraints, RLS and a guarded REVOKE.
   - Safe to re-run.
   - Exact SQL is in the Phase 2 report, section 8.
5. **Verify:**
   ```sql
   SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'
     AND table_name IN ('users','entitlements','subscriptions','subscription_events','scan_usage',
       'scan_history','collection_items','api_keys','api_key_usage','feedback','security_events',
       'user_legal_consents','guest_scan_usage');                                  -- expect 13
   SELECT has_table_privilege('anon','public.guest_scan_usage','SELECT');          -- expect false
   ```

After deploying, `/health/ready` shows `"schema":"ok"` only when all 13 tables exist.

---

## K. Remaining blockers

**Before the first Railway deployment:**
1. Migrations applied (J).
2. Required Railway variables set (I).
3. The Supabase admin key: an existing legacy key, or a newly created `sb_secret_` key. Creating a key doesn't rotate anything.

**Must be verified immediately after deploying:**
- `X-Real-IP` overwriting (D);
- the RevenueCat webhook configured and delivering.

**Before public launch:**
- legal and privacy text (Gemini and zero-retention claims; Phase 2 list);
- `LEGAL_*` values in the web build;
- Supabase custom SMTP (the default allows 2 emails per hour);
- mobile builds with `APP_ENV=production` and `BACKEND_URL`;
- confirm ownership of `api.coinscan.app`, or always pass `BACKEND_URL`;
- bundle IDs, products and entitlements match App Store Connect, Play Console and RevenueCat;
- iOS: consider adding `ITSAppUsesNonExemptEncryption`;
- an iOS build check once the Xcode licence is accepted.

---

## L. Exact manual actions for you (later; none done)

1. **Supabase Dashboard (read-only first):**
   - Is the project on the legacy JWT secret or on signing keys?
   - Which tables exist (J, step 1)?
2. **Supabase:**
   - apply the missing migrations in order (J);
   - choose the admin key (legacy `service_role`, or create a secret key);
   - configure custom SMTP before launch.
3. **Railway:**
   - create the service from this repository (`railway.toml` is picked up);
   - set the variables in (I);
   - keep 1 replica;
   - leave the start command empty (the Dockerfile `CMD` is used);
   - generate the public domain.
4. **RevenueCat Dashboard → Integrations → Webhooks:**
   - URL: `https://<railway-domain>/v1/webhooks/revenuecat`;
   - Authorization header value: the same value as `REVENUECAT_WEBHOOK_SECRET`.
5. **Vercel, once the API domain exists:** `BACKEND_URL` set to the Railway URL; then set `ALLOWED_ORIGINS` on Railway to the Vercel origin.
6. **App stores and RevenueCat:** confirm bundle IDs, product IDs and entitlement IDs (`pro`, `plus`).

---

## M. First Railway deployment sequence

1. You approve; then commit and push this work.
2. **Supabase:** run steps J1–J5.
3. **Railway:**
   - create the service;
   - set the variables;
   - deploy;
   - watch the build. The image is built for the first time here.
4. **Healthcheck:** Railway waits for `/health/ready` to return 200. If it stays 503, the response's `checks` show which part is missing (database, schema, auth, vision, catalogue, guest_quota, revenuecat_webhook or account_deletion), and the logs name the missing setting or table.
5. **Check the logs:**
   - "Starting in production mode";
   - CORS and Gemini warnings, if any;
   - no `CLIENT_IP_HEADER … missing` warning when real traffic arrives.
6. **Smoke tests:**
   - `GET /health/live` returns 200;
   - `GET /health/ready` returns all `ok`;
   - `GET /docs` returns 404.
7. **Client IP check (D):**
   - `GET /v1/guest/quota` with `-H "X-Real-IP: 192.0.2.1"`;
   - do one guest scan;
   - repeat with `192.0.2.2`.
   - If the second shows a fresh allowance, Railway passes the client's header through: **unset `CLIENT_IP_HEADER`** and report back.
8. **Signed in:** with a real test account, do one scan; check `/v1/account/quota`; delete a **throwaway** account and confirm it's gone from Supabase Auth → Users.
9. **RevenueCat:**
   - send a **test webhook** from the dashboard; expect 200 `test_event_acknowledged`;
   - make one sandbox purchase; an `entitlements` row should show `pro` or `plus`.
10. **Web:** point Vercel `BACKEND_URL` at Railway, set `ALLOWED_ORIGINS`, and redeploy both.

---

## N. Rollback plan

- **Bad deployment:** a failing healthcheck never goes live; the previous deployment keeps serving. For a deployment that is live but misbehaving, use Railway → Deployments → previous deployment → **Rollback**.
- **Bad variable:** revert it in Railway, which redeploys.
- **Database:** all three migrations are additive (new tables and policies only); the app never alters or deletes existing data. Rollback isn't needed. If ever required: `DROP TABLE public.guest_scan_usage;` (guest counters only).
- **RevenueCat:**
  - events are idempotent;
  - RevenueCat retries failed deliveries;
  - after an outage, use "resend" in the dashboard;
  - ordering protection prevents stale overwrites.
- **Fallback hosting:** Google Cloud configuration (`cloudbuild.yaml`) is preserved unchanged. It still targets Gemini, so it isn't a like-for-like fallback.

---

## O. Final test results

| Suite | Before Phase 3 | After Phase 3 |
|---|---|---|
| Backend pytest **with PostgreSQL** | 475 passed | **507 passed**, 0 skipped |
| Backend pytest without PostgreSQL | — | 448 passed, 59 skipped (PostgreSQL tests) |
| `flutter analyze` | clean | **clean** |
| `flutter test` | 194/194 | **194/194** |
| Web release build + bundle scan | — | built; 13 planted secrets, **0** in the bundle |
| Container command (pinned production venv) | — | dev / unmigrated / migrated / SIGTERM scenarios as expected (B) |
| Linux 3.11 wheel resolution | — | all 35 pins resolve |
| Docker image build | — | **not possible locally** (Docker not installed) |
| iOS / Android release builds | — | **not run** (Xcode licence; real signing keystore) |

New tests: `test_production_hardening.py` (24), `test_postgres_revenuecat.py` (4), plus 2 deployment, 1 readiness and 1 PostgreSQL collection test.

The only pre-existing warning is `InsecureKeyLengthWarning` in `test_jwt_verification` (a deliberately short test key).

Existing tests changed because behaviour was intentionally tightened:
- `test_health_readiness.py`: new `schema` check; the real-database test now uses a migrated database.
- `test_deployment_files.py`: `SUPABASE_SECRET_KEY` added to the list of server secrets.

Nothing was weakened or deleted.

---

## Change control

**Modified (16):**

| File | Why |
|---|---|
| `backend/Dockerfile` | virtualenv install (start-up bug) |
| `backend/requirements.txt` | full pin of tested versions |
| `backend/app/main.py` | `LOG_LEVEL`; httpx URL-logging leak; CORS parsing |
| `backend/app/runtime_checks.py` | schema readiness; CORS and Gemini start-up warnings |
| `backend/app/db/session.py` | `check_schema`; SQL echo development-only |
| `backend/app/config.py` | `VISION_PROVIDER` validation |
| `backend/app/api/webhooks.py` | database-backed ordering; FK handling; safe logging |
| `backend/app/api/collection.py`, `backend/app/api/account.py` | UUID-validated item ids |
| `backend/app/security/rate_limit.py` | setting honoured; memory sweep |
| `backend/app/services/recognition/vision_provider.py` | OpenAI output-token cap |
| `backend/.env.example` | unused and now-wired settings documented |
| `lib/features/scan/scan_screen.dart` | Android HEIC gallery fix |
| Tests | `test_deployment_files.py`, `test_health_readiness.py`, `test_postgres_guest_integration.py` |

**Added (3):**
- `backend/tests/test_production_hardening.py`
- `backend/tests/test_postgres_revenuecat.py`
- this report

**Confirmations:**
- No other files changed (hash comparison against the start-of-phase snapshot).
- No files outside the repository changed, except temporary tooling in the session scratchpad: a virtualenv, a disposable local PostgreSQL and scripts.
- No credentials changed or used.
- No deployments.
- No remote migrations.
- No commits (HEAD is still `130ceb4`).
- No dashboards opened.
- `cloudbuild.yaml` is unchanged, and no Render configuration exists in the repository.
