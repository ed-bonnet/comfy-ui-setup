#!/usr/bin/env bash
set -euo pipefail

# Script 08: Deploy Services
# Deploy ComfyUI container and dashboard services

# Source the utils.sh script for environment variables
source "$(dirname "$0")/utils.sh"

echo "🔧 Step 08: Deploy Services"

# Function to deploy a container
deploy_container() {
    local name="$1"
    local image="$2"
    local port="$3"
    local extra_args="$4"
    
    echo "🚀 Deploying container: $name"
    
    # Check if container already exists and stop/remove it
    if docker ps -a --filter "name=${name}" --format '{{.Names}}' | grep -w "${name}" &>/dev/null; then
        echo "🛑 Stopping existing container: $name"
        docker stop "${name}" || true
        docker rm "${name}" || true
    fi
    
    echo "📦 Starting container $name on port $port"
    
    # Deploy the container
    docker run -i \
        --gpus all \
        --name "${name}" \
        -p "${port}:${port}" \
        -v "${MODEL_VOL}:/data/models" \
        -v "${OUTPUT_VOL}:/data/outputs" \
        ${extra_args} \
        "${image}"
    
    # Wait a moment for container to start
    sleep 5
    
    # Verify container is running
    if ! docker ps --filter "name=${name}" --filter "status=running" | grep -q "${name}"; then
        echo "❌ Error: Container $name failed to start" >&2
        docker logs "${name}" >&2
        return 1
    fi
    
    echo "✅ Container $name deployed successfully"
    return 0
}

# Deploy ComfyUI container
echo "🌟 Deploying ComfyUI service..."
deploy_container "comfyui-audio-1" "comfyui-app" "${COMFYUI_PORT}" ""

echo "✅ Step 08 completed: Services deployment successful"
