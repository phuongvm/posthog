# PostHog Plugins - Docker Build

Docker build configuration cho PostHog Plugins với multi-stage build tối ưu và Docker Compose profiles.

## 🏗️ Build Architecture

### Multi-stage Dockerfile

```
builder (Rust + Node.js) → runtime (Production) → development (Optional)
```

1. **builder stage**: Build tất cả dependencies và artifacts
2. **runtime stage**: Production image với minimal footprint
3. **development stage**: Development image với hot-reload

## 🚀 Quick Start

### 1. Build Images

```bash
# Build production image
docker build --target runtime -t posthog/plugins:latest -f plugin-server/Dockerfile .

# Build development image
docker build --target development -t posthog/plugins:dev -f plugin-server/Dockerfile .
```

### 2. Using Build Script

```bash
cd plugin-server

# Make script executable
chmod +x build.sh

# Build images only
./build.sh

# Build and run plugins only (assumes PostHog platform is running)
./build.sh --run

# Build and run development plugins only
./build.sh --dev

# Build and run complete platform (all services)
./build.sh --platform

# Build and run platform with development plugins
./build.sh --platform-dev
```

### 3. Using Docker Compose with Profiles

#### Plugins Only (Default)
```bash
cd plugin-server

# Start plugins only (assumes PostHog platform is running)
docker-compose up plugins

# Start development plugins only
docker-compose up plugins-dev

# Start in background
docker-compose up -d plugins
```

#### Complete Platform (All Services)
```bash
cd plugin-server

# Start all services including dependencies
docker-compose --profile platform up

# Start all services in background
docker-compose --profile platform up -d

# Start only platform services (no plugins)
docker-compose --profile platform up postgres redis kafka clickhouse objectstorage

# Run migrations only
docker-compose --profile platform run --rm migrate
```

## 📁 File Structure

```
plugin-server/
├── Dockerfile              # Multi-stage Dockerfile
├── docker-compose.yml      # Docker Compose with profiles
├── build.sh               # Build script
└── README.md              # This file
```

## 🎯 Docker Compose Profiles

### Default Profile (No Profile)
- **plugins**: Production plugins
- **plugins-dev**: Development plugins

### Platform Profile
- **postgres**: PostgreSQL database
- **redis**: Redis cache
- **zookeeper**: Kafka coordination
- **kafka**: Message broker
- **clickhouse**: Analytics database
- **objectstorage**: MinIO object storage
- **migrate**: Database migrations

### Usage Examples

```bash
# Plugins only (assumes PostHog platform is running)
docker-compose up plugins

# Complete platform with all services
docker-compose --profile platform up

# Mix profiles - start platform services + plugins
docker-compose --profile platform up postgres redis kafka plugins

# Development with hot reload
docker-compose up plugins-dev
```

## 🔧 Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `postgres://posthog:posthog@postgres:5432/posthog` |
| `KAFKA_HOSTS` | Kafka broker list | `kafka:9092` |
| `REDIS_URL` | Redis connection string | `redis://redis:6379/` |
| `CLICKHOUSE_HOST` | ClickHouse host | `clickhouse` |
| `OBJECT_STORAGE_ENDPOINT` | MinIO endpoint | `http://objectstorage:19000` |
| `DEBUG` | Enable debug mode | `1` |

### Ports

| Service | Port | Description |
|---------|------|-------------|
| Plugins | 6738 | Main plugins port |
| Plugins Dev | 6739 | Development server port |
| PostgreSQL | 5432 | Database |
| Redis | 6379, 6479 | Cache & CDP |
| Kafka | 9092 | Message broker |
| ClickHouse | 8123, 9000 | Analytics database |
| MinIO | 19000, 19001 | Object storage |

## 🐳 Docker Images

### Production Image (`posthog/plugins:latest`)

- **Base**: `node:18.19.1-bookworm-slim`
- **User**: `posthog` (non-root)
- **Size**: ~500MB
- **Features**:
  - Optimized for production
  - Minimal dependencies
  - Health checks
  - Security hardened

### Development Image (`posthog/plugins:dev`)

- **Base**: Production image
- **Size**: ~800MB
- **Features**:
  - Development dependencies
  - Source code mounting
  - Hot reload support
  - Debug tools

## 🔍 Troubleshooting

### Build Issues

```bash
# Clear Docker cache
docker builder prune

# Build with no cache
docker build --no-cache -t posthog/plugins .

# Check build context
docker build --progress=plain -t posthog/plugins .
```

### Runtime Issues

```bash
# Check container logs
docker-compose logs plugins

# Access container shell
docker-compose exec plugins sh

# Check health status
docker-compose ps
```

### Profile Issues

```bash
# List available services
docker-compose config --services

# List services by profile
docker-compose config --services --profile platform

# Check compose configuration
docker-compose config
```

### Memory Issues

```bash
# Increase Node.js memory
NODE_OPTIONS="--max-old-space-size=16384" docker-compose up plugins

# Monitor memory usage
docker stats
```

## 📊 Performance

### Build Time Optimization

- **Cache layers**: Dependencies cached separately
- **Multi-stage**: Only necessary artifacts copied
- **Parallel builds**: Independent stages
- **BuildKit**: Modern Docker build engine

### Runtime Optimization

- **Alpine base**: Minimal image size
- **Non-root user**: Security
- **Health checks**: Monitoring
- **Resource limits**: Memory/CPU constraints

## 🔒 Security

- Non-root user (`posthog:posthog`)
- Minimal attack surface
- No development tools in production
- Regular security updates

## 🧪 Testing

### Unit Tests

```bash
# Run tests in container
docker run --rm posthog/plugins:dev pnpm test
```

### Integration Tests

```bash
# Start test environment
docker-compose --profile platform up -d

# Run integration tests
docker-compose run --rm plugins pnpm test:integration
```

## 📈 Monitoring

### Health Checks

```bash
# Check health endpoint
curl http://localhost:6738/health

# Docker health status
docker inspect --format='{{.State.Health.Status}}' container_name
```

### Logs

```bash
# Follow logs
docker-compose logs -f plugins

# Structured logging
docker-compose logs plugins | jq
```

## 🔄 CI/CD Integration

### GitHub Actions

```yaml
- name: Build Plugins
  run: |
    cd plugin-server
    ./build.sh
    
- name: Push to Registry
  run: |
    docker push posthog/plugins:latest
```

### Docker Hub

```bash
# Tag for registry
docker tag posthog/plugins:latest your-registry/plugins:latest

# Push to registry
docker push your-registry/plugins:latest
```

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Make changes
4. Test with `./build.sh --dev`
5. Submit pull request

## 📝 License

MIT License - see [LICENSE](../LICENSE) for details.

---

**Happy Building! 🚀** 