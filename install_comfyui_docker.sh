#!/usr/bin/env bash
set -euo pipefail

# ComfyUI Installation Script for Docker
# Based on archive_to_delete_install_comfyui.sh but adapted for Docker environment
# Heavy dependencies (PyTorch/CUDA) are already installed in the base image

echo "🔧 ComfyUI Docker Installation Script"
echo "📋 This script installs ComfyUI in a Docker container"
echo "💡 Note: PyTorch with CUDA support is pre-installed in the base image"
echo ""

# Set target directory
TARGET="/data/ComfyUI"
echo "🎯 Target directory: $TARGET"

# Step 1: Clone ComfyUI repository if it doesn't exist
if [ ! -d "$TARGET" ]; then
    echo "📥 Cloning ComfyUI repository..."
    git clone --depth=1 --branch master https://github.com/comfyanonymous/ComfyUI.git "$TARGET"
    echo "✅ ComfyUI repository cloned"
else
    echo "✅ ComfyUI repository already exists"
    cd "$TARGET"
    echo "🔄 Updating repository..."
    git pull origin master"
    echo "✅ Repository updated"
fi

# Step 2: Install ComfyUI dependencies
echo "📦 Installing Python dependencies..."
cd "$TARGET"
pip3 install --no-cache-dir -r requirements.txt

# Step 3: Install comfy-cli for additional functionality
echo "🔧 Installing comfy-cli..."
pip3 install --no-cache-dir comfy-cli

# Step 4: Verify installation and CUDA support
echo "🧪 Verifying installation..."
python3 -c "
import sys
print(f'✅ Python version: {sys.version.split()[0]}')

try:
    import torch
    print(f'✅ PyTorch version: {torch.__version__}')
    print(f'✅ CUDA available: {torch.cuda.is_available()}')
    if torch.cuda.is_available():
        print(f'✅ GPU: {torch.cuda.get_device_name(0)}')
        print(f'✅ CUDA version: {torch.version.cuda}')
    else:
        print('❌ CUDA not available - check base image')
except ImportError as e:
    print(f'❌ PyTorch import failed: {e}')
    sys.exit(1)

try:
    import comfy
    print('✅ ComfyUI core imported successfully')
except ImportError as e:
    print(f'❌ ComfyUI import failed: {e}')
    print('🔧 Attempting to fix by installing ComfyUI directly...')
    # If comfy import fails, try installing it directly
    import subprocess
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', '--no-cache-dir', 'git+https://github.com/comfyanonymous/ComfyUI.git'])
    print('✅ ComfyUI installed directly')
"

echo "✅ ComfyUI installation completed successfully"
echo "🚀 Ready to start ComfyUI on port ${COMFYUI_PORT:-8188}"
