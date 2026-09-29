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

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
)
logger = logging.getLogger("coinscan.api")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifecycle manager for startup and shutdown of database pools and connections."""
    await init_db()
    yield
    await close_db()


app = FastAPI(
    title="CoinScan Recognition & Valuation API",
    description="Production-ready multi-sided coin recognition, catalogue verification, and valuation engine.",
    version=settings.app_version,
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# Configure CORS for Flutter Web, iOS, Android, and desktop clients
origins = [o.strip() for o in settings.allowed_origins.split(",") if o.strip()]
if not origins or "*" in origins:
    origins = ["*"]

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
        "docs": "/docs",
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
