#!/bin/bash

# Production Docker Build Script for Perses
# This script builds Linux AMD64 binaries and creates a production Docker image
# Usage: ./scripts/build-production-image.sh [IMAGE_TAG]

set -euo pipefail

# Configuration
DEFAULT_IMAGE="quay.io/jezhu/perses-perses"
IMAGE_TAG="${1:-latest}"
FULL_IMAGE_TAG="${DEFAULT_IMAGE}:${IMAGE_TAG}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [[ ! -f "Dockerfile" || ! -f "cmd/perses/main.go" ]]; then
    log_error "This script must be run from the Perses root directory"
    exit 1
fi

log_info "Starting production build for image: ${FULL_IMAGE_TAG}"

# Step 1: Clean up any existing binaries in root
log_info "Cleaning up existing binaries..."
rm -f ./perses ./percli

# Step 2: Build plugins and assets (host architecture for tools)
log_info "Building assets and installing plugins..."
make assets-compress install-default-plugins

# Step 3: Cross-compile binaries for Linux AMD64
log_info "Cross-compiling binaries for Linux AMD64..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags "-s -w -X github.com/prometheus/common/version.Version=$(cat VERSION 2>/dev/null || echo 'dev') -X github.com/prometheus/common/version.Revision=$(git rev-parse HEAD 2>/dev/null || echo 'unknown') -X github.com/prometheus/common/version.BuildDate=$(date +%Y-%m-%d) -X github.com/prometheus/common/version.Branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')" \
    -o ./perses ./cmd/perses

CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags "-s -w" \
    -o ./percli ./cmd/percli

# Verify binaries are correct architecture
log_info "Verifying binary architecture..."
if file ./perses | grep -q "ELF 64-bit LSB executable, x86-64"; then
    log_info "✓ perses binary: Linux x86-64"
else
    log_error "✗ perses binary: Wrong architecture"
    file ./perses
    exit 1
fi

if file ./percli | grep -q "ELF 64-bit LSB executable, x86-64"; then
    log_info "✓ percli binary: Linux x86-64"
else
    log_error "✗ percli binary: Wrong architecture"
    file ./percli
    exit 1
fi

# Step 4: Build production Docker image
log_info "Building production Docker image..."
if command -v podman &> /dev/null; then
    CONTAINER_TOOL="podman"
elif command -v docker &> /dev/null; then
    CONTAINER_TOOL="docker"
else
    log_error "Neither podman nor docker found. Please install one of them."
    exit 1
fi

log_info "Using container tool: ${CONTAINER_TOOL}"

${CONTAINER_TOOL} build --platform linux/amd64 . -t "${FULL_IMAGE_TAG}"

# Step 5: Clean up binaries from root (optional)
log_info "Cleaning up root directory binaries..."
rm -f ./perses ./percli

# Success
log_info "✓ Production build complete!"
log_info "Image: ${FULL_IMAGE_TAG}"
log_info ""
log_info "Next steps:"
log_info "  1. Push to registry: ${CONTAINER_TOOL} push ${FULL_IMAGE_TAG}"
log_info "  2. Update your deployment to use: ${FULL_IMAGE_TAG}"
log_info ""
log_info "Image details:"
${CONTAINER_TOOL} images | grep "${DEFAULT_IMAGE}" | head -1 || true