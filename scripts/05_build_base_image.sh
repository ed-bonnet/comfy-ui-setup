#!/usr/bin/env bash
set -euo pipefail

# Script 05: Build Base Image
# Create the base CUDA/PyTorch Docker image

# Source the utils.sh script for environment variables
source "$(dirname "$0")/utils.sh"

echo "🔧 Step 05: Build Base Image"

# Check if base image already exists
if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^comfyui-base:"; then
    echo "✅ Base image 'comfyui-base' already exists"
    echo "🔍 Existing base images:"
    docker images comfyui-base
    echo "✅ Step 05 completed: Base image verified"
    exit 0
fi

echo "🏗️ Building base CUDA/PyTorch image..."

# Build the base image
echo "🔨 Building base image..."
if ! docker build -t comfyui-base -f Dockerfile.base .; then
    echo "❌ Error: Failed to build base image" >&2
    exit 1
fi

# Verify the image was built successfully
echo "🔍 Verifying base image..."
if ! docker images | grep -q "comfyui-base"; then
    echo "❌ Error: Base image not found after build" >&2
    exit 1
fi

echo "✅ Base image built successfully:"
docker images comfyui-base

echo "✅ Step 05 completed: Base image build successful"
