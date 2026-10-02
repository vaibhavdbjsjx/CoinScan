"""
Startup configuration checks and readiness reporting.

Hardened environments (staging, production) refuse to start without the
settings that security depends on, and report "not ready" until everything a
production CoinScan needs is configured and reachable. Only setting *names*
are ever logged or returned, never their values.
"""

import logging
from typing import Dict, List, Tuple

from backend.app.config import settings
from backend.app.db.session import check_database, check_schema
from backend.app.security.jwt_auth import signing_keys

logger = logging.getLogger("coinscan.startup")

# Readiness check -> the setting that satisfies it (for messages only).
FEATURE_SETTINGS = {
    "vision": "OPENAI_API_KEY (or GEMINI_API_KEY with VISION_PROVIDER=gemini)",
    "catalogue": "NUMISTA_API_KEY",
    "guest_quota": "GUEST_QUOTA_HMAC_SECRET",
    "revenuecat_webhook": "REVENUECAT_WEBHOOK_SECRET",
    "account_deletion": "SUPABASE_SECRET_KEY (or legacy SUPABASE_SERVICE_ROLE_KEY)",
}


def parse_allowed_origins(raw: str) -> List[str]:
    """ALLOWED_ORIGINS as CORS origins. Browsers send Origin without a trailing
    slash or path, so "https://app.example.com/" is normalised to match.
    Empty or containing "*" means any origin (without credentials)."""
    origins = []
    for entry in (raw or "").split(","):
        origin = entry.strip().rstrip("/")
        if origin and origin not in origins:
            origins.append(origin)
    if not origins or "*" in origins:
        return ["*"]
    return origins


def cors_warnings() -> List[str]:
    """Advice for a hardened deployment's CORS setting (logged, never fatal)."""
    origins = parse_allowed_origins(settings.allowed_origins)
    if origins == ["*"]:
        return ["ALLOWED_ORIGINS allows every website. Set it to the web app's https origin(s); "
                "native apps are unaffected."]
    return [f"ALLOWED_ORIGINS entry {o} is not https." for o in origins if not o.startswith("https://")]


def configuration_problems() -> List[str]:
    """Security-critical settings missing for a staging/production deployment."""
    problems = []
    if not (settings.database_url and settings.database_url.strip()):
        problems.append("DATABASE_URL is not set")
    if not settings.resolved_jwt_issuer:
        problems.append("SUPABASE_URL is not set (needed to verify the token issuer and load the signing keys)")
    if not (settings.resolved_jwks_url or settings.supabase_jwt_secret or settings.supabase_jwt_public_key):
        problems.append("No Supabase token verification method (SUPABASE_URL for signing keys, or SUPABASE_JWT_SECRET)")
    return problems


def ignored_development_settings() -> List[str]:
    """Development-only settings that are present but never honoured when hardened."""
    names = []
    if settings.api_secret:
        names.append("API_SECRET")
    if settings.api_keys_json:
        names.append("API_KEYS_JSON")
    if settings.numista_offline_fixture:
        names.append("NUMISTA_OFFLINE_FIXTURE")
    return names


def feature_settings() -> Dict[str, bool]:
    provider = (settings.vision_provider or "").strip().lower()
    vision_key = {"openai": settings.openai_api_key, "gemini": settings.gemini_api_key}.get(provider)
    return {
        "vision": bool(vision_key),
        "catalogue": bool(settings.numista_api_key),
        "guest_quota": bool(settings.guest_quota_hmac_secret),
        "revenuecat_webhook": bool(settings.revenuecat_webhook_secret),
        # Deleting an account must also delete the Supabase login.
        "account_deletion": bool(settings.supabase_url and settings.supabase_admin_key),
    }


def run_startup_checks() -> None:
    """Logs the security mode; raises if a hardened deployment lacks required settings."""
    if settings.dev_features_enabled:
        logger.warning(
            f"APP_ENV={settings.app_env}: development aids are ENABLED (mock bearer tokens, mock "
            "vision provider, static API keys). Never expose this server publicly."
        )
        return

    problems = configuration_problems()
    for problem in problems:
        logger.critical(f"Startup configuration error: {problem}")
    if problems:
        raise RuntimeError(
            f"CoinScan refuses to start in {settings.app_env}: required configuration is missing (see log)."
        )

    for warning in cors_warnings():
        logger.warning(warning)
    if settings.vision_provider != "openai":
        logger.warning(
            f"VISION_PROVIDER={settings.vision_provider}: the legacy provider is selected. "
            "The production provider is OpenAI; unset VISION_PROVIDER to use it."
        )
    elif settings.gemini_api_key:
        logger.warning("GEMINI_API_KEY is set but unused (VISION_PROVIDER=openai); remove it.")
    for name in ignored_development_settings():
        logger.warning(f"{name} is set but ignored in {settings.app_env} (development-only setting).")
    if settings.guest_quota_hmac_secret and len(settings.guest_quota_hmac_secret) < 32:
        logger.warning("GUEST_QUOTA_HMAC_SECRET is shorter than 32 characters; use a long random value.")

    missing = [FEATURE_SETTINGS[name] for name, ok in feature_settings().items() if not ok]
    if missing:
        logger.error("Not ready for traffic until set: " + "; ".join(missing) + " (see /health/ready).")
    logger.info(f"Starting in {settings.app_env} mode: strict token verification, development aids disabled.")


def _auth_status() -> str:
    if settings.supabase_jwt_secret or settings.supabase_jwt_public_key or signing_keys.has_keys:
        return "ok"
    return "unavailable" if settings.resolved_jwks_url else "missing"


async def readiness() -> Tuple[bool, Dict[str, str]]:
    """Returns (ready, checks). Check values: ok | missing | unavailable | not_configured."""
    checks: Dict[str, str] = {"database": await check_database(settings.readiness_timeout_seconds)}
    # Every table the API uses must exist (migrations applied).
    checks["schema"] = (
        await check_schema(settings.readiness_timeout_seconds)
        if checks["database"] == "ok" else checks["database"]
    )

    if (
        settings.resolved_jwks_url
        and not signing_keys.has_keys
        and not (settings.supabase_jwt_secret or settings.supabase_jwt_public_key)
    ):
        await signing_keys.refresh()
    checks["auth"] = _auth_status()

    for name, configured in feature_settings().items():
        checks[name] = "ok" if configured else "missing"

    if settings.is_hardened:
        ready = all(value == "ok" for value in checks.values())
    else:
        ready = checks["database"] in ("ok", "not_configured")
    return ready, checks
