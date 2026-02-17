#!/usr/bin/env bash
set -euo pipefail

# Script 04: Volumes Setup
# Create shared volume directories on host for models and outputs

# Source the utils.sh script for environment variables
source "$(dirname "$0")/utils.sh"

echo "🔧 Step 04: Volumes Setup"

# Function to create and set permissions for a volume
setup_volume() {
    local volume_path="$1"
    
    echo "📁 Setting up volume: $volume_path"
    
    # Create directory if it doesn't exist
    if [ ! -d "$volume_path" ]; then
        echo "  Creating directory: $volume_path"
        sudo mkdir -p "$volume_path"
    else
        echo "  Directory already exists: $volume_path"
    fi
    
    # Set proper permissions (read/write for current user and docker group)
    echo "  Setting permissions..."
    sudo chown -R $(id -u):$(id -g) "$volume_path"
    sudo chmod -R 755 "$volume_path"
    
    # Also ensure Docker can access it by adding to docker group if needed
    if ! groups $(whoami) | grep -q '\bdocker\b'; then
        echo "⚠️  Warning: Current user not in docker group"
        echo "  Consider adding user to docker group: sudo usermod -aG docker $(whoami)"
    fi
}

# Create model volume
setup_volume "$MODEL_VOL"

# Create output volume
setup_volume "$OUTPUT_VOL"

# Verify the volumes were created
echo "🔍 Verifying volume setup:"
for vol in "$MODEL_VOL" "$OUTPUT_VOL"; do
    if [ -d "$vol" ]; then
        echo "✅ Volume: $vol (exists)"
        echo "   Permissions: $(ls -ld "$vol")"
    else
        echo "❌ Error: Volume not created at $vol" >&2
        exit 1
    fi
done

echo "✅ Shared volumes created successfully"
echo "✅ Step 04 completed: Volumes setup successful"
