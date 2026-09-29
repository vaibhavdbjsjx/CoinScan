# COINSCAN — PHASE 2: HIGH-SEVERITY FORENSIC AUDIT
**DOCUMENT CLASSIFICATION: CONFIDENTIAL & PROPRIETARY — PRINCIPAL AUDIT REPORT**
**Date:** September 29, 2026
**Author:** Senior Principal Software Architect, Security Auditor, Mobile & Cloud Systems Engineer
**Audit Target:** CoinScan Production Codebase (Post-Phase 1 Critical Remediation)
**Audit Mode:** READ-ONLY FORENSIC INSPECTION (Zero source code modifications permitted or applied)

---

## 1. Executive Summary

This forensic audit represents an independent, rigorous, read-only evaluation of the CoinScan repository following the completion of Phase 1 critical remediation. The primary objective is to verify the exact status of all previously identified HIGH-severity issues, discover new or latent HIGH-severity risks, evaluate the architectural resilience of the current system against real production failure modes, and provide a clear, factual assessment of release readiness.

While Phase 1 successfully resolved all eight documented CRITICAL blockers across Google Cloud Build secret deployment bindings, JWT issuer cryptographic verification, cascading GDPR account deletion in Supabase GoTrue, RevenueCat webhook foreign-key crashes, mobile OAuth redirection handling, and native URI scheme declarations, the application cannot be declared production-ready. All 139 Flutter automated tests and all 141 backend Pytest automated tests currently pass with 100% success, and the Flutter static analyzer reports zero defects. However, automated test suites executing against mocked in-memory backends and mocked platform channels do not provide proof of production readiness.

The current repository continues to harbor significant, verified HIGH-severity issues across consumer user interfaces, valuation calculations, mobile navigation, and third-party data portability. Furthermore, four newly discovered HIGH-severity issues have been identified during this deep inspection: a distributed race condition and quota bypass in the backend scan reservation engine, a thundering herd token refresh vulnerability that can cause session revocation in mobile clients, an unauthenticated session desynchronization bug during email signup when email confirmation is active, and an unbounded base64 payload vulnerability in JSON API request schemas.

Under no circumstances should CoinScan be submitted to the Apple App Store or Google Play Store in its current state. The application requires a systematic, risk-prioritized Phase 3 remediation to resolve these HIGH-severity vulnerabilities.

---

## 2. Previous HIGH Findings

This section provides an independent, code-verified audit of the twelve HIGH-severity issues previously cataloged in the CoinScan forensic register. Each finding has been re-examined against the live source code to establish its current reality, exact file locations, technical evidence, and remaining production risk.

### Finding ISSUE-UX-01: AppRouter Initial Location Hardcoded to Onboarding

The original finding stated that AppRouter hardcodes initialLocation to /onboarding without evaluating whether the user is already authenticated or has completed onboarding, forcing returning users through the onboarding carousel on every application launch.

The current status of this issue is STILL PRESENT.

The affected file is lib/core/navigation/router.dart at lines 30 through 58.

Inspection of router.dart confirms that the GoRouter configuration initializes with initialLocation: onboarding. There is no redirect guard, no refreshListenable wired to AuthService.authStateChanges, and no persistent check against local storage or SharedPreferences to determine if onboarding has previously been acknowledged. Even when a user has a valid Supabase JWT stored in secure storage, every application cold start or restart forces the client to mount OnboardingScreen before reaching the login or main navigation shell.

In production, this defect results in immediate user friction and apparent session loss. Returning subscribed users will be subjected to the introductory onboarding flow on every launch, giving the impression that their account or data was wiped.

### Finding ISSUE-UX-02: HomeScreen Displays Mock Collectibles and Advisor Tips from MockApi

The original finding stated that HomeScreen bypasses real user vault data and server APIs, loading mock featured coins and hardcoded investment recommendations directly from MockApi.

The current status of this issue is STILL PRESENT.

The affected files are lib/features/home/home_screen.dart at lines 107 and 657, and lib/core/network/mock_api.dart at lines 221 through 240 and 460 through 490.

Inspection of home_screen.dart demonstrates that during widget build, the featured collection horizontal rail executes final featured = MockApi.getFeaturedCollectibles(), which returns static hardcoded coin models including a Carson City Morgan Dollar and a Saint-Gaudens Double Eagle. Additionally, line 657 constructs the Advisor insight card using final tip = MockApi.getAdvisorRecommendations().first. Neither of these sections queries the user's real collection stored in CollectionStorageService nor the backend API.

In production, App Store and Google Play human app reviewers will observe identical static mock assets across all accounts and test runs. Furthermore, genuine end users will see recommendations and portfolio items that do not reflect their actual physical collection, destroying trust in the platform's analytical utility.

### Finding ISSUE-UX-03: CollectionVaultScreen Displays Mock Series Completion Checklists

The original finding stated that CollectionVaultScreen depends on MockApi for series completion templates, utilizing hardcoded set identifiers and static targets.

The current status of this issue is STILL PRESENT.

The affected file is lib/features/collection/collection_vault_screen.dart at lines 570 through 596, referencing lib/core/network/mock_api.dart at lines 450 through 480.

Inspection of collection_vault_screen.dart demonstrates that the series completion ListView constructs its items using MockApi.getSeriesCompletions(). The code iterates over three hardcoded mock series templates: ser_double_eagle, ser_ancient_athens, and ser_morgan_dollar. The progress computation attempts to match items in the user's vault using heuristic string matching on coin name and denomination against static totalCount denominators.

In production, users collecting series outside these three hardcoded numismatic templates (such as Lincoln Cents, Washington Quarters, British Sovereigns, or Roman Imperial Denarii) receive zero series tracking capability. The feature operates as a hardcoded cosmetic demonstration rather than a generalized, server-backed numismatic series engine.

### Finding ISSUE-LEG-02: Non-Functional GDPR Data Portability Export UI

The original finding stated that the DataManagementScreen export functionality displays a cosmetic alert dialog showing byte counts rather than delivering an actual downloadable or shareable data archive, violating GDPR Article 20.

The current status of this issue is STILL PRESENT.

The affected file is lib/features/profile/data_management_screen.dart at lines 37 through 63.

Inspection of data_management_screen.dart reveals that the _exportData method executes exportToJson on the local scan history and collection storage services. Upon obtaining the raw JSON strings, it measures their character length and displays an AlertDialog informing the user that their export contains X bytes of scan records and Y bytes of collection vault metadata. The dialog provides a single action button labeled Close, which simply dismisses the dialog. The JSON payload is neither saved to the device filesystem, copied to the clipboard, presented in a system share sheet, nor synchronized with the server's GDPR export endpoint.

Under GDPR Article 20, individuals have the legal right to receive personal data concerning them in a structured, commonly used, and machine-readable format. Merely calculating string byte lengths and displaying them in a popup without providing the data file represents non-compliance that could trigger regulatory complaints and App Store rejection under guideline 5.1.1 (Data Collection and Storage).

### Finding ISSUE-LEG-03: ProfileScreen Displays Hardcoded Mock Showcase Data

The original finding stated that ProfileScreen renders hardcoded mock profile information ("Alexander Vance / Vaibhav Sharma", Level 12, 524 followers) instead of authenticated user metadata.

The current status of this issue is STILL PRESENT.

The affected files are lib/features/profile/profile_screen.dart at lines 330 through 365 and lines 754 through 850, and lib/core/network/mock_api.dart at lines 433 through 448.

Inspection of profile_screen.dart confirms two distinct hardcoded mock sections. In the Achievements tab, lines 330 through 365 render static widgets displaying 4,500 / 5,000 XP, a progress bar hardcoded to 0.9, Level 12, and 500 XP to Level 13. In the Public Showcase tab, line 755 executes final profile = MockApi.getCollectorProfile(), which pulls a static CollectorProfileModel featuring username Vaibhav Sharma, rank Ancient Coin Master, global ranking 342, reputation 98%, 142 scans, and 524 followers. These values are displayed unconditionally for every signed-in user.

In production, App Store review teams inspecting the application will flag developer names and fake social statistics embedded in consumer account views. For real users, displaying an entirely different person's name and fake stats is an unacceptable breach of interface integrity and personal profile privacy.

### Finding ISSUE-VAL-01: ValuationEngine Numismatic Pricing Restricted to Three Coin Issues

The original finding stated that the backend ValuationEngine numismatic collector price guide covers only three specific historical coin varieties, returning null for all other coins in the world.

The current status of this issue is STILL PRESENT.

The affected file is backend/app/services/valuation/valuation_service.py at lines 140 through 183.

Inspection of valuation_service.py confirms that _calculate_collector_guide_value contains strict conditional branching restricted to:
1. United States 1 Dollar minted in 1882 (Morgan Dollar).
2. British India minted in 1912 (1 Rupee George V).
3. Ancient Greece (Attica Athens Tetradrachm).
If a scanned coin does not match one of these three exact profiles, the collector valuation branch returns None. Unless the coin is composed of precious metal (allowing intrinsic melt calculation), the overall valuation result is marked as UNAVAILABLE.

In production, out of millions of cataloged coin types worldwide, 99.999% of scanned coins will display no collector value whatever. While refusing to fabricate prices is numismatically correct, having an internal pricing database containing only three coins severely limits the utility of the application unless an external valuation provider or comprehensive auction database is integrated.

### Finding ISSUE-VAL-02: MetalSpotPriceProvider Instantiated Without API Key

The original finding stated that ValuationEngine instantiates MetalSpotPriceProvider with zero arguments, completely bypassing settings.metals_api_key and forcing live bullion spot calculations to permanently fall back to static price data from January 1, 2026.

The current status of this issue is STILL PRESENT.

The affected files are backend/app/services/valuation/valuation_service.py at line 27, backend/app/api/recognition.py at line 65, and backend/app/services/valuation/metal_price_provider.py at lines 15 through 40.

Inspection of valuation_service.py reveals that ValuationEngine.__init__ defaults its provider using self.metal_provider = metal_provider or MetalSpotPriceProvider(). In recognition.py, line 65 instantiates valuation_engine = ValuationEngine() with no arguments. In metal_price_provider.py, __init__ defines api_key: Optional[str] = None. Because the API key is never supplied, line 38 executes if not self.api_key: return self._cache.get(symbol, 32.50). The cache is initialized with static baselines (Gold $2,680.00/oz, Silver $32.50/oz, Platinum $980.00/oz) timestamped January 1, 2026.

In production, even if the deployment administrator correctly provisions METALS_API_KEY in Google Secret Manager and mounts it into the Cloud Run container environment, the code completely ignores the environment variable. Precious metal valuations for bullion coins will forever compute against static January 2026 prices, producing increasingly inaccurate valuations as spot bullion markets fluctuate.

### Finding ISSUE-VAL-03: CollectionDetailScreen Synthetic Price History Generation

The original finding stated that CollectionDetailScreen generates synthetic price charts using Random() with an intentional upward bias, producing deceptive financial performance curves.

The current status of this issue is STILL PRESENT.

The affected files are lib/features/collection/collection_detail_screen.dart at lines 253 through 257, and lib/core/network/mock_api.dart at lines 386 through 424.

Inspection of collection_detail_screen.dart demonstrates that during build, the widget invokes MockApi.getPriceHistory(c.id, _selectedChartDuration, baseOverride: basePrice). In mock_api.dart, the getPriceHistory implementation constructs Random rand = Random(id.hashCode + duration.hashCode) and simulates historical data points by multiplying consecutive points by factor = 1.0 + (rand.nextDouble() * 0.08 - 0.02). The code explicitly includes the comment "upward bias" to simulate an appreciating asset.

Presenting fabricated investment return graphs to users under interactive duration tabs ("1 Month", "1 Year", "All Time") is an extreme compliance and legal liability. Regulators and store reviewers classify synthetic price curves that simulate past financial performance as deceptive market manipulation, especially in a tool marketing itself as an asset valuation and collection tracking utility.

### Finding ISSUE-VAL-04: CollectionStorageService Arbitrary Multiplier Formulas

The original finding stated that CollectionStorageService.toCollectibleModel() invents dealer buy prices, minimum/maximum valuation ranges, and investment letter ratings using fixed mathematical percentages and ternary operators.

The current status of this issue is STILL PRESENT.

The affected file is lib/core/storage/collection_storage_service.dart at lines 180 through 202.

Inspection of collection_storage_service.dart confirms that when transforming a persistent VaultItem into a CollectibleModel, the code applies arbitrary heuristics:
- dealerPrice: calculated as 85% of retail price (value * 0.85).
- minPrice: melt value or 80% of retail price (value * 0.8).
- maxPrice: catalogue value or 130% of retail price (value * 1.3).
- investmentRating: hardcoded as 'A' if the coin contains precious metals, and 'B+' for all other circulating issues.
- authenticityConfidence: defaulted to 0.88 if absent.
- designer: hardcoded as 'Historic Engraver'.

In production, these fabricated metrics mislead collectors. An alloy containing trace silver does not automatically confer an 'A' grade investment rating, and dealers do not buy arbitrary coins at exactly 85% of estimated retail value. Generating financial metrics from hardcoded multiplication factors violates numismatic integrity.

### Finding ISSUE-ARCH-02: ScanScreen Monolithic Architecture

The original finding stated that ScanScreen is an oversized 2,600+ line monolith that tightly couples camera lifecycle, accelerometer math, image decoding, custom painters, and state orchestration.

The current status of this issue is STILL PRESENT.

The affected file is lib/features/scan/scan_screen.dart comprising 2,608 lines of code.

Inspection of scan_screen.dart reveals a massive single-file architecture containing camera initialization, orientation changes, flash management, accelerometer and gyroscope sensor streams for levelness detection, edge detection canvas drawing, alignment overlays, lighting analysis, multiple modal bottom sheets, image cropping, and multipart API dispatching.

While the file compiles cleanly and functions during standard executions, its extreme complexity creates substantial maintenance hazards, increases the likelihood of memory leaks during camera controller re-initialization, and makes unit and widget testing of individual scanner subsystems extraordinarily difficult.

### Finding ISSUE-ARCH-03: Unused Backend GDPR Account Export Endpoint

The original finding stated that the server provides an asynchronous GDPR data export endpoint (GET /v1/account/export), but the mobile client never invokes it.

The current status of this issue is STILL PRESENT.

The affected files are backend/app/api/account.py at lines 719 through 756, and lib/core/network/api_client.dart.

Inspection of backend/app/api/account.py confirms a comprehensive export endpoint that aggregates user profile data, active entitlements, historical scans, collection items, and legal consent audit trails into an AccountDataExportResponse. However, a grep search across the entire lib/ directory reveals that ApiClient possesses no exportAccountData method, and no screen or service in the Flutter application ever issues a request to /v1/account/export.

This disconnect directly links to ISSUE-LEG-02: while backend engineers built the necessary GDPR data portability mechanism, frontend engineers failed to connect it, leaving users with only the cosmetic local byte-counter dialog.

### Finding ISSUE-PLAT-03: Android Help Center Apple ID Platform Copy Inconsistency

The original finding stated that the Help Center FAQ instructs users to sign in with their Apple ID to restore subscriptions, even when running on Android.

The current status of this issue is STILL PRESENT.

The affected file is lib/features/help/help_center_screen.dart at line 91.

Inspection of help_center_screen.dart confirms that under the question "How do I restore my subscription?", the static answer copy reads: "Open Settings → Account → Restore Purchases. As long as you are signed into the same Apple ID, your active Plus or Pro subscription will restore immediately." There is no check of defaultTargetPlatform or Platform.isAndroid to adjust this string to "Google Account" or a platform-neutral phrasing.

In production, Google Play Store app submission reviewers frequently reject applications that reference Apple proprietary terminology, Apple ID, or App Store policies within Android APK/AAB builds under Google Play Developer Program policies.

---

## 3. Newly Discovered HIGH Findings

During this forensic audit, four new HIGH-severity issues were discovered that were either omitted from the previous audit or represent latent architectural vulnerabilities.

### Finding ISSUE-CONC-01: In-Flight Quota Bypass and Multi-Instance State Desynchronization

The backend QuotaEngine implements a two-phase slot reservation mechanism to prevent race conditions during concurrent scans. However, the reservation phase operates exclusively on volatile in-memory dictionaries and fails to query or lock the persistent database.

The affected file is backend/app/security/quota_service.py at lines 278 through 315 and lines 364 through 405.

Inspection of reserve_slot in quota_service.py reveals that when a request arrives, the function executes:
```python
async with self._lock:
    key = (identifier, date_str)
    current_used = self._daily_usage.get(key, 0)
    current_in_flight = self._in_flight.get(key, 0)
    if current_used + current_in_flight >= limit:
        raise HTTPException(status_code=429, ...)
    self._in_flight[key] = current_in_flight + 1
```
Notice that reserve_slot never queries the database ScanUsage table. It relies entirely on self._daily_usage in the local Python process. In a containerized cloud deployment such as Google Cloud Run, multiple instances scale horizontally to serve traffic. If a user sends requests across multiple containers, or if a container restarts, self._daily_usage is zero. A free user with a 3-scan limit can easily execute dozens of scans across instances.

Furthermore, when the scan completes and commit() is called, the database update executes:
```python
if usage is None:
    usage = ScanUsage(user_id=self.identifier, scan_date=c_date, scan_count=1)
    session.add(usage)
else:
    usage.scan_count += 1
await session.commit()
```
The commit method blindly increments scan_count without verifying whether scan_count has exceeded the limit. Because the front door (reserve_slot) only checked volatile memory, and the back door (commit) increments without enforcement, the database will happily record scan_count values far above the tier limit.

The exploit scenario involves an unauthorized free user bursting simultaneous requests to different Cloud Run instances or after container auto-recycling, consuming expensive Gemini Vision AI and Numista API calls without subscribing.

The recommended remediation direction is to refactor reserve_slot to perform an atomic PostgreSQL check-and-reserve transaction using SELECT ... FOR UPDATE or an atomic UPDATE ... WHERE scan_count < limit statement when database persistence is configured.

### Finding ISSUE-AUTH-05: Concurrent Token Refresh Thundering Herd and Session Revocation

The mobile ApiClient executes an automatic token refresh when encountering an HTTP 401 response. However, it lacks a mutual exclusion lock or unified future for concurrent in-flight refreshes, causing a thundering herd against the authentication provider.

The affected file is lib/core/network/api_client.dart at lines 185 through 202.

Inspection of ApiClient._performRequestWithRefresh reveals that when an API call receives HTTP 401, it executes:
```dart
if (response.statusCode == 401 && tokenRefresher != null) {
  final refreshedToken = await tokenRefresher!();
  if (refreshedToken != null && refreshedToken.isNotEmpty) {
    ...
  } else {
    await onSessionExpired?.call();
  }
}
```
In standard application usage, when an access token expires while the user is actively viewing their vault or home screen, multiple background API calls (fetching profile, collection items, and scan usage) encounter 401 at the exact same millisecond. Each concurrent request independently invokes tokenRefresher!(), which in turn calls AuthService.refreshToken() and Supabase.auth.refreshSession().

Supabase Auth (GoTrue) enforces single-use refresh token rotation by default. When multiple concurrent requests submit the exact same old refresh token in rapid succession, the GoTrue server detects this as a potential token replay attack (RFC 6819 Section 5.2.2.3). GoTrue immediately invalidates the entire refresh token family, revoking all active sessions for that user. Consequently, onSessionExpired is triggered, logging the user out abruptly while they are actively using the application.

The exploit/failure scenario occurs naturally when any active user leaves the app backgrounded until their access token expires (typically 1 hour), then foregrounds the app. Instead of a seamless background token renewal, they are unexpectedly booted to the login screen and their session is destroyed.

The recommended remediation direction is to introduce an asynchronous mutex or single in-flight Completer in ApiClient or AuthService, ensuring that only one refresh request is dispatched to Supabase while all other 401 requests await the same resolution.

### Finding ISSUE-AUTH-06: Email Signup Pending Verification State Desynchronization

When a user signs up with email and password, AuthService immediately places the client into an authenticated state with a placeholder token if email verification is enabled on Supabase, leading to broken network operations.

The affected file is lib/core/auth/auth_service.dart at lines 358 through 413.

Inspection of signUpWithEmail in auth_service.dart demonstrates:
```dart
final res = await client.auth.signUp(
  email: email,
  password: password,
  data: {'display_name': resolvedDisplayName},
);
final user = res.user;
final session = res.session;
userId = user.id;
token = session?.accessToken ?? 'pending_verification';
...
await _persistSession(token: token, userId: userId, ...);
_state = AuthState(user: profile, token: token, termsConsentRequired: false);
_configureApiClient();
_authStateController.add(_state);
unawaited(fetchAuthoritativeProfile());
```
When Supabase is configured with mandatory email confirmation (the recommended production security baseline), client.auth.signUp() successfully registers the user in auth.users, but returns session == null until the user clicks the verification link in their email.

Because session is null, AuthService assigns token = 'pending_verification'. It then immediately marks the user as fully authenticated in local state, writes pending_verification to the device Keychain/Keystore, and dispatches fetchAuthoritativeProfile(). The ApiClient immediately issues GET /v1/account/me with Authorization: Bearer pending_verification. The backend rejects this token with HTTP 401.

The user is thrust into the main application interface, but every subsequent network operation (collection vault, scan recognition, profile loading) fails with unauthorized errors. If the user closes and re-opens the app, the session restoration logic attempts to restore pending_verification from secure storage, permanently locking them in a broken authenticated state.

The recommended remediation direction is to verify whether session is null upon signup. If null, the app must not enter AuthState.authenticated; instead, it should navigate to an "Email Verification Sent" confirmation screen informing the user to verify their inbox before logging in.

### Finding ISSUE-API-01: Unbounded Base64 Request Payload Size on JSON Recognition Model

While the multipart recognition endpoint limits upload sizes, the JSON/Base64 request model lacks maximum length constraints on image strings, leaving the backend vulnerable to memory exhaustion.

The affected file is backend/app/models/requests.py at lines 16 through 24.

Inspection of JsonRecognitionRequest in requests.py reveals:
```python
class JsonRecognitionRequest(BaseModel):
    frontImageBase64: str = Field(alias="front_image_base64")
    reverseImageBase64: Optional[str] = Field(default=None, alias="reverse_image_base64")
    edgeImageBase64: Optional[str] = Field(default=None, alias="edge_image_base64")
    ...
```
In Pydantic, string fields without max_length accept arbitrarily large payloads. If an alternative JSON-based recognition endpoint or client payload is parsed, a malicious actor could send hundreds of megabytes of base64 data. When Python decodes multiple concurrent 100MB+ base64 strings into memory buffers, it can trigger out-of-memory (OOM) killer events in Cloud Run containers (which typically run with 1GB to 2GB memory limits), taking down the entire API instance.

The recommended remediation direction is to enforce max_length on all base64 string fields in JsonRecognitionRequest (e.g., max_length=28_000_000, representing ~20MB of raw image data after base64 encoding).

---

## 4. HIGH Issues That Were Actually Fixed

It is critical to distinguish between issues that have actually been remediated versus those that remain outstanding. 

A thorough review of the Phase 1 remediation documented in COINSCAN_CRITICAL_REMEDIATION_REPORT.md confirms that Phase 1 was strictly scoped to the eight CRITICAL blockers:
1. ISSUE-SEC-01 (Cloud Build Secret Manager bindings for DATABASE_URL)
2. ISSUE-SEC-02 (Cloud Build Secret Manager bindings for SUPABASE_JWT_SECRET)
3. ISSUE-SEC-03 (JWT issuer verification in JwtAuthVerifier)
4. ISSUE-DATA-01 (Cascading account deletion in Supabase GoTrue admin API)
5. ISSUE-DATA-02 (WebhookStateManager foreign key crashes on anonymous IDs)
6. ISSUE-AUTH-01 (AuthService Google Sign In hardcoded credentials & crashes)
7. ISSUE-AUTH-02 (AuthService Apple Sign In hardcoded credentials & crashes)
8. ISSUE-AUTH-03 (Native URI scheme intent filters in AndroidManifest.xml and Info.plist)

None of the twelve previously reported HIGH issues were addressed in Phase 1, nor were they resolved as side effects of the critical fixes. Every single one of the twelve previous HIGH findings remains active in the current source code, exactly as demonstrated by the forensic evidence in Section 2.

Any previous document claiming that the marketplace, price charts, mock profiles, or onboarding bypasses were completely resolved was referring only to partial exploratory prototypes or was factually mistaken. This audit independently confirms that all 12 original HIGH findings, plus the 4 newly discovered HIGH findings, currently exist in the repository.

---

## 5. External Blockers

In evaluating production readiness, technical defects within source code must be cleanly separated from external infrastructure requirements that cannot be verified solely through code inspection. The following external blockers currently prevent live production deployment and end-to-end operational verification:

### Apple Developer & App Store Connect
1. Store Subscription Products: Auto-renewable subscription product identifiers com.coinscan.plus.monthly, com.coinscan.plus.yearly, com.coinscan.pro.monthly, and com.coinscan.pro.yearly have not been created in App Store Connect.
2. Paid Applications Agreement: Apple's Paid Applications Agreement and banking/tax profiles must be active in App Store Connect to process sandbox or live transactions.
3. App Store Review Account: A dedicated review account with pre-seeded collection items and active credentials must be provisioned.
4. Production Provisioning Profiles & Certificates: Distribution certificates and App Store provisioning profiles tied to bundle identifier com.coinvault.coinvaultAi must be generated for release signing.

### Google Play Console
1. Google Play Subscriptions: In-app subscription products matching the canonical product identifiers must be configured with base plans and billing offers in the Play Console.
2. Google Play Billing API & Service Account: A Google Cloud service account with permissions to access Google Play Android Developer APIs must be linked to RevenueCat for server-side receipt verification.
3. Release Keystore: A production upload keystore (.jks/.keystore) must be created and stored securely for signing release AABs.

### RevenueCat Dashboard
1. Project & App Configuration: iOS App (bundle ID com.coinvault.coinvaultAi) and Android App (package name com.coinvault.coinvault_ai) must be created in the RevenueCat dashboard.
2. Entitlements & Offerings: Entitlements plus and pro, along with a default offering containing Monthly and Annual packages, must be configured.
3. Webhook Endpoint: The production Cloud Run webhook URL (https://<cloud-run-domain>/v1/webhooks/revenuecat) and shared authorization secret must be registered in the RevenueCat dashboard.
4. Public SDK Keys: The generated public SDK keys (appl_... and goog_...) must be supplied to the Flutter build via compile-time defines REVENUECAT_APPLE_KEY and REVENUECAT_GOOGLE_KEY.

### Supabase & Cloud Infrastructure
1. Supabase Auth Configuration: In the Supabase project dashboard, redirect URLs must include com.coinvault.coinvaultai://login-callback. Email confirmation templates and OAuth provider keys (Apple Client Secret / Service ID, Google Web Client ID / Secret) must be provisioned.
2. Google Cloud Secret Manager: Production secrets (DATABASE_URL, SUPABASE_JWT_SECRET, SUPABASE_SERVICE_ROLE_KEY, REVENUECAT_WEBHOOK_SECRET, GEMINI_API_KEY, NUMISTA_API_KEY, METALS_API_KEY, EXCHANGERATE_API_KEY) must be populated in the production GCP project to satisfy Cloud Build deployment bindings.
3. Real Physical Device Testing: StoreKit 2 transactions on physical iOS devices and Google Play Billing flows on physical Android devices cannot be validated in automated CI runners or emulators.

---

## 6. Test Verification

The repository test suites were executed independently during this audit using read-only terminal commands.

### Flutter Static Analysis
Execution command:
```bash
flutter analyze
```
Result:
Analyzing coinscan...
No issues found! (ran in 3.3s)
Status: Clean (0 issues).

### Flutter Test Suite
Execution command:
```bash
flutter test --reporter expanded
```
Result:
139 out of 139 tests passed (100% pass rate).
Total execution time: 5 seconds.
Note on logs: Warning logs regarding offline ApiException(status: 400) appear during auth and consent tests because the suite runs against mocked local HTTP clients without live Supabase endpoints. This behavior is expected and caught by test assertions.

### Backend Pytest Suite
Execution command:
```bash
PYTHONPATH=backend:backend/.venv/lib/python3.9/site-packages /usr/bin/python3 -m pytest backend/tests -v
```
Result:
141 out of 141 tests passed (100% pass rate).
Total execution time: 1.76 seconds.
Warnings: One standard deprecation warning from pyjwt regarding HMAC test key length.
Status: Clean (0 failures).

---

## 7. Test Coverage Gaps

Although the automated test suites report 100% success, a critical analysis of what those tests actually cover reveals severe gaps in production verification. Passing tests do not constitute proof of production readiness when the tests test idealized mocks rather than failure-prone production environments.

### Real PostgreSQL & Row-Level Security
Zero backend tests execute against a real PostgreSQL instance. All automated tests utilize in-memory mock stores or SQLite in-memory databases with foreign keys disabled. Consequently, real PostgreSQL custom enum serialization, timezone-aware datetime operations, concurrency locking with SELECT ... FOR UPDATE, and Supabase Row-Level Security (RLS) policies are completely untested in automated CI.

### Multi-Worker & Multi-Container Concurrency
Zero tests execute across multiple concurrent processes. All concurrency tests execute within a single Python asyncio event loop sharing the same QuotaEngine memory space. Distributed race conditions, container recycling, and cross-instance quota leaks (such as Finding ISSUE-CONC-01) cannot be detected by the current test suite.

### Native StoreKit 2 and Google Play Billing APIs
Zero tests validate genuine StoreKit 2 or Google Play Billing plugin method channels. The Flutter tests run using DevSubscriptionService or mocked purchases_flutter responses. Real device edge cases—such as user cancellation midway through purchase, payment pending authorization (Ask to Buy for family sharing), network drop during receipt validation, or billing retry grace periods—have zero automated coverage.

### Camera Hardware & Video Stream Memory
Zero automated tests validate physical camera hardware captures. All camera unit tests feed synthetic ByteData buffers to ImagePreprocessingService. Real-world edge cases—including camera device orientation lock, EXIF rotation matrix handling, sensor memory exhaustion during rapid multi-coin burst captures, and Android CameraX lifecycle binding during app switching—are completely uncovered by automated suites.

---

## 8. Production Architecture Risks

Beyond discrete functional bugs, the audit evaluated foundational architectural risks that could impair scalability, stability, and maintainability.

### Stateful In-Memory State on Stateless Cloud Run
The backend architecture maintains hybrid persistence: data is written to PostgreSQL (when configured), but operational state—such as in-flight scan reservations, IP rate limiting, and Numista fallback caches—is held in global Python dictionaries. In a serverless container environment like Cloud Run, container instances scale from zero to many and shut down arbitrarily. Relying on in-process memory for quota enforcement and rate limiting is architecturally flawed for distributed deployments; a distributed cache (such as Redis / Memorystore) or database-backed advisory locks should be used.

### Monolithic UI File Structures
Several key Flutter views exhibit extreme file bloat. ScanScreen exceeds 2,600 lines; CollectionDetailScreen exceeds 1,460 lines; ProfileScreen exceeds 1,070 lines; HomeScreen exceeds 1,040 lines. These files bundle navigation, sensor hardware logic, complex custom painting, layout building, and mock data loading into giant single files. This architectural style significantly increases cognitive load, slows down code reviews, and increases the surface area for regression bugs during refactoring.

### Asymmetrical Client/Server Contracts
There are significant discrepancies between mobile client capabilities and server schemas. For example, the backend CollectionItem schema omits the numismatic variety field present in the client; the client DataManagementScreen omits the backend GET /v1/account/export integration; and the backend ValuationEngine ignores the METALS_API_KEY available in application configuration. These disconnects indicate that backend and mobile teams developed features independently without strict schema contract enforcement.

---

## 9. Recommended Remediation Order

To ensure systematic, safe remediation in subsequent phases, the HIGH-severity findings should be addressed in the following sequence based on architectural dependencies and production risk:

### Phase 2A: Authentication, Session & Concurrency Hardening
1. Fix ISSUE-CONC-01: Refactor QuotaEngine.reserve_slot to enforce atomic, database-backed quota validation, eliminating multi-instance quota bypass.
2. Fix ISSUE-AUTH-05: Implement a mutual-exclusion refresh lock and shared future in ApiClient to eliminate concurrent token refresh storms and prevent accidental session revocation.
3. Fix ISSUE-AUTH-06: Correct AuthService.signUpWithEmail to handle null sessions when email verification is required, preventing broken pending_verification session states.
4. Fix ISSUE-UX-01: Update AppRouter with a reactive redirect guard listening to AuthService, routing authenticated users directly to the main navigation shell on launch.

### Phase 2B: Consumer UI Mock Data Elimination & App Store Safety
1. Fix ISSUE-LEG-03: Strip hardcoded mock profile data ("Vaibhav Sharma", Level 12) from ProfileScreen; bind the view strictly to authentic user profile metadata and genuine vault statistics.
2. Fix ISSUE-UX-02: Remove MockApi featured collectibles and advisor tips from HomeScreen; bind the dashboard to the user's authentic collection vault.
3. Fix ISSUE-UX-03: Refactor CollectionVaultScreen series completions to operate on genuine user vault data or gracefully indicate customizable set tracking rather than hardcoded mock series.
4. Fix ISSUE-PLAT-03: Platform-gate Help Center restoration instructions to display "Google Account" on Android and "Apple ID" on iOS.

### Phase 2C: Valuation Engine & Numismatic Integrity
1. Fix ISSUE-VAL-02: Inject settings.metals_api_key into MetalSpotPriceProvider across valuation_service.py and recognition.py, enabling real-time spot bullion pricing.
2. Fix ISSUE-VAL-03: Eliminate synthetic Random() price history generation with artificial upward bias in mock_api.dart and CollectionDetailScreen; display honest historic numismatic index data or state that historical auction trend data is unavailable.
3. Fix ISSUE-VAL-04: Remove fabricated dealer price (85%), min/max percentages, and investment letter grades from CollectionStorageService.toCollectibleModel(); present only genuine verified valuation metrics.
4. Fix ISSUE-VAL-01: Expand or gracefully handle collector pricing limits in ValuationEngine so users understand when catalogue values are unavailable versus returning silent nulls.

### Phase 2D: Compliance, Data Portability & API Hardening
1. Fix ISSUE-LEG-02 & ISSUE-ARCH-03: Wire DataManagementScreen "Export My Data" button directly to the backend GET /v1/account/export endpoint and present a system share sheet allowing users to export their machine-readable JSON data archive.
2. Fix ISSUE-API-01: Add max_length constraints to JsonRecognitionRequest base64 fields in requests.py to prevent memory exhaustion denial-of-service attacks.
3. Fix ISSUE-ARCH-02: Progressively modularize ScanScreen by extracting sensor handling, camera overlays, and review dialogs into focused component widgets.

---

## 10. Final Verdict

### Status: HIGH ISSUES REMAIN

The CoinScan codebase has achieved commendable progress with the complete remediation of all eight CRITICAL security and deployment blockers in Phase 1. Static analysis is clean (0 issues) and automated unit test suites achieve a 100% pass rate (280/280 total tests passed).

However, **the application is NOT ready for production release.** 

All twelve previously identified HIGH-severity issues remain fully active in the current source code, and four newly discovered HIGH-severity vulnerabilities pose genuine risks to session stability, quota enforcement, and infrastructure memory safety. 

Subsequent remediation phases must systematically resolve these verified defects before initiating App Store submission or public production traffic.

---
*End of Forensic Audit Report — Prepared for Engineering Leadership & Release Governance.*
