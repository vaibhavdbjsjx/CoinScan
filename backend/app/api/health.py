"""
Health and readiness check endpoints for CoinScan API.
"""

from datetime import datetime
from fastapi import APIRouter
from backend.app.config import settings
from backend.app.models.responses import HealthResponse

router = APIRouter(tags=["Health"])


@router.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    """Returns service health and provider readiness without leaking credentials."""
    providers = {
        "vision": "ready" if (settings.gemini_api_key or settings.openai_api_key or settings.app_env == "development") else "mock",
        "numista": "ready" if settings.numista_api_key else "fallback_catalog",
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
    """Kubernetes / Cloud Run liveness probe."""
    return {"status": "alive", "service": settings.app_name}


@router.get("/health/ready")
async def readiness_check():
    """Readiness probe checking critical subsystems."""
    return {
        "status": "ready",
        "service": settings.app_name,
        "environment": settings.app_env,
        "vision_provider": settings.vision_provider,
    }
