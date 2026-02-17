#!/usr/bin/env bash
set -euo pipefail

# Script 03: Docker Setup
# Install Docker and configure data root

# Source the utils.sh script for environment variables
source "$(dirname "$0")/utils.sh"

echo "🔧 Step 03: Docker Setup"

# Check if Docker is already installed
if command -v docker &>/dev/null; then
    echo "✅ Docker is already installed"
    echo "🔍 Verifying Docker version:"
    docker --version
else
    echo "📥 Installing Docker..."

    # Install dependencies
    echo "📦 Installing dependencies..."
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

    # Add Docker's official GPG key
    echo "🔑 Adding Docker GPG key..."
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo $ID)/gpg | \
        sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Add Docker repository
    echo "📦 Adding Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/$(. /etc/os-release; echo $ID) \
        $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    echo "🔄 Updating package lists..."
    sudo apt-get update
    echo "📥 Installing Docker packages..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
fi

# Reload and restart Docker (if installed or updated)
echo "🔄 Reloading systemd and restarting Docker..."
sudo systemctl daemon-reload
sudo systemctl restart docker

# Verify Docker is running
echo "� Verifying Docker service status..."
if ! sudo systemctl is-active --quiet docker; then
    echo "❌ Error: Docker service is not running" >&2
    exit 1
fi

# Test Docker functionality
echo "🔍 Testing Docker functionality..."
if ! docker --version; then
    echo "❌ Error: Docker command failed" >&2
    exit 1
fi

# Add current user to docker group if not already member
echo "👤 Adding current user to docker group..."
if ! groups $USER | grep -q '\bdocker\b'; then
    echo "➡️ Adding $USER to docker group..."
    sudo usermod -aG docker $USER
    echo "✅ User $USER added to docker group"
    echo "💡 Important: Please log out and log back in, or run 'newgrp docker' for the group change to take effect"
else
    echo "✅ User $USER is already in docker group"
fi

echo "✅ Docker installed and configured successfully"
echo "✅ Step 03 completed: Docker setup successful"
