#!/usr/bin/env bash

# utils.sh - Common utilities for ComfyUI setup scripts
# Loads environment variables from .env file and provides helper functions

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment variables from .env file
load_env() {
    local env_file="$PROJECT_ROOT/.env"
    
    if [ ! -f "$env_file" ]; then
        echo "❌ Error: .env file not found at $env_file" >&2
        echo "💡 Please create a .env file based on .env.example" >&2
        return 1
    fi
    
    # Source the .env file
    # shellcheck disable=SC1090
    source "$env_file"
    
    # Set default values for optional variables
    export CUDA_VERSION="${CUDA_VERSION:-12.4}"
    export PYTORCH_VERSION="${PYTORCH_VERSION:-2.5.0}"
    export COMFYUI_REPO="https://github.com/comfyanonymous/ComfyUI.git"
    export COMFYUI_BRANCH="master"
    export COMFYUI_PORT="${COMFYUI_PORT:-8188}"
    export DASHBOARD_PORT="${DASHBOARD_PORT:-3230}"
    export MODEL_VOL="${MODEL_VOL:-models}"
    export OUTPUT_VOL="${OUTPUT_VOL:-outputs}"
    
    echo "✅ Environment variables loaded from $env_file"
}

# Validate that required environment variables are set
validate_env() {
    local required_vars=("CUDA_VERSION" "PYTORCH_VERSION" "COMFYUI_REPO" "COMFYUI_BRANCH")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            echo "❌ Error: Required environment variable $var is not set" >&2
            return 1
        fi
    done
    
    echo "✅ All required environment variables are set"
}

# Print current environment configuration
print_env() {
    echo "🔧 Current Environment Configuration:"
    echo "   CUDA_VERSION: $CUDA_VERSION"
    echo "   PYTORCH_VERSION: $PYTORCH_VERSION"
    echo "   COMFYUI_REPO: $COMFYUI_REPO"
    echo "   COMFYUI_BRANCH: $COMFYUI_BRANCH"
    echo "   COMFYUI_PORT: $COMFYUI_PORT"
    echo "   DASHBOARD_PORT: $DASHBOARD_PORT"
    echo "   MODEL_VOL: $MODEL_VOL"
    echo "   OUTPUT_VOL: $OUTPUT_VOL"
}

# Main function to load and validate environment
setup_environment() {
    load_env || return 1
    validate_env || return 1
    print_env
}

setup_environment
