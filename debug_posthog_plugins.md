# Debug PostHog Plugin Server - Hướng dẫn khắc phục sự cố

## 📋 Tổng quan

Tài liệu này tổng hợp tất cả các vấn đề thường gặp khi setup và chạy PostHog Plugin Server, cùng với cách khắc phục chi tiết.

## 🐳 Docker Build Process cho PostHog Plugins

### 🔍 Phân tích hiện tại

#### 1. **Multi-stage Dockerfile**
PostHog sử dụng multi-stage build với 4 stages chính:
- `frontend-build`: Build frontend assets
- `plugin-server-build`: Build plugin-server (Node.js) + dependencies
- `posthog-build`: Build Django app + Python dependencies
- `fetch-geoip-db`: Download GeoIP database
- Final stage: Combine tất cả artifacts

#### 2. **Plugin Server Build Stage**
```dockerfile
FROM ghcr.io/posthog/rust-node-container:bookworm_rust_1.82-node_18.19.1 AS plugin-server-build

# System dependencies
RUN apt-get install -y make g++ gcc python3 libssl-dev zlib1g-dev

# Build process:
# 1. Install Node.js dependencies
# 2. Build plugin-transpiler
# 3. Build cyclotron (Rust)
# 4. Build plugin-server
# 5. Install production dependencies only
```

#### 3. **Docker Compose Configuration**
```yaml
plugins:
  extends:
    file: docker-compose.base.yml
    service: plugins
  build: .  # Build từ root Dockerfile
  volumes:
    # Mount workspace packages cho development
    - ./common/eslint_rules:/code/common/eslint_rules
    - ./ee/frontend:/code/ee/frontend
    - ./frontend:/code/frontend
    - ./plugin-server:/code/plugin-server
    # Mount node_modules (built locally)
    - ./node_modules:/code/node_modules
    - ./plugin-server/node_modules:/code/plugin-server/node_modules
```

### ⚠️ Vấn đề hiện tại

#### 1. **Development vs Production Mismatch**
- **Development**: Mount volumes để hot-reload
- **Production**: Copy artifacts từ build stages
- **Vấn đề**: Có thể gây inconsistency giữa dev và prod

#### 2. **Build Context Size**
- Dockerfile copy toàn bộ workspace
- `.dockerignore` loại trừ nhiều files nhưng vẫn lớn
- Build time có thể chậm

#### 3. **Dependency Management**
- Plugin-server phụ thuộc vào workspace packages
- Cần build `@posthog/hogvm`, `@posthog/cyclotron` trước
- Rust dependencies cần compile

### 🔧 Cải thiện Build Process

#### 1. **Tối ưu Build Context**
```dockerfile
# Chỉ copy files cần thiết cho plugin-server
COPY turbo.json package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY ./bin/turbo ./bin/turbo
COPY ./patches ./patches
COPY ./rust ./rust
COPY ./common/hogvm/typescript/ ./common/hogvm/typescript/
COPY ./plugin-server/package.json ./plugin-server/tsconfig.json ./plugin-server/
```

#### 2. **Separate Plugin Server Dockerfile**
Tạo `plugin-server/Dockerfile` riêng:
```dockerfile
FROM ghcr.io/posthog/rust-node-container:bookworm_rust_1.82-node_18.19.1

WORKDIR /app

# Copy only plugin-server specific files
COPY package.json pnpm-lock.yaml ./
COPY plugin-server/package.json ./plugin-server/
COPY common/hogvm/typescript/package.json ./common/hogvm/typescript/

# Install dependencies
RUN corepack enable && pnpm install --frozen-lockfile

# Copy source code
COPY plugin-server/src/ ./plugin-server/src/
COPY common/hogvm/typescript/src/ ./common/hogvm/typescript/src/

# Build
RUN pnpm --filter=@posthog/hogvm build
RUN pnpm --filter=@posthog/plugin-server build

# Production dependencies only
RUN pnpm --filter=@posthog/plugin-server install --prod

EXPOSE 6738
CMD ["node", "plugin-server/dist/index.js"]
```

#### 3. **Docker Compose Optimization**
```yaml
plugins:
  build:
    context: .
    dockerfile: plugin-server/Dockerfile
  environment:
    DATABASE_URL: 'postgres://posthog:posthog@db:5432/posthog'
    KAFKA_HOSTS: 'kafka:9092'
    REDIS_URL: 'redis://redis:6379/'
  depends_on:
    - db
    - redis
    - kafka
```

### 🚀 Build Commands

#### 1. **Build Plugin Server Image**
```bash
# Build từ root (hiện tại)
docker build -t posthog/plugin-server .

# Build riêng plugin-server (đề xuất)
cd plugin-server
docker build -t posthog/plugin-server .
```

#### 2. **Build với Docker Compose**
```bash
# Build tất cả services
docker-compose build

# Build chỉ plugin-server
docker-compose build plugins

# Build và run
docker-compose up --build plugins
```

#### 3. **Development Build**
```bash
# Build với development dependencies
docker build --target plugin-server-build -t posthog/plugin-server:dev .

# Run với volume mounts
docker-compose -f docker-compose.dev.yml up plugins
```

### 📊 Build Performance Tips

#### 1. **Cache Optimization**
```dockerfile
# Sử dụng build cache cho dependencies
RUN --mount=type=cache,id=pnpm,target=/tmp/pnpm-store \
    pnpm install --frozen-lockfile --store-dir /tmp/pnpm-store
```

#### 2. **Layer Optimization**
```dockerfile
# Copy package files trước source code
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Copy source code sau
COPY src/ ./src/
RUN pnpm build
```

#### 3. **Multi-platform Build**
```bash
# Build cho multiple architectures
docker buildx build --platform linux/amd64,linux/arm64 -t posthog/plugin-server .
```

### 🔍 Troubleshooting Build Issues

#### 1. **Memory Issues**
```bash
# Tăng memory cho Node.js build
NODE_OPTIONS="--max-old-space-size=16384" pnpm build
```

#### 2. **Rust Build Issues**
```bash
# Cài Rust dependencies
apt-get install -y make g++ gcc libssl-dev

# Set Rust target
rustup target add x86_64-unknown-linux-gnu
```

#### 3. **Dependency Resolution**
```bash
# Clear pnpm cache
pnpm store prune

# Reinstall dependencies
rm -rf node_modules
pnpm install --frozen-lockfile
```

## 🔧 Khắc phục Build Plugins Image - Network Configuration

### 🎯 Vấn đề chính
Khi build và chạy plugin-server container riêng biệt, cần kết nối với các services từ main PostHog stack (db, redis, kafka, etc.) mà không hardcode IP addresses.

### ✅ Giải pháp hoàn chỉnh

#### 1. **Tạo Separate Plugin Server Dockerfile**
```dockerfile
# plugin-server/Dockerfile
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

# Runtime stage
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

# Create non-root user
RUN groupadd -g 1000 posthog && \
    useradd -r -g posthog -u 1000 posthog

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
```

#### 2. **Cấu hình Docker Compose với Network**
```yaml
# plugin-server/docker-compose.yml
services:
  # Plugin Server - Production Build
  plugins:
    build:
      context: ..
      dockerfile: plugin-server/Dockerfile
      target: runtime
    ports:
      - "6738:6738"
    volumes:
      - ../share:/share
    environment:
      DATABASE_URL: 'postgres://posthog:posthog@db:5432/posthog'
      PERSONS_DATABASE_URL: 'postgres://posthog:posthog@db:5432/posthog'
      KAFKA_HOSTS: 'kafka:9092'
      REDIS_URL: 'redis://redis:6379/'
      CDP_REDIS_HOST: 'redis7'
      CDP_REDIS_PORT: '6379'
      CDP_REDIS_PASSWORD: ''
      CLICKHOUSE_HOST: 'clickhouse'
      CLICKHOUSE_DATABASE: 'posthog'
      CLICKHOUSE_SECURE: 'false'
      CLICKHOUSE_VERIFY: 'false'
      CYCLOTRON_DATABASE_URL: 'postgres://posthog:posthog@db:5432/cyclotron'
      OBJECT_STORAGE_ENDPOINT: 'http://objectstorage:19000'
      OBJECT_STORAGE_REGION: 'us-east-1'
      OBJECT_STORAGE_ACCESS_KEY_ID: 'object_storage_root_user'
      OBJECT_STORAGE_SECRET_ACCESS_KEY: 'object_storage_root_password'
      OBJECT_STORAGE_BUCKET: 'posthog'
      DEBUG: '1'

  # Plugin Server - Development Build
  plugins-dev:
    build:
      context: ..
      dockerfile: plugin-server/Dockerfile
      target: development
    ports:
      - "6739:6738"
    volumes:
      # Mount source code for hot reload
      - ../plugin-server/src:/app/plugin-server/src:ro
      - ../common/hogvm/typescript/src:/app/common/hogvm/typescript/src:ro
      # Mount GeoIP database
      - ../share:/share
    environment:
      DATABASE_URL: 'postgres://posthog:posthog@db:5432/posthog'
      PERSONS_DATABASE_URL: 'postgres://posthog:posthog@db:5432/posthog'
      KAFKA_HOSTS: 'kafka:9092'
      REDIS_URL: 'redis://redis:6379/'
      CDP_REDIS_HOST: 'redis7'
      CDP_REDIS_PORT: '6379'
      CDP_REDIS_PASSWORD: ''
      CLICKHOUSE_HOST: 'clickhouse'
      CLICKHOUSE_DATABASE: 'posthog'
      CLICKHOUSE_SECURE: 'false'
      CLICKHOUSE_VERIFY: 'false'
      CYCLOTRON_DATABASE_URL: 'postgres://posthog:posthog@db:5432/cyclotron'
      OBJECT_STORAGE_ENDPOINT: 'http://objectstorage:19000'
      OBJECT_STORAGE_REGION: 'us-east-1'
      OBJECT_STORAGE_ACCESS_KEY_ID: 'object_storage_root_user'
      OBJECT_STORAGE_SECRET_ACCESS_KEY: 'object_storage_root_password'
      OBJECT_STORAGE_BUCKET: 'posthog'
      DEBUG: '1'
      NODE_ENV: 'development'

networks:
  default:
    external: true
    name: posthog_default
```

#### 3. **Network Configuration Strategy**
```bash
# 1. Kiểm tra network hiện tại của main PostHog
docker network ls | grep posthog

# 2. Kiểm tra aliases của các services
docker inspect posthog-kafka-1 | grep -A 10 -B 5 "Aliases"
docker inspect posthog-redis7-1 | grep -A 10 -B 5 "Aliases"

# 3. Sử dụng hostnames thực tế:
# - kafka (alias của posthog-kafka-1)
# - redis7 (alias của posthog-redis7-1)
# - db, clickhouse, objectstorage (từ main PostHog)
```

#### 4. **Build và Run Commands**
```bash
# Build plugin-server image
cd plugin-server
docker-compose build plugins

# Run plugin-server
docker-compose up plugins

# Build và run development version
docker-compose build plugins-dev
docker-compose up plugins-dev
```

### 🔍 Các vấn đề đã khắc phục

#### 1. **Thiếu GeoIP Database**
**Vấn đề:** `ENOENT: no such file or directory, open '../share/GeoLite2-City.mmdb'`
**Giải pháp:**
- Copy file GeoIP database trong Dockerfile
- Mount volume `../share:/share` trong docker-compose
- Tạo thư mục `.tmp` với đúng permissions

#### 2. **Permission Issues**
**Vấn đề:** `EACCES: permission denied, mkdir '.tmp/sessions/session-buffer-files'`
**Giải pháp:**
```dockerfile
# Create necessary directories with proper permissions
RUN mkdir -p .tmp/sessions/session-buffer-files && \
    chown -R posthog:posthog .tmp
```

#### 3. **Network Connectivity**
**Vấn đề:** Không kết nối được với services từ main PostHog
**Giải pháp:**
- Sử dụng external network `posthog_default`
- Dùng hostnames thực tế thay vì IP addresses
- Không cần `extra_hosts` hay hardcode IP

#### 4. **Redis CDP Connection**
**Vấn đề:** `connect ECONNREFUSED 127.0.0.1:6479`
**Giải pháp:**
- Sử dụng `redis7` hostname (alias của posthog-redis7-1)
- Port 6379 (internal port, không phải host port 6479)

#### 5. **Kafka Connection**
**Vấn đề:** `Local: Assign partitions` errors
**Giải pháp:**
- Sử dụng `kafka` hostname (alias của posthog-kafka-1)
- Đảm bảo Kafka service đang chạy trong main PostHog stack

### ✅ Kết quả cuối cùng

Plugin-server container có thể:
- ✅ Kết nối với tất cả services từ main PostHog stack
- ✅ Sử dụng hostnames thay vì IP addresses
- ✅ Truy cập GeoIP database
- ✅ Tạo thư mục cần thiết với đúng permissions
- ✅ Build và run độc lập mà không cần hardcode

### 🚀 Best Practices

1. **Luôn dùng external network** để kết nối giữa các docker-compose stacks
2. **Sử dụng hostnames thực tế** từ service aliases
3. **Mount volumes cho development** thay vì copy files
4. **Tạo thư mục cần thiết** trong Dockerfile với đúng permissions
5. **Sử dụng multi-stage build** để tối ưu image size

## 🚨 Các vấn đề đã gặp và cách khắc phục

### 1. **Thiếu module Python**
**Vấn đề:** Lỗi `ModuleNotFoundError` khi chạy plugin-server
**Giải pháp:** 
```bash
# Cài Python dependencies
cd /home/devcontainers/posthog
pip install -r requirements.txt
```

### 2. **Lỗi pnpm workspace không tìm thấy package**
**Vấn đề:** `Cannot find package '@posthog/hogvm'` do mount volume không đủ
**Giải pháp:**
- Mount đủ các thư mục workspace cần thiết trong docker-compose
- Build `node_modules` và `dist` ngoài local trước khi chạy container

### 3. **Thiếu GeoIP database**
**Vấn đề:** Lỗi `MMDB_FILE_LOCATION` không tìm thấy file
**Giải pháp:**
- Tạo thư mục `share/` và download GeoIP database
- Hoặc để plugin-server tự động download (đã hoạt động)

### 4. **Thiếu thư mục frontend/dist**
**Vấn đề:** Lỗi không tìm thấy `frontend/dist`
**Giải pháp:**
```bash
cd frontend
pnpm install
pnpm build
```

### 5. **Lỗi script pnpm start:dev:no-build**
**Vấn đề:** Script không tồn tại trong package.json
**Giải pháp:** Sử dụng script có sẵn `pnpm start:dev`

### 6. **Lỗi permission khi chạy pnpm install**
**Vấn đề:** EACCES permission denied
**Giải pháp:**
```bash
# Cài Node.js và pnpm bằng nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 18
npm install -g pnpm
```

### 7. **Lỗi cargo permission denied**
**Vấn đề:** Không có quyền build Rust code
**Giải pháp:**
```bash
# Cài Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
```

### 8. **Thiếu pkg-config và libssl-dev**
**Vấn đề:** Lỗi build Rust dependencies
**Giải pháp:**
```bash
sudo apt update
sudo apt install pkg-config libssl-dev
```

### 9. **Lỗi thiếu package @posthog/hogvm**
**Vấn đề:** Chưa build đúng thư mục
**Giải pháp:**
```bash
cd common/hogvm/typescript
pnpm install
pnpm build
```

### 10. **Lỗi EACCES khi build hogvm**
**Vấn đề:** Thiếu quyền hoặc script không tồn tại
**Giải pháp:**
```bash
# Kiểm tra script tồn tại
ls -la package.json
# Chạy với quyền đúng
pnpm build
```

### 11. **Lỗi Kafka connection timeout**
**Vấn đề:** Không kết nối được Kafka broker
**Giải pháp:**
- Chạy Kafka bằng docker-compose
- Kiểm tra Kafka đang chạy trên port 9092

### 12. **Lỗi Redis port 6479 không kết nối**
**Vấn đề:** Redis không expose port 6479
**Giải pháp:**
```yaml
# Trong docker-compose.yml
redis:
  ports:
    - "6379:6379"
    - "6479:6479"  # Thêm port này
```

### 13. **Lỗi Kafka broker hostname**
**Vấn đề:** librdkafka và KafkaJS cần hostname khác nhau
**Giải pháp:**
```bash
# Thêm vào /etc/hosts
echo "127.0.0.1 kafka" | sudo tee -a /etc/hosts
```

### 14. **Biến môi trường KAFKA_PRODUCER_METADATA_BROKER_LIST không được load**
**Vấn đề:** `getKafkaConfigFromEnv` bỏ qua biến nếu key đã có trong defaultConfig
**Giải pháp:** Sử dụng biến môi trường khác hoặc set trực tiếp khi chạy

## 🔧 Setup hoàn chỉnh cho lần sau

### 1. **Cài đặt dependencies**
```bash
# Cài Node.js và pnpm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 18
npm install -g pnpm

# Cài Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Cài system dependencies
sudo apt update
sudo apt install pkg-config libssl-dev mprocs brotli
```

### 2. **Build dependencies**
```bash
# Build frontend
cd frontend
pnpm install
pnpm build

# Build hogvm
cd ../common/hogvm/typescript
pnpm install
pnpm build

# Cài Python dependencies
cd /home/devcontainers/posthog
pip install -r requirements.txt
```

### 3. **Setup hosts file**
```bash
echo "127.0.0.1 kafka" | sudo tee -a /etc/hosts
```

### 4. **Chạy services**
```bash
# Chạy dependencies bằng docker-compose
docker-compose up -d kafka redis clickhouse postgres

# Chạy plugin-server
cd plugin-server
pnpm start:dev
```

## ✅ Kết quả cuối cùng

Plugin-server đã chạy thành công với:
- ✅ Kafka consumer rebalancing bình thường
- ✅ Session recording hoạt động
- ✅ GeoIP database tự động cập nhật
- ✅ Database connection ổn định
- ✅ Redis connection không lỗi
- ✅ Tất cả consumer groups đã join thành công

## 📊 Log patterns bình thường

### Kafka Consumer Rebalancing (BÌNH THƯỜNG)
```
[INFO] 🔁 kafka_consumer_rebalancing
    topicPartitions: [...]
    err: {
      "code": -175,  // Đây là bình thường!
      "message": "Local: Assign partitions"
    }
```

### Session Recording (BÌNH THƯỜNG)
```
[INFO] 🔁 session_batch_manager_flushing
    batchSize: 0  // Bình thường khi chưa có data
[INFO] 🔁 session_batch_recorder_flushed_no_sessions
```

### Consumer Status (BÌNH THƯỜNG)
```
[INFO] ℹ️ consumer_status
    groupId: "clickhouse-plugin-server-async-webhooks"
    offsets: {}
```

## ⚠️ Lưu ý quan trọng

1. **Các log "rebalancing" và "batchSize: 0" là hành vi bình thường, không phải lỗi!**
2. **Error code -175 trong Kafka là bình thường** - đây là "Local: Assign partitions"
3. **Plugin-server sẽ tự động download GeoIP database** nếu cần
4. **Kafka consumer groups sẽ rebalance liên tục** - đây là hành vi chuẩn
5. **Session recording batch size 0 là bình thường** khi chưa có session data

## 🔍 Troubleshooting nhanh

### Kiểm tra services đang chạy
```bash
# Kiểm tra Kafka
docker-compose ps kafka

# Kiểm tra Redis
docker-compose ps redis

# Kiểm tra ports
netstat -tlnp | grep -E ':(9092|6379|6479)'
```

### Kiểm tra hosts file
```bash
cat /etc/hosts | grep kafka
```

### Kiểm tra dependencies
```bash
# Node.js
node --version
pnpm --version

# Rust
rustc --version
cargo --version

# Python
python --version
pip list | grep posthog
```

## 📝 Checklist setup

- [ ] Cài Node.js 18+ và pnpm
- [ ] Cài Rust và cargo
- [ ] Cài system dependencies (pkg-config, libssl-dev)
- [ ] Build frontend (`pnpm build`)
- [ ] Build hogvm (`cd common/hogvm/typescript && pnpm build`)
- [ ] Cài Python dependencies (`pip install -r requirements.txt`)
- [ ] Thêm `127.0.0.1 kafka` vào `/etc/hosts`
- [ ] Chạy docker-compose services
- [ ] Chạy plugin-server (`pnpm start:dev`)

---

**Tác giả:** Generated from PostHog plugin-server debugging session  
**Ngày tạo:** 2025-01-24  
**Phiên bản:** 1.1 (Added Docker Build Process section) 