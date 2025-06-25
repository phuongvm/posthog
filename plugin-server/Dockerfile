# PostHog Plugin Server Dockerfile
# Multi-stage build optimized for plugin-server

# ===========================================
# Stage 1: Dependencies & Build Environment
# ===========================================
FROM ghcr.io/posthog/rust-node-container:bookworm_rust_1.82-node_18.19.1 AS builder

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    "make" \
    "g++" \
    "gcc" \
    "python3" \
    "libssl-dev" \
    "zlib1g-dev" \
    "pkg-config" \
    && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy workspace configuration files
COPY turbo.json package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY ./bin/turbo ./bin/turbo
COPY ./patches ./patches

# Copy Rust workspace (needed for cyclotron)
COPY ./rust ./rust

# Copy common packages
COPY ./common/hogvm/typescript/ ./common/hogvm/typescript/
COPY ./common/esbuilder/ ./common/esbuilder/
COPY ./common/plugin_transpiler/ ./common/plugin_transpiler/

# Copy plugin-server package files
COPY ./plugin-server/package.json ./plugin-server/tsconfig.json ./plugin-server/

# Enable pnpm and install dependencies
RUN corepack enable

# Install all dependencies with cache optimization
RUN --mount=type=cache,id=pnpm,target=/tmp/pnpm-store \
    NODE_OPTIONS="--max-old-space-size=16384" pnpm install --frozen-lockfile --store-dir /tmp/pnpm-store

# Copy source code
COPY ./plugin-server/src/ ./plugin-server/src/
COPY ./plugin-server/tests/ ./plugin-server/tests/
COPY ./common/hogvm/typescript/src/ ./common/hogvm/typescript/src/

# Build cyclotron first (Rust dependencies)
RUN NODE_OPTIONS="--max-old-space-size=16384" bin/turbo --filter=@posthog/cyclotron build

# Build hogvm
RUN NODE_OPTIONS="--max-old-space-size=16384" bin/turbo --filter=@posthog/hogvm build

# Build plugin-server
RUN NODE_OPTIONS="--max-old-space-size=16384" bin/turbo --filter=@posthog/plugin-server build

# Install production dependencies only
RUN --mount=type=cache,id=pnpm,target=/tmp/pnpm-store \
    corepack enable && \
    NODE_OPTIONS="--max-old-space-size=16384" pnpm --filter=@posthog/plugin-server install --frozen-lockfile --store-dir /tmp/pnpm-store --prod && \
    NODE_OPTIONS="--max-old-space-size=16384" bin/turbo --filter=@posthog/plugin-server prepare

# ===========================================
# Stage 2: Runtime Environment
# ===========================================
FROM node:18.19.1-bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    "ca-certificates" \
    "curl" \
    "libssl3" \
    && \
    rm -rf /var/lib/apt/lists/*

# Install pnpm
RUN npm install -g pnpm

# Create non-root user (handle existing GID/UID with logging)
RUN echo "Checking for existing group posthog..." && \
    if ! getent group posthog > /dev/null 2>&1; then \
        echo "Group posthog not found, creating..." && \
        if getent group 1000 > /dev/null 2>&1; then \
            echo "GID 1000 already exists, renaming existing group to posthog..." && \
            groupmod -n posthog $(getent group 1000 | cut -d: -f1); \
        else \
            echo "Creating new group posthog with GID 1000..." && \
            groupadd -g 1000 posthog; \
        fi; \
    else \
        echo "Group posthog already exists"; \
    fi && \
    echo "Checking for existing user posthog..." && \
    if ! getent passwd posthog > /dev/null 2>&1; then \
        echo "User posthog not found, creating..." && \
        if getent passwd 1000 > /dev/null 2>&1; then \
            echo "UID 1000 already exists, renaming existing user to posthog..." && \
            usermod -l posthog -g posthog $(getent passwd 1000 | cut -d: -f1); \
        else \
            echo "Creating new user posthog with UID 1000..." && \
            useradd -r -g posthog -u 1000 posthog; \
        fi; \
    else \
        echo "User posthog already exists"; \
    fi && \
    echo "User setup completed. Current user/group info:" && \
    id posthog && \
    getent group posthog

WORKDIR /app

# Copy built artifacts from builder stage
COPY --from=builder --chown=posthog:posthog /app/plugin-server/dist ./plugin-server/dist
COPY --from=builder --chown=posthog:posthog /app/plugin-server/node_modules ./plugin-server/node_modules
COPY --from=builder --chown=posthog:posthog /app/plugin-server/package.json ./plugin-server/package.json

# Copy workspace dependencies
COPY --from=builder --chown=posthog:posthog /app/node_modules ./node_modules
COPY --from=builder --chown=posthog:posthog /app/common/hogvm/typescript/dist ./common/hogvm/typescript/dist
COPY --from=builder --chown=posthog:posthog /app/common/hogvm/typescript/node_modules ./common/hogvm/typescript/node_modules
COPY --from=builder --chown=posthog:posthog /app/common/hogvm/typescript/package.json ./common/hogvm/typescript/package.json

# Copy cyclotron artifacts
COPY --from=builder --chown=posthog:posthog /app/rust/cyclotron-node/dist ./rust/cyclotron-node/dist
COPY --from=builder --chown=posthog:posthog /app/rust/cyclotron-node/package.json ./rust/cyclotron-node/package.json
COPY --from=builder --chown=posthog:posthog /app/rust/cyclotron-node/index.node ./rust/cyclotron-node/index.node

# Copy workspace configuration
COPY --chown=posthog:posthog pnpm-workspace.yaml pnpm-lock.yaml ./

# Copy GeoIP database
COPY --chown=posthog:posthog share/GeoLite2-City.mmdb ./share/GeoLite2-City.mmdb

# Create necessary directories with proper permissions
RUN mkdir -p .tmp/sessions/session-buffer-files && \
    chown -R posthog:posthog .tmp

# Switch to non-root user
USER posthog

# Set environment variables
ENV NODE_ENV=production \
    BASE_DIR=/app

# Expose plugin server port
EXPOSE 6738

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:6738/health || exit 1

# Default command
CMD ["node", "plugin-server/dist/index.js"]

# ===========================================
# Stage 3: Development Environment (Optional)
# ===========================================
FROM runtime AS development

# Install development dependencies
USER root
RUN --mount=type=cache,id=pnpm,target=/tmp/pnpm-store \
    pnpm install --frozen-lockfile --store-dir /tmp/pnpm-store

# Copy source code for development
COPY --chown=posthog:posthog ./plugin-server/src/ ./plugin-server/src/
COPY --chown=posthog:posthog ./common/hogvm/typescript/src/ ./common/hogvm/typescript/src/

USER posthog

# Development command with nodemon
CMD ["pnpm", "--filter=@posthog/plugin-server", "start:dev"] 