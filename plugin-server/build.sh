#!/bin/bash

# PostHog Plugin Server Build Script
# This script builds and tests the plugin-server Docker image

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="posthog/plugins"
TAG="latest"
CONTEXT_DIR=".."
DOCKERFILE="plugin-server/Dockerfile"

echo -e "${BLUE}🐳 PostHog Plugins Build Script${NC}"
echo "=================================="

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    print_error "This script must be run from the plugin-server directory"
    exit 1
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

print_status "Docker is running"

# Build the image
echo -e "${BLUE}🔨 Building plugins image...${NC}"
echo "Context: $CONTEXT_DIR"
echo "Dockerfile: $DOCKERFILE"
echo "Image: $IMAGE_NAME:$TAG"

# Build production image
print_status "Building production image..."
docker build \
    --target runtime \
    -t "$IMAGE_NAME:$TAG" \
    -f "$DOCKERFILE" \
    "$CONTEXT_DIR"

# Build development image
print_status "Building development image..."
docker build \
    --target development \
    -t "$IMAGE_NAME:dev" \
    -f "$DOCKERFILE" \
    "$CONTEXT_DIR"

print_status "Build completed successfully!"

# Show image info
echo -e "${BLUE}📊 Image Information:${NC}"
docker images | grep "$IMAGE_NAME"

# Test the image
echo -e "${BLUE}🧪 Testing image...${NC}"

# Test production image
print_status "Testing production image..."
docker run --rm \
    -e NODE_ENV=production \
    -e BASE_DIR=/app \
    "$IMAGE_NAME:$TAG" \
    node --version

# Test development image
print_status "Testing development image..."
docker run --rm \
    -e NODE_ENV=development \
    -e BASE_DIR=/app \
    "$IMAGE_NAME:dev" \
    node --version

print_status "Image tests passed!"

# Optional: Run with docker-compose
if [ "$1" = "--run" ]; then
    echo -e "${BLUE}🚀 Starting plugins only...${NC}"
    
    # Check if docker-compose file exists
    if [ ! -f "docker-compose.yml" ]; then
        print_error "docker-compose.yml not found in plugin-server directory"
        exit 1
    fi
    
    # Start plugins only (no platform services)
    print_status "Starting plugins..."
    docker-compose up plugins
    
elif [ "$1" = "--dev" ]; then
    echo -e "${BLUE}🚀 Starting development plugins only...${NC}"
    
    # Start development plugins only
    print_status "Starting development plugins..."
    docker-compose up plugins-dev

elif [ "$1" = "--platform" ]; then
    echo -e "${BLUE}🚀 Starting complete platform with all services...${NC}"
    
    # Start all services including platform dependencies
    print_status "Starting complete platform..."
    docker-compose --profile platform up

elif [ "$1" = "--platform-dev" ]; then
    echo -e "${BLUE}🚀 Starting complete platform with development plugins...${NC}"
    
    # Start all services with development plugins
    print_status "Starting complete platform with development plugins..."
    docker-compose --profile platform up plugins-dev

else
    echo -e "${BLUE}📋 Usage:${NC}"
    echo "  ./build.sh                    # Build images only"
    echo "  ./build.sh --run              # Build and run plugins only"
    echo "  ./build.sh --dev              # Build and run development plugins only"
    echo "  ./build.sh --platform         # Build and run complete platform (all services)"
    echo "  ./build.sh --platform-dev     # Build and run platform with dev plugins"
    echo ""
    echo -e "${YELLOW}💡 Docker Compose Profiles:${NC}"
    echo "  docker-compose up plugins              # Plugins only (default)"
    echo "  docker-compose up plugins-dev          # Development plugins only"
    echo "  docker-compose --profile platform up   # All services (platform profile)"
    echo "  docker-compose --profile platform up migrate # Run migrations only"
    echo ""
    echo -e "${YELLOW}💡 Quick Commands:${NC}"
    echo "  docker-compose up plugins              # Start plugins"
    echo "  docker-compose --profile platform up -d # Start all services in background"
    echo "  docker-compose down                    # Stop all services"
fi

print_status "Build script completed!" 