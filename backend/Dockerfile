# Multi-stage lightweight production Dockerfile for CoinScan Backend
FROM python:3.11-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --user -r requirements.txt

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

COPY --from=builder /root/.local /home/coinscan/.local
ENV PATH=/home/coinscan/.local/bin:$PATH
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

# Copy application source
COPY backend/app /app/backend/app

# Switch to non-root user
USER coinscan

EXPOSE 8080

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health/live || exit 1

CMD ["uvicorn", "backend.app.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "2"]
