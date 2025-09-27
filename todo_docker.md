# Automated ComfyUI Docker Environment Setup Guide

The following **single Bash orchestrator script** reads a local **`.env`** file, installs Docker with NVIDIA GPU support, builds images, and deploys multiple ComfyUI containers plus a lightweight web dashboard.  

***

## 1. Create `.env` File  
Place in project root as **`.env`** and adjust values as needed:

```dotenv
# Docker storage root
DOCKER_DATA_ROOT=/mnt/docker-data

# CUDA & PyTorch
CUDA_VERSION=12.4
PYTORCH_VERSION=2.5.0

# ComfyUI repository
COMFYUI_REPO=https://github.com/comfyanonymous/ComfyUI.git
COMFYUI_BRANCH=main

# Ports
COMFYUI_PORT=8188
DASHBOARD_PORT=3230

# Shared volumes (relative to DOCKER_DATA_ROOT)
MODEL_VOL=models
OUTPUT_VOL=outputs
```

***

## 2. `deploy.sh` Orchestrator Script  
Create **`deploy.sh`** in project root and make executable (`chmod +x deploy.sh`).  

```bash
#!/usr/bin/env bash
set -euo pipefail

# Load .env
if [ ! -f .env ]; then
  echo "Error: .env file not found" >&2
  exit 1
fi
export $(grep -v '^#' .env | xargs)

# 2.1 Check NVIDIA GPU on host
if ! command -v nvidia-smi &>/dev/null; then
  echo "Installing NVIDIA drivers and Container Toolkit..."
  # Add NVIDIA repo and key
  distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
  curl -sL https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
  curl -sL https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list \
    | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
  sudo apt-get update
  sudo apt-get install -y nvidia-driver nvidia-docker2
  sudo systemctl restart docker
fi

echo "Verifying GPU:"
nvidia-smi

# 2.2 Install Docker & configure storage
if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo $ID)/gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/$(. /etc/os-release; echo $ID) \
    $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
fi

# Configure Docker data-root
sudo mkdir -p "${DOCKER_DATA_ROOT}"
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "data-root": "${DOCKER_DATA_ROOT}"
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker

# 2.3 Create shared volumes on host
for vol in "${MODEL_VOL}" "${OUTPUT_VOL}"; do
  sudo mkdir -p "${DOCKER_DATA_ROOT}/${vol}"
done

# 2.4 Build Base Image
cat > Dockerfile.base <<EOF
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu22.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip git && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir torch==${PYTORCH_VERSION}+cu${CUDA_VERSION//./} \
     --extra-index-url https://download.pytorch.org/whl/cu${CUDA_VERSION//./}

WORKDIR /opt
EOF

docker build -t comfyui-base -f Dockerfile.base .

# 2.5 Create ComfyUI install script
cat > install_comfyui.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

TARGET=/data/ComfyUI
if [ ! -d "$TARGET" ]; then
  git clone --depth=1 --branch "${COMFYUI_BRANCH}" "${COMFYUI_REPO}" "$TARGET"
  pip3 install --no-cache-dir -r "$TARGET/requirements.txt"
fi
EOF
chmod +x install_comfyui.sh

# 2.6 Build ComfyUI Image
cat > Dockerfile.comfyui <<EOF
ARG CUDA_VERSION
FROM comfyui-base:\${CUDA_VERSION}

COPY install_comfyui.sh /usr/local/bin/install_comfyui.sh
RUN chmod +x /usr/local/bin/install_comfyui.sh

ENTRYPOINT ["/usr/local/bin/install_comfyui.sh"]
CMD ["python3", "/data/ComfyUI/main.py", "--listen", "0.0.0.0", "--port", "${COMFYUI_PORT}"]
EOF

docker build --build-arg CUDA_VERSION=${CUDA_VERSION} -t comfyui-app -f Dockerfile.comfyui .

# 2.7 Deploy Services
function deploy_container() {
  name=$1; image=$2; port=$3; extra_args=$4
  if docker ps --filter "name=${name}" --format '{{.Names}}' | grep -w "${name}" &>/dev/null; then
    echo "Stopping existing ${name}..."
    docker stop "${name}"
    docker rm "${name}"
  fi
  echo "Starting ${name}..."
  docker run -d --gpus all --name "${name}" -p "${port}:${port}" \
    -v "${DOCKER_DATA_ROOT}/${MODEL_VOL}:/data/models" \
    -v "${DOCKER_DATA_ROOT}/${OUTPUT_VOL}:/data/outputs" ${extra_args} "${image}"
}

deploy_container comfyui comfyui-app ${COMFYUI_PORT} \
  "-v /data/models:/data/models -v /data/outputs:/data/outputs"

# Docker Dashboard using docker-compose if present, else pull image
if [ -f docker-compose.yml ]; then
  docker-compose up -d
else
  deploy_container docker-web-gui rakibtg/docker-web-gui ${DASHBOARD_PORT} \
    "-v /var/run/docker.sock:/var/run/docker.sock"
fi

echo "Deployment complete!"
echo "Access ComfyUI at http://<host>:${COMFYUI_PORT}"
echo "Access Docker Dashboard at http://<host>:${DASHBOARD_PORT}"
```

***

## 3. Usage  
- Place **`.env`**, **`docker-compose.yml`**, **`deploy.sh`**, **`Dockerfile.base`**, **`Dockerfile.comfyui`**, and **`install_comfyui.sh`** in the same directory.  
- Make scripts executable:  
  ```bash
  chmod +x deploy.sh install_comfyui.sh
  ```
- Run deployment:  
  ```bash
  ./deploy.sh
  ```
- Manage services with:  
  ```bash
  ./deploy.sh   # deploy or redeploy all
  ```

This orchestrator ensures idempotent setup, GPU passthrough, automatic ComfyUI updates on first container run, and a lightweight web UI dashboard.