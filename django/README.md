# PostHog Django Services

Unified Docker setup cho tất cả Django services trong PostHog.

## Tổng quan

Tất cả các Django services (web, worker, migrate, temporal-django-worker, asyncmigrationscheck) đều sử dụng chung một Docker image vì chúng có:

- **Cùng base image** (Python 3.11 + Node.js)
- **Cùng volume mount** `.:/app/posthog`
- **Cùng environment variables** 
- **Chỉ khác nhau ở command** để start service

## Services

### 1. Web Service
- **Command**: `./bin/start-backend & ./bin/start-frontend`
- **Mục đích**: Django web server + frontend
- **Container**: `posthog-web`

### 2. Worker Service  
- **Command**: `./bin/docker-worker-celery --with-scheduler`
- **Mục đích**: Celery worker với scheduler
- **Container**: `posthog-worker`

### 3. Migrate Service
- **Command**: `python manage.py migrate && python manage.py migrate_clickhouse && python manage.py run_async_migrations`
- **Mục đích**: Database migrations
- **Container**: `posthog-migrate`

### 4. Async Migrations Check
- **Command**: `python manage.py run_async_migrations --check`
- **Mục đích**: Kiểm tra async migrations
- **Container**: `posthog-asyncmigrationscheck`

### 5. Temporal Django Worker
- **Command**: `./bin/temporal-django-worker`
- **Mục đích**: Temporal workflow worker
- **Container**: `posthog-temporal-django-worker`

## Cấu trúc Files

```
django/
├── Dockerfile                    # Unified Docker image
├── docker-compose.yml     # Docker Compose cho Django services
├── manage-django.sh             # Script quản lý services
└── README.md                    # Tài liệu này
```

## Sử dụng

### 1. Build image
```bash
./django/manage-django.sh build
```

### 2. Start tất cả services
```bash
./django/manage-django.sh start
```

### 3. Start service cụ thể
```bash
./django/manage-django.sh start web
./django/manage-django.sh start worker
./django/manage-django.sh start migrate
```

### 4. Run migrations
```bash
./django/manage-django.sh migrate
```

### 5. Check async migrations
```bash
./django/manage-django.sh check-migrations
```

### 6. Xem logs
```bash
./django/manage-django.sh logs web
./django/manage-django.sh logs worker
./django/manage-django.sh logs
```

### 7. Stop services
```bash
./django/manage-django.sh stop web
./django/manage-django.sh stop
```

### 8. Restart services
```bash
./django/manage-django.sh restart worker
./django/manage-django.sh restart
```

## Lợi ích của Unified Image

### 1. **Consistency**
- Tất cả services dùng cùng version Python, Node.js, dependencies
- Không có conflict giữa các services

### 2. **Efficiency** 
- Chỉ cần build 1 image thay vì nhiều image riêng biệt
- Tiết kiệm disk space và build time

### 3. **Maintainability**
- Dễ maintain và update dependencies
- Chỉ cần sửa 1 Dockerfile

### 4. **Development Experience**
- Hot reload cho tất cả services
- Source code được mount vào tất cả containers

## Network Configuration

Tất cả services đều dùng external network `posthog_default` để kết nối với:

- **Database**: `db:5432`
- **Redis**: `redis:6379` 
- **Kafka**: `kafka:9092`
- **ClickHouse**: `clickhouse:8123`
- **Plugins**: `plugins:6738`

## Environment Variables

Tất cả services đều dùng chung environment variables từ `&worker_env`:

```yaml
environment: &worker_env
  OTEL_SDK_DISABLED: 'true'
  DISABLE_SECURE_SSL_REDIRECT: 'true'
  IS_BEHIND_PROXY: 'true'
  DATABASE_URL: 'postgres://posthog:posthog@db:5432/posthog'
  CLICKHOUSE_HOST: 'clickhouse'
  # ... và nhiều variables khác
```

## Troubleshooting

### 1. Service không start được
```bash
# Check logs
./django/manage-django.sh logs [service-name]

# Check dependencies
docker ps | grep posthog
```

### 2. Migration failed
```bash
# Run migration manually
./django/manage-django.sh migrate

# Check async migrations
./django/manage-django.sh check-migrations
```

### 3. Network issues
```bash
# Check network
docker network ls | grep posthog

# Restart main stack
docker-compose down
docker-compose up -d
```

## Best Practices

1. **Luôn start main PostHog stack trước** (db, redis, kafka, clickhouse)
2. **Run migrations trước khi start services**
3. **Check async migrations định kỳ**
4. **Monitor logs của các services**
5. **Restart services khi có code changes**

## Migration từ Old Setup

Nếu bạn đang dùng setup cũ với volume mount `.:/app/posthog`:

1. Stop old services
2. Build new unified image
3. Start new services
4. Verify everything works

```bash
# Stop old services
docker-compose down web worker migrate temporal-django-worker

# Build and start new services  
./django/manage-django.sh build
./django/manage-django.sh start
``` 