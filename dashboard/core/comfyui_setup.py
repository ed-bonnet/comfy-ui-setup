import os
import sys
import re
import logging
from typing import Dict, Optional

from .command_utils import conda_cmd, run_cmd
from .env_file_handler import _parse_env_file
from .config import ENV_PATH
def setup_logging():
    """Configure logging to work with Gunicorn"""
    # Get gunicorn logger
    gunicorn_logger = logging.getLogger('gunicorn.error')
    
    # Create or get your app logger
    logger = logging.getLogger(__name__)
    
    if gunicorn_logger.handlers:
        # Running under Gunicorn - use its handlers
        logger.handlers = gunicorn_logger.handlers[:]
        logger.setLevel(gunicorn_logger.level)
    else:
        # Running standalone - configure basic logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            stream=sys.stdout
        )
    
    return logger
logger = setup_logging()

def get_free_port(start_port=8188) -> Optional[int]:
    """Find the first free port starting from start_port"""
    for port in range(start_port, start_port + 100):
        rc, out, _ = run_cmd(["ss", "-tuln"], timeout=5)
        if str(port) not in out:
            return port
    return None


def create_comfy_service(name: str, env_name: str, port: int, comfy_dir: str) -> str:
    service_name = f"comfy-{name}.service"
    unit_path = os.path.expanduser(f"~/.config/systemd/user/{service_name}")
    unit_dir = os.path.dirname(unit_path)
    os.makedirs(unit_dir, exist_ok=True)
    unit_content = f"""[Unit]
Description=ComfyUI {name}
After=network.target

[Service]
Type=simple
User={os.getenv('USER')}
WorkingDirectory={comfy_dir}
Environment=PATH=/home/{os.getenv('USER')}/miniconda3/envs/{env_name}/bin:/home/{os.getenv('USER')}/miniconda3/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/bin/bash -lc 'source /home/{os.getenv('USER')}/miniconda3/etc/profile.d/conda.sh && /home/{os.getenv('USER')}/miniconda3/bin/conda run -n {env_name} python main.py --port {port} --listen 0.0.0.0'
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target"""
    with open(unit_path, "w") as f:
        f.write(unit_content)
    run_cmd(["systemctl", "--user", "daemon-reload"])
    # Start and enable
    run_cmd(["systemctl", "--user", "start", service_name])
    run_cmd(["systemctl", "--user", "enable", service_name])
    return service_name


def setup_comfyui_environment(name: str, pyver: str) -> Dict:
    """API-ready function for creating a ComfyUI environment"""

    if not name or any(c in name for c in " /\\:"):
        return {"ok": False, "error": "Invalid environment name"}

    env_name = f"comfyui-instance-{name}"
    
    # Check uniqueness - we'll need to import conda_envs from conda_manager
    from .conda_manager import conda_envs
    current_envs = conda_envs()

    if any(e == env_name for e in current_envs):
        return {"ok": False, "error": f"Environment {env_name} already exists"}

    # Create base env with torch
    args = [
        "create", "-n", env_name, f"python={pyver}", 
        "pytorch", "torchvision", "torchaudio", "cudatoolkit=11.8",
        "-c", "pytorch", "-c", "nvidia", "-y"
    ]
    logger.error("!!!!!!!!!!")
    rc, out, err = conda_cmd(args, timeout=600)
    if rc != 0:
        return {"ok": False, "error": "Failed to create env", "stderr": err}

    # Create dir and install ComfyUI
    comfy_dir = os.path.expanduser(f"~/comfyuis/{name}")
    os.makedirs(comfy_dir, exist_ok=True)
    os.chdir(comfy_dir)
    if not os.path.exists("main.py"):
        # Clone if not exists
        git_rc, _, git_err = run_cmd(["git", "clone", "https://github.com/comfyanonymous/ComfyUI.git", "."], timeout=120)
        if git_rc != 0:
            # Clean up
            subprocess.run(["conda", "remove", "-n", env_name, "--all", "-y"], capture_output=True)
            return {"ok": False, "error": "Failed to clone ComfyUI", "stderr": git_err}

    # Install requirements in env
    pip_rc, pip_out, pip_err = run_cmd(["conda", "run", "-n", env_name, "pip", "install", "-r", "requirements.txt"], timeout=300)
    if pip_rc != 0:
        # Clean up
        run_cmd(["conda", "remove", "-n", env_name, "--all", "-y"], timeout=60)
        return {"ok": False, "error": "Failed to install ComfyUI requirements", "stderr": pip_err}

    # Handle models symbolic link from .env
    models_location = _parse_env_file(ENV_PATH).get("models_location", "").strip()
    if models_location:
        models_src = os.path.expanduser(models_location)
        models_target = os.path.join(comfy_dir, "models")
        # Ensure models dir exists
        os.makedirs(models_target, exist_ok=True)
        # Remove existing models dir/link
        if os.path.exists(models_target):
            rc_rm, _, _ = run_cmd(["rm", "-rf", models_target])
            if rc_rm != 0:
                return {"ok": False, "error": f"Failed to clear existing models at {models_target}"}
        # Create symlink
        rc_ln, out_ln, err_ln = run_cmd(["ln", "-s", models_src, models_target])
        if rc_ln != 0:
            return {"ok": False, "error": f"Failed to create models symlink: {err_ln}"}
        logger.info(f"✅ Models symlink created: {models_target} -> {models_src}")

    port = get_free_port()
    if port is None:
        return {"ok": False, "error": "No free port found"}

    service_name = create_comfy_service(name, env_name, port, comfy_dir)

    # Update SERVICES in .env
    services_line = None
    lines = []
    with open(ENV_PATH, "r") as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        if line.strip().startswith("SERVICES="):
            services_line = i
            current_services = line.strip().split("=", 1)[1].strip('"').strip()
            new_services = f"{current_services},user:{service_name}" if current_services else f"user:{service_name}"
            lines[i] = f"SERVICES={new_services}\n"
            break
    if services_line is None:
        lines.append(f"SERVICES=user:{service_name}\n")
    with open(ENV_PATH, "w") as f:
        f.writelines(lines)

    return {
        "ok": True, 
        "env_name": env_name, 
        "service_name": service_name, 
        "port": port, 
        "comfy_dir": comfy_dir
    }
