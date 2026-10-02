"""
Health and readiness check endpoints for CoinScan API.

/health/live   the process is up (no dependency checks).
/health/ready  the service can take traffic: in staging/production this means
               the database answers, Supabase token verification works and every
               required provider setting is present. Used as the deploy
               healthcheck. Responses name checks only; they never include
               secrets, connection strings or error details.
"""

from datetime import datetime
from fastapi import APIRouter
from fastapi.responses import JSONResponse

from backend.app.config import settings
from backend.app.models.responses import HealthResponse
from backend.app.runtime_checks import feature_settings, readiness

router = APIRouter(tags=["Health"])


@router.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    """Returns service health and provider configuration without leaking credentials."""
    configured = feature_settings()
    if configured["vision"]:
        vision = "ready"
    else:
        vision = "mock" if settings.dev_features_enabled else "not_configured"
    if settings.numista_api_key:
        numista = "ready"
    elif settings.numista_offline_fixture and settings.dev_features_enabled:
        numista = "offline_fixture"
    else:
        numista = "not_configured"
    providers = {
        "vision": vision,
        "numista": numista,
        "valuation": "ready",
        "fx": "ready",
    }

    return HealthResponse(
        status="ok",
        service=settings.app_name,
        version=settings.app_version,
        environment=settings.app_env,
        providers=providers,
        timestamp=datetime.utcnow().isoformat() + "Z",
    )


@router.get("/health/live")
async def liveness_check():
    """Liveness probe: the process is running and serving requests."""
    return {"status": "alive"}


@router.get("/health/ready")
async def readiness_check():
    """Readiness probe: 200 when ready for traffic, otherwise 503 with the failing check names."""
    ready, checks = await readiness()
    return JSONResponse(
        status_code=200 if ready else 503,
        content={"status": "ready" if ready else "not_ready", "checks": checks},
    )
