import logging
import os

# Set up logging
logger = logging.getLogger(__name__)

# Resolve base app directory (expected WorkingDirectory in systemd unit)
BASE_DIR = os.path.abspath(os.getenv("COMFYUI_DASHBOARD_DIR", os.getcwd()))
logger.debug(f"Base directory: {BASE_DIR}")
ENV_PATH = os.path.join(BASE_DIR, ".env")
logger.debug(f"Env path: {ENV_PATH}")

# Basic config
MASK_SECRETS = os.getenv("MASK_SECRETS", "true").lower() in ("1", "true", "yes", "on")
ACTION_TOKEN = None  # Disabled
SECRET_KEY = os.getenv("SECRET_KEY", "change-me-in-.env")

# Services to monitor/control: "user:comfyui.service,user:comfyui-dashboard.service"
SERVICES = os.getenv("SERVICES", "")

# Prefer explicit Miniconda path, fallback to PATH
MINICONDA_CONDA = os.path.expanduser(os.getenv("MINICONDA_CONDA", "~/miniconda3/bin/conda"))
if not os.path.isfile(MINICONDA_CONDA):
    MINICONDA_CONDA = "conda"
