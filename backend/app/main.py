"""
Main FastAPI application entry point for the CoinScan backend recognition service.
"""

import time
import uuid
import logging
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from backend.app.config import settings
from backend.app.api import health, recognition, webhooks, feedback, account, collection

from contextlib import asynccontextmanager
from backend.app.db.session import init_db, close_db
from backend.app.runtime_checks import parse_allowed_origins, run_startup_checks
from backend.app.security.jwt_auth import signing_keys
from backend.app.security.request_limits import RequestSizeLimitMiddleware

# Configure structured logging (LOG_LEVEL: debug | info | warning | error).
logging.basicConfig(
    level=getattr(logging, (settings.log_level or "info").strip().upper(), logging.INFO),
    format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
)
# httpx logs every request URL at INFO. Some providers take their key as a query
# parameter (metals-api ?access_key=), so request lines must never be logged.
for _noisy_logger in ("httpx", "httpcore"):
    logging.getLogger(_noisy_logger).setLevel(logging.WARNING)
logger = logging.getLogger("coinscan.api")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifecycle manager for startup and shutdown of database pools and connections."""
    # Staging/production refuse to start without required security settings.
    run_startup_checks()
    await init_db()
    if settings.resolved_jwks_url:
        await signing_keys.refresh()
    yield
    await close_db()


# Interactive API docs only for development and tests.
_docs_enabled = settings.dev_features_enabled

app = FastAPI(
    title="CoinScan Recognition & Valuation API",
    description="Production-ready multi-sided coin recognition, catalogue verification, and valuation engine.",
    version=settings.app_version,
    docs_url="/docs" if _docs_enabled else None,
    redoc_url="/redoc" if _docs_enabled else None,
    openapi_url="/openapi.json" if _docs_enabled else None,
    lifespan=lifespan,
)

# Body size limits sit inside CORS so even a 413 carries CORS headers for web clients.
app.add_middleware(
    RequestSizeLimitMiddleware,
    default_max_bytes=settings.max_request_kb * 1024,
    path_limits={"/v1/recognition": settings.max_recognition_request_mb * 1024 * 1024},
)

# Configure CORS for the web app. Native mobile apps send no Origin header and
# are unaffected. ALLOWED_ORIGINS lists exact origins (scheme://host[:port]).
origins = parse_allowed_origins(settings.allowed_origins)
is_wildcard = origins == ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=not is_wildcard,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def structured_logging_middleware(request: Request, call_next) -> Response:
    """Assigns unique Request ID, measures latency, and logs structured metrics without payload leakage."""
    request_id = str(uuid.uuid4())
    request.state.request_id = request_id
    start_time = time.perf_counter()

    response: Response = await call_next(request)

    duration_ms = round((time.perf_counter() - start_time) * 1000, 2)
    response.headers["X-Request-ID"] = request_id

    # Log safe observability metrics
    logger.info(
        f"request_id={request_id} method={request.method} path={request.url.path} "
        f"status={response.status_code} duration_ms={duration_ms}"
    )

    return response


# Include Routers
app.include_router(health.router)
app.include_router(recognition.router)
app.include_router(webhooks.router)
app.include_router(feedback.router)
app.include_router(account.router)
app.include_router(collection.router)


@app.get("/")
async def root():
    return {
        "service": settings.app_name,
        "version": settings.app_version,
        "status": "online",
        "docs": "/docs" if _docs_enabled else None,
        "health": "/health",
    }


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global safe exception handler to prevent leaking internal stack traces."""
    return JSONResponse(
        status_code=500,
        content={
            "status": "error",
            "message": "An internal server error occurred while processing the coin scan.",
            "detail": str(exc) if settings.app_env == "development" else "Internal server error.",
        },
    )
