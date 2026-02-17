#!/usr/bin/env bash
set -euo pipefail

# ComfyUI installation script
# This script runs inside the Docker container to set up ComfyUI

TARGET=/data/ComfyUI
echo "🔧 Setting up ComfyUI in $TARGET"

# Clone ComfyUI repository if it doesn't exist
if [ ! -d "$TARGET" ]; then
    mkdir -p "$TARGET"
    # pip install comfy-cli
    # echo "📥 Installing ComfyUI via comfy-cli..."
    # echo -e "\n\n\n\n\n" | comfy --workspace="$TARGET" install 
    # echo "📥 Cloning ComfyUI repository..."
    git clone --depth=1 --branch master https://github.com/comfyanonymous/ComfyUI.git "$TARGET"
    # git clone --depth=1 --branch v0.3.59 https://github.com/comfyanonymous/ComfyUI.git "$TARGET"

    # # Install Python dependencies
    # echo "📦 Installing Python dependencies..."
    cd "$TARGET"
    pip3 install --no-cache-dir -r requirements.txt
    
    ################# NOT TESTED YET #################
    # Install additional dependencies for custom nodes
    echo "📦 Installing additional dependencies (onnxruntime)..."
    pip3 install --no-cache-dir onnxruntime
    ##################################################
    
    # Create symlink for models and outputs
    rm -rf models output
    ln -s /data/models models
    ln -s /data/outputs output

    # Install comfy-ui manager
    cd "custom_nodes"
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager comfyui-manager

    

fi
# Update ComfyUI-Manager user config.ini file, to allow to download with direct github links
# It needs this file to exist, at the first run it creates it with normal security level
if [ -f "$TARGET/user/default/ComfyUI-Manager/config.ini" ]; then
    cd "$TARGET/user/default/ComfyUI-Manager"
    sed -i 's/normal/weak/g' config.ini
fi
cd "$TARGET"
ls -lha .
echo "!!!!!"
echo "!!!!!"
echo "!!!!!"
# comfy launch -- --listen 0.0.0.0 --port 8188
python3 main.py --listen 0.0.0.0 --port 8188

echo "✅ ComfyUI installation completed"
