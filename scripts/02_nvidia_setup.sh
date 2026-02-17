#!/usr/bin/env bash
set -euo pipefail

# Script 02: NVIDIA GPU Setup
# Install NVIDIA drivers and container toolkit for GPU support

# Source the utils.sh script for environment variables
source "$(dirname "$0")/utils.sh"

echo "🔧 Step 02: NVIDIA GPU Setup"

# Check if nvidia-smi is available (indicating NVIDIA drivers are installed)
if command -v nvidia-smi &>/dev/null; then
    echo "✅ NVIDIA drivers already installed"
    echo "🔍 Verifying GPU availability:"
    nvidia-smi
    echo "✅ Step 02 completed: NVIDIA setup verified"
    exit 0
fi

echo "📥 Installing NVIDIA drivers and container toolkit..."

# Determine distribution for NVIDIA repository
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)

echo "📋 Detected distribution: $distribution"

# Add NVIDIA repository and key
echo "🔑 Adding NVIDIA repository key..."
curl -fsSL https://nvidia.github.io/nvidia-docker/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-docker.gpg

echo "📦 Adding NVIDIA repository..."
curl -fsSL "https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list" | \
    sudo tee /etc/apt/sources.list.d/nvidia-docker.list

# Update package list and install NVIDIA packages
echo "🔄 Updating package lists..."
sudo apt-get update

echo "📥 Installing NVIDIA driver and container toolkit..."
sudo apt-get install -y nvidia-driver-535 nvidia-docker2

# Restart Docker to apply changes
echo "🔄 Restarting Docker service..."
sudo systemctl restart docker

# Verify installation
echo "🔍 Verifying GPU availability:"
if ! nvidia-smi; then
    echo "❌ Error: NVIDIA GPU not detected after installation" >&2
    echo "Please check your GPU hardware and try again" >&2
    exit 1
fi

echo "✅ NVIDIA drivers and container toolkit installed successfully"
echo "✅ Step 02 completed: NVIDIA setup successful"
