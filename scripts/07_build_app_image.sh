#!/usr/bin/env bash
set -euo pipefail

# Script 07: Build Application Image
# Build the final ComfyUI application image from the base image

# Source the utils.sh script for environment variables
source "$(dirname "$0")/utils.sh"

echo "🔧 Step 07: Build Application Image"

# Build the application image with CUDA version as build argument
echo "🔨 Building application image..."
if ! docker build --build-arg CUDA_VERSION=${CUDA_VERSION} -t comfyui-app -f Dockerfile.comfyui .; then
    echo "❌ Error: Failed to build application image" >&2
    exit 1
fi

# Verify the image was built successfully
echo "🔍 Verifying application image..."
if ! docker images | grep -q "comfyui-app"; then
    echo "❌ Error: Application image not found after build" >&2
    exit 1
fi

echo "✅ Application image built successfully:"
docker images comfyui-app

echo "✅ Step 07 completed: Application image build successful"
