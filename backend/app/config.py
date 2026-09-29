"""
Configuration and settings for the CoinScan backend service.
"""

import os
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "coinscan-backend"
    app_env: str = "development"
    app_version: str = "1.0.0"
    log_level: str = "info"
    host: str = "0.0.0.0"
    port: int = 8080
    allowed_origins: str = "*"
    api_secret: Optional[str] = None

    # Vision AI Provider ('gemini' or 'openai')
    vision_provider: str = "gemini"
    gemini_api_key: Optional[str] = None
    gemini_model: str = "gemini-2.0-flash"
    openai_api_key: Optional[str] = None
    openai_model: str = "gpt-4o-mini"

    # Numismatic Catalogue (Numista)
    numista_api_key: Optional[str] = None
    numista_api_base_url: str = "https://api.numista.com/v3"
    # Answer catalogue lookups from the 4-record offline test fixture instead of Numista.
    # Honoured only in local development (see is_local_development); every result is
    # labelled as fixture data. Never enable for real users.
    numista_offline_fixture: bool = False

    # Financial & Spot Providers
    metals_api_key: Optional[str] = None
    metals_api_base_url: str = "https://metals-api.com/api/latest"
    exchangerate_api_key: Optional[str] = None
    exchangerate_api_base_url: str = "https://open.er-api.com/v6/latest"

    # API Key → Tier Mapping (JSON string, e.g. {"sk_abc": "pro", "sk_xyz": "free"})
    api_keys_json: Optional[str] = None

    # Auth & Database (Supabase / PostgreSQL)
    supabase_url: Optional[str] = None
    supabase_service_role_key: Optional[str] = None
    supabase_jwt_secret: Optional[str] = None
    supabase_jwt_public_key: Optional[str] = None
    supabase_jwt_algorithm: Optional[str] = None
    supabase_jwt_audience: Optional[str] = "authenticated"
    supabase_jwt_issuer: Optional[str] = None
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

    # Request & Image Processing Limits
    max_upload_mb: int = 20
    min_image_dimension: int = 240
    max_image_dimension: int = 4096
    request_timeout_seconds: float = 15.0
    rate_limit_per_minute: int = 60

    model_config = SettingsConfigDict(
        env_file=(".env", "backend/.env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @property
    def is_managed_platform(self) -> bool:
        """True when running on a hosted platform (Cloud Run sets K_SERVICE, Render sets RENDER)."""
        return bool(os.environ.get("K_SERVICE") or os.environ.get("RENDER"))

    @property
    def is_local_development(self) -> bool:
        """Development-only conveniences (mock auth tokens, mock vision, offline catalogue
        fixture) are allowed only for an explicit development/test environment that is not
        running on a hosted platform. A deployment that forgets APP_ENV therefore does not
        silently expose them."""
        return self.app_env in ("development", "test") and not self.is_managed_platform


settings = Settings()
