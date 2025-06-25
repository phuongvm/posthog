# PostHog Django Services Unified Dockerfile
# Based on root Dockerfile structure for web, worker, migrate, temporal-django-worker

# ===========================================
# Stage 1: Frontend Build
# ===========================================
FROM node:18.19.1-bookworm-slim AS frontend-build
WORKDIR /code
SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

COPY turbo.json package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.json ./
COPY frontend/package.json frontend/
COPY frontend/bin/ frontend/bin/
COPY bin/ bin/
COPY patches/ patches/
COPY common/hogvm/typescript/ common/hogvm/typescript/
COPY common/esbuilder/ common/esbuilder/
COPY common/eslint_rules/ common/eslint_rules/
COPY common/tailwind/ common/tailwind/
COPY products/ products/
COPY ee/frontend/ ee/frontend/
RUN --mount=type=cache,id=pnpm,target=/tmp/pnpm-store \
    corepack enable && pnpm --version && \
    pnpm --filter=@posthog/frontend... install --frozen-lockfile --store-dir /tmp/pnpm-store

COPY frontend/ frontend/
RUN bin/turbo --filter=@posthog/frontend build
# KLUDGE: to get the image-bitmap-data-url-worker-*.js.map files into the dist folder
RUN cp frontend/node_modules/@posthog/rrweb/dist/image-bitmap-data-url-worker-*.js.map frontend/dist/ || true

# ===========================================
# Stage 2: Django Build
# ===========================================
FROM python:3.11.9-slim-bookworm AS django-build
WORKDIR /code
SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

# Install build dependencies
COPY pyproject.toml uv.lock ./
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    "build-essential" \
    "git" \
    "libpq-dev" \
    "libxmlsec1" \
    "libxmlsec1-dev" \
    "libffi-dev" \
    "zlib1g-dev" \
    "pkg-config" \
    && \
    rm -rf /var/lib/apt/lists/* && \
    pip install uv~=0.7.0 --no-cache-dir && \
    UV_PROJECT_ENVIRONMENT=/python-runtime uv sync --frozen --no-cache --compile-bytecode --no-binary-package lxml --no-binary-package xmlsec

ENV PATH=/python-runtime/bin:$PATH \
    PYTHONPATH=/python-runtime

# Copy Django source and build static files
COPY manage.py manage.py
COPY common/esbuilder common/esbuilder
COPY common/hogvm common/hogvm/
COPY posthog posthog/
COPY products/ products/
COPY ee ee/
COPY --from=frontend-build /code/frontend/dist /code/frontend/dist
RUN SKIP_SERVICE_VERSION_REQUIREMENTS=1 STATIC_COLLECTION=1 DATABASE_URL='postgres:///' REDIS_URL='redis:///' python manage.py collectstatic --noinput

# ===========================================
# Stage 3: GeoIP Database
# ===========================================
FROM debian:bookworm-slim AS geoip-db
WORKDIR /code
SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

# Fetch the GeoLite2-City database
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    "ca-certificates" \
    "curl" \
    "brotli" \
    && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir share && \
    ( curl -s -L "https://mmdbcdn.posthog.net/" --http1.1 | brotli --decompress --output=./share/GeoLite2-City.mmdb ) && \
    chmod -R 755 ./share/GeoLite2-City.mmdb

# ===========================================
# Stage 4: Runtime Environment
# ===========================================
FROM python:3.11.9-slim-bookworm AS runtime
WORKDIR /code
SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]
ENV PYTHONUNBUFFERED 1

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    "chromium" \
    "chromium-driver" \
    "libpq-dev" \
    "libxmlsec1" \
    "libxmlsec1-dev" \
    "libxml2" \
    "gettext-base" \
    "curl" \
    "ca-certificates" \
    "nodejs" \
    "npm" \
    && \
    rm -rf /var/lib/apt/lists/*

# Install pnpm
RUN npm install -g pnpm

# Create non-root user
RUN groupadd -g 1000 posthog && \
    useradd -r -g posthog -u 1000 posthog && \
    chown posthog:posthog /code

# Copy Python runtime from django-build
COPY --from=django-build --chown=posthog:posthog /python-runtime /python-runtime
ENV PATH=/python-runtime/bin:$PATH \
    PYTHONPATH=/python-runtime

# Copy Django static files
COPY --from=django-build --chown=posthog:posthog /code/staticfiles /code/staticfiles

# Copy frontend assets
COPY --from=frontend-build --chown=posthog:posthog /code/frontend/dist /code/frontend/dist

# Copy GeoIP database
COPY --from=geoip-db --chown=posthog:posthog /code/share/GeoLite2-City.mmdb /code/share/GeoLite2-City.mmdb

# Copy application code
COPY --chown=posthog:posthog . .

# Create necessary directories
RUN mkdir -p .tmp && \
    chown -R posthog:posthog .tmp

# Switch to non-root user
USER posthog

# Set environment variables
ENV NODE_ENV=production \
    CHROME_BIN=/usr/bin/chromium \
    CHROME_PATH=/usr/lib/chromium/ \
    CHROMEDRIVER_BIN=/usr/bin/chromedriver \
    DJANGO_SETTINGS_MODULE=posthog.settings

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/_health || exit 1

# Default command (will be overridden in docker-compose)
CMD ["./bin/docker-worker-celery", "--with-scheduler"]

# ===========================================
# Stage 5: Development Environment
# ===========================================
FROM runtime AS development

# Install development dependencies
USER root
RUN UV_PROJECT_ENVIRONMENT=/python-runtime uv sync --frozen --no-cache --compile-bytecode --no-binary-package lxml --no-binary-package xmlsec --group dev

USER posthog

# Development command
CMD ["./bin/docker-worker-celery", "--with-scheduler"] 