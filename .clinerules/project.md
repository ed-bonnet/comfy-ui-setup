# ComfyUI Setup Project

## Overview
Automated setup for ComfyUI (AI image gen tool) on Ubuntu with RTX GPU. Includes installation scripts, systemd service, bash manager, and Flask web dashboard for management.

## Structure
- **Root**: README.md (install guide), install_comfyui.sh (main install).
- **scripts/**: install_conda.sh (Miniconda), install_comfyui_dashboard.sh (dashboard setup), uninstall_comfyui_dashboard.sh.
- **dashboard/**: Flask app (app.py) for env/service management; .env.example; todo.md; static/app.css; templates/index.html.
- **test/**: test_dashboard.sh (validates deployment, binding, access, and regressions).

## Key Files & Roles
- install_comfyui.sh: Installs Miniconda, ComfyUI env (python=3.11, PyTorch CUDA), bashrc aliases, systemd service (~/.config/systemd/user/comfyui.service), ~/comfyui-manager.sh.
- app.py: Flask APIs for conda envs (list/create, with optional models symlink from .env models_location), services (control comfyui/comfyui-dashboard), .env editing (load/save with example fallback for missing file).
- install_comfyui_dashboard.sh: Creates conda env, installs Flask/Gunicorn/python-dotenv, configures app to run from repo's dashboard/ directory instead of deploying elsewhere, creates .env in dashboard/ for configuration, writes/updates user systemd unit (pointed to repo) and starts/enables it (unless --no-start).
- README.md: High-level install instructions.

## Features
- Automated ComfyUI install with CUDA (RTX 3090), TOS handling, env activation.
- Systemd services for ComfyUI (port 8188) and dashboard (port 8080).
- Bash manager: status/start/stop/logs/test/fix.
- Web dashboard: Monitor envs/services, create envs (with optional models symlink using models_location from .env), edit .env, secret masking. .env save now initializes from .env.example if file missing. UI field for models location removed; use .env instead.
- Installer simplified to default purpose (remote bind by default); test script for regressions and issue detection.
- Access: ComfyUI http://localhost:8188, Dashboard http://0.0.0.0:8080 (remote accessible; secure with firewall).

This aids LLM in targeted changes: e.g., edit app.py for new APIs, scripts for install tweaks.

## LLM Update Rule
- After making changes to source files, adding new features, or discovering useful information, update this .clinerules/project.md to reflect the updates for improved project management.
