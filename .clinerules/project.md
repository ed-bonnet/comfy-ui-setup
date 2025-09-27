# ComfyUI Setup Project

## Overview
Automated setup for ComfyUI (AI image gen tool) on Ubuntu with RTX GPU. Includes installation scripts, systemd service, bash manager, and Flask web dashboard for management.

## Structure
- **Root**: README.md (install guide), install_comfyui.sh (main install).
- **scripts/**: install_conda.sh (Miniconda), install_comfyui_dashboard.sh (dashboard setup), uninstall_comfyui_dashboard.sh.
- **dashboard/**: Flask app (app.py) for env/service management; .env.example; todo.md; static/app.css; templates/index.html.
- **dashboard/core/**: Refactored business logic modules (config.py, command_utils.py, conda_manager.py, service_manager.py, env_file_handler.py, comfyui_setup.py).
- **test/**: test_dashboard.sh (validates deployment, binding, access, and regressions).

## Key Files & Roles
- install_comfyui.sh: Installs Miniconda, ComfyUI env (python=3.11, PyTorch CUDA), bashrc aliases, systemd service (~/.config/systemd/user/comfyui.service), ~/comfyui-manager.sh.
- app.py: Refactored Flask endpoints only - calls core modules for business logic.
- dashboard/core/: Modular business logic separated from web framework:
  - config.py: Configuration constants and environment variables
  - command_utils.py: Command execution utilities
  - conda_manager.py: Conda environment management
  - service_manager.py: Systemd service management
  - env_file_handler.py: Environment file operations
  - comfyui_setup.py: ComfyUI-specific setup logic
- install_comfyui_dashboard.sh: Creates conda env, installs Flask/Gunicorn/python-dotenv, configures app to run from repo's dashboard/ directory instead of deploying elsewhere, creates .env in dashboard/ for configuration, writes/updates user systemd unit (pointed to repo) and starts/enables it (unless --no-start).
- README.md: High-level install instructions.

## Features
- Automated ComfyUI install with CUDA (RTX 3090), TOS handling, env activation.
- Systemd services for ComfyUI (port 8188) and dashboard (port 8080).
- Bash manager: status/start/stop/logs/test/fix.
- Web dashboard: Monitor envs/services, create envs (with optional models symlink using models_location from .env), edit .env, secret masking. .env save now initializes from .env.example if file missing. UI field for models location removed; use .env instead.
- Installer simplified to default purpose (remote bind by default); test script for regressions and issue detection.
- Refactored architecture: Clean separation between Flask endpoints and business logic for better testability and maintainability.
- Access: ComfyUI http://localhost:8188, Dashboard http://0.0.0.0:8080 (remote accessible; secure with firewall).

This aids LLM in targeted changes: e.g., edit core modules for business logic changes, app.py for endpoint modifications.

## LLM Update Rule
- After making changes to source files, adding new features, or discovering useful information, update this .clinerules/project.md to reflect the updates for improved project management.
