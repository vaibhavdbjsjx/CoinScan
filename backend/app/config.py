"""
Configuration and settings for the CoinScan backend service.

Security mode is decided by APP_ENV alone, never by the hosting platform:

  production, staging   hardened: strict token verification, required
                        configuration checked at startup, no development aids.
  development, test     development aids (mock bearer tokens, mock vision
                        provider, offline catalogue fixture, static API keys)
                        are available for local work and automated tests.

APP_ENV defaults to "production", so a deployment that forgets to set it is
hardened rather than exposed. Local development must opt in explicitly.
"""

from typing import Optional

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

APP_ENVIRONMENTS = ("development", "test", "staging", "production")
VISION_PROVIDERS = ("openai", "gemini")


class Settings(BaseSettings):
    app_name: str = "coinscan-backend"
    app_env: str = "production"
    app_version: str = "1.0.0"
    log_level: str = "info"
    host: str = "0.0.0.0"
    port: int = 8080
    allowed_origins: str = "*"
    # Development only: a shared static key mapped to the Pro tier. Never honoured
    # in staging or production (see security/auth.py).
    api_secret: Optional[str] = None

    # Vision AI Provider: 'openai' (production) or 'gemini' (legacy, Google Cloud era).
    vision_provider: str = "openai"
    gemini_api_key: Optional[str] = None
    gemini_model: str = "gemini-2.0-flash"
    openai_api_key: Optional[str] = None
    openai_model: str = "gpt-4o-mini"

    # Numismatic Catalogue (Numista)
    numista_api_key: Optional[str] = None
    numista_api_base_url: str = "https://api.numista.com/v3"
    # Answer catalogue lookups from the 4-record offline test fixture instead of Numista.
    # Honoured only when APP_ENV is development or test; every result is labelled as
    # fixture data. Never enable for real users.
    numista_offline_fixture: bool = False

    # Financial & Spot Providers
    metals_api_key: Optional[str] = None
    metals_api_base_url: str = "https://metals-api.com/api/latest"
    exchangerate_api_key: Optional[str] = None
    exchangerate_api_base_url: str = "https://open.er-api.com/v6/latest"

    # Development only: static API key → tier map (JSON string). Never honoured in
    # staging or production.
    api_keys_json: Optional[str] = None

    # Auth & Database (Supabase / PostgreSQL)
    supabase_url: Optional[str] = None
    # Server-only admin credential, used only to delete the Supabase Auth user when
    # an account is deleted. Prefer SUPABASE_SECRET_KEY (new sb_secret_... key);
    # SUPABASE_SERVICE_ROLE_KEY (legacy service_role JWT) is still accepted.
    supabase_secret_key: Optional[str] = None
    supabase_service_role_key: Optional[str] = None
    # Legacy shared secret (HS256). Needed only while the project still issues
    # HS256 tokens; projects on Supabase JWT signing keys verify via JWKS.
    supabase_jwt_secret: Optional[str] = None
    supabase_jwt_public_key: Optional[str] = None
    supabase_jwt_algorithm: Optional[str] = None
    supabase_jwt_audience: Optional[str] = "authenticated"
    supabase_jwt_issuer: Optional[str] = None
    # Public signing keys of the Supabase project. Defaults to
    # {SUPABASE_URL}/auth/v1/.well-known/jwks.json when SUPABASE_URL is set.
    supabase_jwks_url: Optional[str] = None
    supabase_jwks_cache_seconds: int = 600
    database_url: Optional[str] = None
    revenuecat_webhook_secret: Optional[str] = None
    # Exact (case-insensitive, comma-separated) RevenueCat identifiers mapped to tiers.
    # Must match the RevenueCat dashboard and lib/core/subscriptions/revenuecat_config.dart.
    revenuecat_pro_entitlement_ids: str = "pro"
    revenuecat_plus_entitlement_ids: str = "plus"
    revenuecat_pro_product_ids: str = "com.coinscan.pro.monthly,com.coinscan.pro.yearly"
    revenuecat_plus_product_ids: str = "com.coinscan.plus.monthly,com.coinscan.plus.yearly"

    # Mandatory Legal Consent
    required_terms_version: str = "1.0.0"
    required_privacy_version: str = "1.0.0"

    # Observability & Deployment
    sentry_dsn: Optional[str] = None
    cloud_run_service_url: Optional[str] = None

    # Database connection pool (per process). Supabase poolers and the smallest
    # Supabase compute have tight connection limits; keep these small.
    db_pool_size: int = 5
    db_max_overflow: int = 5
    db_pool_timeout_seconds: float = 10.0
    db_pool_recycle_seconds: int = 1800
    db_connect_timeout_seconds: float = 10.0
    db_command_timeout_seconds: float = 30.0
    # TLS to PostgreSQL: disable | prefer | require | verify-ca | verify-full.
    # Unset = taken from DATABASE_URL (ssl= or sslmode=), otherwise "require" in
    # staging/production and the driver default in development/test.
    db_ssl_mode: Optional[str] = None
    # Supavisor/PgBouncer transaction mode cannot keep prepared statements.
    # Unset = detected from the URL (port 6543 or pgbouncer=true).
    db_transaction_pooler: Optional[bool] = None

    # Request & Image Processing Limits
    # Per image. The app uploads JPEGs of at most 1920 px (typically < 2 MB).
    max_upload_mb: int = 10
    min_image_dimension: int = 240
    max_image_dimension: int = 4096
    # Decoding cost grows with pixel count; images above this are refused before
    # they are decoded (the app sends at most ~3.7 MP).
    max_image_pixels: int = 12_000_000
    # Whole-request ceilings, enforced while the body is received.
    max_recognition_request_mb: int = 32   # up to three images plus form fields
    max_request_kb: int = 1024             # every other endpoint (JSON bodies)
    request_timeout_seconds: float = 15.0
    rate_limit_per_minute: int = 60
    readiness_timeout_seconds: float = 3.0

    # Guest (signed-out) scanning
    guest_daily_scan_limit: int = 2        # per install (or per network when no install id is sent)
    guest_network_daily_scan_limit: int = 20  # abuse ceiling per network address
    # Secret for the keyed hash of guest identifiers. REQUIRED in staging and
    # production; guest scanning is refused (503) without it. Raw IPs are never stored.
    guest_quota_hmac_secret: Optional[str] = None

    # How the client address is found (used for guest-quota hashing and rate
    # limits; never stored). See security/client_ip.py.
    # CLIENT_IP_HEADER: a header the platform edge always sets itself, e.g.
    # X-Real-IP on Railway. Takes precedence when set. Verify after deploying.
    client_ip_header: Optional[str] = None
    # Otherwise: number of trusted reverse proxies that APPEND to X-Forwarded-For
    # (the client is the N-th entry from the right). 0 = the TCP peer address.
    # Never trust more hops than actually exist, or clients can spoof their address.
    trusted_proxy_hops: int = 0

    # Only backend/.env (server settings). The repository-root .env.example
    # documents public client variables and is never read by the API.
    model_config = SettingsConfigDict(
        env_file=("backend/.env",),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @field_validator("app_env", mode="before")
    @classmethod
    def _validate_app_env(cls, value):
        normalised = str(value or "").strip().lower() or "production"
        if normalised not in APP_ENVIRONMENTS:
            raise ValueError(f"APP_ENV must be one of: {', '.join(APP_ENVIRONMENTS)}")
        return normalised

    @field_validator("vision_provider", mode="before")
    @classmethod
    def _validate_vision_provider(cls, value):
        normalised = str(value or "").strip().lower() or "openai"
        if normalised not in VISION_PROVIDERS:
            raise ValueError(f"VISION_PROVIDER must be one of: {', '.join(VISION_PROVIDERS)}")
        return normalised

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def is_hardened(self) -> bool:
        """staging or production: strict security and required configuration."""
        return self.app_env in ("staging", "production")

    @property
    def dev_features_enabled(self) -> bool:
        """Development aids (mock bearer tokens, mock vision provider, offline
        catalogue fixture, static API keys). Only for an explicit APP_ENV of
        development or test; the hosting platform plays no part."""
        return self.app_env in ("development", "test")

    @property
    def resolved_jwks_url(self) -> Optional[str]:
        if self.supabase_jwks_url:
            return self.supabase_jwks_url.strip()
        if self.supabase_url:
            return f"{self.supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json"
        return None

    @property
    def supabase_admin_key(self) -> Optional[str]:
        """The Supabase admin credential: new secret key first, legacy service_role key second."""
        for value in (self.supabase_secret_key, self.supabase_service_role_key):
            if value and value.strip():
                return value.strip()
        return None

    @property
    def resolved_jwt_issuer(self) -> Optional[str]:
        if self.supabase_jwt_issuer:
            return self.supabase_jwt_issuer.strip()
        if self.supabase_url:
            return f"{self.supabase_url.rstrip('/')}/auth/v1"
        return None


settings = Settings()
