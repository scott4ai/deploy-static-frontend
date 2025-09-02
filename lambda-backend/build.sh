#!/bin/bash

# HITL Platform Lambda - Build and Package Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/dist"
PACKAGE_DIR="$SCRIPT_DIR/package"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log "Starting Lambda build process..."

# Clean previous builds
log "Cleaning previous builds..."
rm -rf "$BUILD_DIR"
rm -rf "$PACKAGE_DIR"
rm -f "$SCRIPT_DIR/deployment.zip"

# Install dependencies
log "Installing dependencies..."
if [ ! -d "node_modules" ]; then
    npm install
else
    log "Dependencies already installed, skipping..."
fi

# Build TypeScript
log "Building TypeScript..."
npm run build

# Create package directory
log "Creating deployment package..."
mkdir -p "$PACKAGE_DIR"

# Copy compiled JavaScript
cp -r "$BUILD_DIR"/* "$PACKAGE_DIR/"

# Copy package.json (for Lambda runtime)
cp package.json "$PACKAGE_DIR/"

# Install production dependencies in package directory
log "Installing production dependencies..."
cd "$PACKAGE_DIR"
npm install --only=production

# Create deployment zip
log "Creating deployment zip..."
cd "$SCRIPT_DIR"
cd "$PACKAGE_DIR"
zip -r "../deployment.zip" . -q

# Get zip size
cd "$SCRIPT_DIR"
ZIP_SIZE=$(ls -lh deployment.zip | awk '{print $5}')

log "Lambda deployment package created successfully!"
log "Package size: $ZIP_SIZE"
log "Location: $SCRIPT_DIR/deployment.zip"

# Validate package contents
log "Package contents:"
unzip -l deployment.zip | head -20

# Clean up build artifacts
log "Cleaning up build artifacts..."
rm -rf "$BUILD_DIR"
rm -rf "$PACKAGE_DIR"

echo ""
echo "======================================"
echo "Lambda Build Complete!"
echo "======================================"
echo "Deployment package: deployment.zip"
echo "Size: $ZIP_SIZE"
echo ""
echo "Ready for deployment to AWS Lambda"
echo "======================================"