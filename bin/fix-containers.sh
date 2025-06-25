#!/bin/bash
set -e

echo "🔧 Fixing PostHog containers..."

# Fix web container (same issue as worker)
echo "🌐 Fixing web container..."
docker-compose exec web pip install django-linear-migrations==2.16.* || true
docker-compose exec web mkdir -p /python-runtime/lib/python3.11/site-packages/ || true
docker-compose exec web cp -r /usr/local/lib/python3.11/site-packages/django_linear_migrations /python-runtime/lib/python3.11/site-packages/ || true
docker-compose exec web cp -r /usr/local/lib/python3.11/site-packages/django_linear_migrations-2.16.0.dist-info /python-runtime/lib/python3.11/site-packages/ || true

# Fix worker container (same issue as web)
echo "📦 Fixing worker container..."
docker-compose exec worker pip install django-linear-migrations==2.16.* || true
docker-compose exec worker mkdir -p /python-runtime/lib/python3.11/site-packages/ || true
docker-compose exec worker cp -r /usr/local/lib/python3.11/site-packages/django_linear_migrations /python-runtime/lib/python3.11/site-packages/ || true
docker-compose exec worker cp -r /usr/local/lib/python3.11/site-packages/django_linear_migrations-2.16.0.dist-info /python-runtime/lib/python3.11/site-packages/ || true

# Fix plugins container - add encryption keys
echo "🔐 Fixing plugins container..."
docker-compose exec plugins sh -c 'echo "ENCRYPTION_KEYS=test_key_1,test_key_2" >> /code/.env' || true

# Fix feature-flags container - download GeoIP database
echo "🌍 Fixing feature-flags container..."
docker-compose exec feature-flags mkdir -p /share || true
docker-compose exec feature-flags curl -s -L "https://mmdbcdn.posthog.net/" --http1.1 | brotli --decompress --output=/share/GeoLite2-City.mmdb || true

# Load Unit configuration for web container
echo "⚙️ Loading Unit configuration for web container..."
docker-compose exec web curl -X PUT --data-binary @/docker-entrypoint.d/unit.json --unix-socket /var/run/control.unit.sock http://localhost/config/ || true

# Restart containers
echo "🔄 Restarting containers..."
docker-compose restart web worker plugins feature-flags

echo "✅ Container fixes applied!"
echo "📋 Remaining issues:"
echo "   - property-defs-rs: Kafka topic 'clickhouse_events_json' needs to be created"
echo "   - This will be fixed when data starts flowing through the system" 