# Multi-stage lightweight production Dockerfile for CoinScan Backend
FROM python:3.11-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Dependencies go into a self-contained virtualenv. (A `pip install --user`
# into /root/.local is not found at runtime: the non-root user's home is /app,
# so Python would look in /app/.local and the server could not start.)
COPY backend/requirements.txt ./requirements.txt
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# Final minimal runtime container
FROM python:3.11-slim

# Create non-root user for security
RUN groupadd -r coinscan && useradd -r -g coinscan -d /app -s /sbin/nologin coinscan

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg62-turbo \
    zlib1g \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Same base image and path as the builder, so the virtualenv works unchanged.
COPY --from=builder /opt/venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Copy application source
COPY backend/app /app/backend/app

# Switch to non-root user
USER coinscan

# Documentation only: the server binds to $PORT (injected by Railway and most
# platforms); 8080 is the fallback for plain `docker run`.
EXPOSE 8080

# Container-level liveness check (platforms such as Railway use their own
# deploy healthcheck, configured to /health/ready).
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PORT:-8080}/health/live" > /dev/null || exit 1

# - Binds 0.0.0.0:$PORT (default 8080).
# - One worker unless WEB_CONCURRENCY says otherwise (scans are I/O-bound).
# - On SIGTERM, in-flight requests get GRACEFUL_SHUTDOWN_SECONDS to finish;
#   keep it below the platform's draining time (railway.toml: 30 s).
# - --no-proxy-headers: client addresses come only from CLIENT_IP_HEADER /
#   TRUSTED_PROXY_HOPS, never from FORWARDED_ALLOW_IPS.
# - --no-access-log: uvicorn's access log records the connecting address; the
#   app's own request log (request id, path, status, latency) never does.
# `exec` makes uvicorn PID 1 so it receives the platform's signals directly.
CMD ["sh", "-c", "exec uvicorn backend.app.main:app --host 0.0.0.0 --port \"${PORT:-8080}\" --workers \"${WEB_CONCURRENCY:-1}\" --timeout-graceful-shutdown \"${GRACEFUL_SHUTDOWN_SECONDS:-25}\" --no-proxy-headers --no-access-log"]
