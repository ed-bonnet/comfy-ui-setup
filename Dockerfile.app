FROM comfyui-base

# Copy the ComfyUI installation script
COPY install_comfyui.sh /usr/local/bin/install_comfyui.sh
RUN chmod +x /usr/local/bin/install_comfyui.sh

# Set environment variables
ENV COMFYUI_PORT=8188
ENV COMFYUI_REPO=https://github.com/comfyanonymous/ComfyUI.git
ENV COMFYUI_BRANCH=master

# Create the ComfyUI directory structure
RUN mkdir -p /data/ComfyUI

# Run the installation script when container starts
ENTRYPOINT ["/usr/local/bin/install_comfyui.sh"]

# Default command to start ComfyUI
CMD ["python3", "/data/ComfyUI/main.py", "--listen", "0.0.0.0", "--port", "8188"]
