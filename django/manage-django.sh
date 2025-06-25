#!/bin/bash

# PostHog Django Services Management Script
# Unified management for web, worker, migrate, temporal-django-worker, etc.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DJANGO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$DJANGO_DIR")"
COMPOSE_FILE="$DJANGO_DIR/docker-compose.yml"
export COMPOSE_BAKE=true

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if PostHog network exists
check_network() {
    print_status "Checking if PostHog network exists..."
    if ! docker network ls | grep -q "posthog_default"; then
        print_error "PostHog network 'posthog_default' not found!"
        print_status "Please start the main PostHog stack first:"
        echo "  docker-compose up -d"
        exit 1
    fi
    print_success "PostHog network found"
}

# Function to check dependencies
check_dependencies() {
    print_status "Checking dependencies..."
    
    # Check if main PostHog services are running
    local required_services=("db" "redis" "kafka" "clickhouse")
    local missing_services=()
    
    for service in "${required_services[@]}"; do
        if ! docker ps --format "table {{.Names}}" | grep -q "posthog_${service}"; then
            missing_services+=("$service")
        fi
    done
    
    if [ ${#missing_services[@]} -gt 0 ]; then
        print_error "Missing required services: ${missing_services[*]}"
        print_status "Please start the main PostHog stack first:"
        echo "  docker-compose up -d"
        exit 1
    fi
    
    print_success "All dependencies are running"
}

# Function to build Django image
build_django() {
    print_status "Building Django unified image..."
    
    cd "$PROJECT_ROOT"
    
    # Build the Django image
    docker-compose -f "$COMPOSE_FILE" build 2>&1 | tee build.log
    
    if [ $? -eq 0 ]; then
        print_success "Django unified image built successfully"
    else
        print_error "Failed to build Django unified image"
        exit 1
    fi
}

# Function to start specific service
start_service() {
    local service=$1
    print_status "Starting $service..."
    
    # Stop existing service if running
    docker-compose -f "$COMPOSE_FILE" down "$service" 2>/dev/null || true
    
    # Start service
    docker-compose -f "$COMPOSE_FILE" up -d "$service"
    
    if [ $? -eq 0 ]; then
        print_success "$service started successfully"
        print_status "Container name: posthog-$service"
        print_status "View logs: docker-compose -f $COMPOSE_FILE logs -f $service"
    else
        print_error "Failed to start $service"
        exit 1
    fi
}

# Function to start all Django services
start_all() {
    print_status "Starting all Django services..."
    
    # Stop existing services
    docker-compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    
    # Start all services
    docker-compose -f "$COMPOSE_FILE" up -d
    
    if [ $? -eq 0 ]; then
        print_success "All Django services started successfully"
        print_status "Services: web, worker, migrate, asyncmigrationscheck, temporal-django-worker"
        print_status "View logs: docker-compose -f $COMPOSE_FILE logs -f"
    else
        print_error "Failed to start Django services"
        exit 1
    fi
}

# Function to run migration
run_migration() {
    print_status "Running database migrations..."
    
    # Run migrate service
    docker-compose -f "$COMPOSE_FILE" up migrate
    
    if [ $? -eq 0 ]; then
        print_success "Migrations completed successfully"
    else
        print_error "Migration failed"
        exit 1
    fi
}

# Function to check async migrations
check_async_migrations() {
    print_status "Checking async migrations..."
    
    # Run asyncmigrationscheck service
    docker-compose -f "$COMPOSE_FILE" up asyncmigrationscheck
    
    if [ $? -eq 0 ]; then
        print_success "Async migrations check completed"
    else
        print_error "Async migrations check failed"
        exit 1
    fi
}

# Function to show logs
show_logs() {
    local service=${1:-""}
    if [ -z "$service" ]; then
        print_status "Showing logs for all Django services..."
        docker-compose -f "$COMPOSE_FILE" logs -f
    else
        print_status "Showing logs for $service..."
        docker-compose -f "$COMPOSE_FILE" logs -f "$service"
    fi
}

# Function to stop services
stop_services() {
    local service=${1:-""}
    if [ -z "$service" ]; then
        print_status "Stopping all Django services..."
        docker-compose -f "$COMPOSE_FILE" down
        print_success "All Django services stopped"
    else
        print_status "Stopping $service..."
        docker-compose -f "$COMPOSE_FILE" down "$service"
        print_success "$service stopped"
    fi
}

# Function to show status
show_status() {
    print_status "Django services status:"
    docker-compose -f "$COMPOSE_FILE" ps
}

# Function to restart services
restart_services() {
    local service=${1:-""}
    if [ -z "$service" ]; then
        print_status "Restarting all Django services..."
        stop_services
        check_network
        check_dependencies
        build_django
        start_all
    else
        print_status "Restarting $service..."
        stop_services "$service"
        check_network
        check_dependencies
        build_django
        start_service "$service"
    fi
}

# Function to show help
show_help() {
    echo "PostHog Django Services Management Script"
    echo ""
    echo "Usage: $0 [COMMAND] [SERVICE]"
    echo ""
    echo "Commands:"
    echo "  build                    Build Django unified image"
    echo "  start [SERVICE]          Start specific service or all services"
    echo "  stop [SERVICE]           Stop specific service or all services"
    echo "  restart [SERVICE]        Restart specific service or all services"
    echo "  logs [SERVICE]           Show logs for specific service or all services"
    echo "  status                   Show services status"
    echo "  migrate                  Run database migrations"
    echo "  check-migrations         Check async migrations"
    echo "  help                     Show this help message"
    echo ""
    echo "Services:"
    echo "  web                      Django web server (backend + frontend)"
    echo "  worker                   Celery worker with scheduler"
    echo "  migrate                  Database migration service"
    echo "  asyncmigrationscheck     Async migrations check service"
    echo "  temporal-django-worker   Temporal Django worker"
    echo ""
    echo "Examples:"
    echo "  $0 build                 # Build Django image"
    echo "  $0 start                 # Start all Django services"
    echo "  $0 start web             # Start only web service"
    echo "  $0 start worker          # Start only worker service"
    echo "  $0 logs web              # Show web service logs"
    echo "  $0 migrate               # Run database migrations"
    echo "  $0 restart worker        # Restart worker service"
}

# Main script logic
case "${1:-help}" in
    build)
        check_network
        build_django
        ;;
    start)
        check_network
        check_dependencies
        build_django
        if [ -n "${2:-}" ]; then
            start_service "$2"
        else
            start_all
        fi
        ;;
    stop)
        stop_services "${2:-}"
        ;;
    restart)
        if [ -n "${2:-}" ]; then
            restart_services "$2"
        else
            restart_services
        fi
        ;;
    logs)
        show_logs "${2:-}"
        ;;
    status)
        show_status
        ;;
    migrate)
        check_network
        check_dependencies
        build_django
        run_migration
        ;;
    check-migrations)
        check_network
        check_dependencies
        build_django
        check_async_migrations
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac 