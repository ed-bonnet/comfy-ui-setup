#!/usr/bin/env bash
# Uninstaller for comfyui-dashboard (safe defaults)
# - Stops/disables the user systemd service
# - Removes the unit file and reloads daemon
# - Deletes the app directory under $HOME
# - Removes ONLY the comfyui-dashboard conda environment
# - Does NOT remove Miniconda or other environments
set -euo pipefail

APP_NAME="comfyui-dashboard"
APP_DIR="$HOME/$APP_NAME"
ENV_NAME="$APP_NAME"
SERVICE_NAME="$APP_NAME.service"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_PATH="$UNIT_DIR/$SERVICE_NAME"

KEEP_ENV="false"
KEEP_APP="false"
KEEP_SERVICE_FILE="false"

info() { echo -e "➜ \e[32m$*\e[0m"; }
warn() { echo -e "⚠️  \e[33m$*\e[0m"; }
err()  { echo -e "❌ \e[31m$*\e[0m" >&2; }
die()  { err "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --keep-env            Do not remove the conda environment ($ENV_NAME)
  --keep-app            Do not remove the app directory ($APP_DIR)
  --keep-service-file   Do not remove the systemd unit file ($UNIT_PATH)
  -h, --help            Show this help

Default behavior (no flags):
  - Stop/disable service, remove unit, remove app dir, remove conda env
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-env) KEEP_ENV="true"; shift;;
    --keep-app) KEEP_APP="true"; shift;;
    --keep-service-file) KEEP_SERVICE_FILE="true"; shift;;
    -h|--help) usage; exit 0;;
    *) usage; die "Unknown option: $1";;
  esac
done

stop_disable_unit() {
  if systemctl --user list-unit-files | grep -q "^$SERVICE_NAME"; then
    info "Stopping/disabling service: $SERVICE_NAME"
    systemctl --user stop "$SERVICE_NAME" || true
    systemctl --user disable "$SERVICE_NAME" || true
  else
    info "Service not registered with systemd --user: $SERVICE_NAME (skipping stop/disable)"
  fi
}

remove_unit() {
  if [[ "$KEEP_SERVICE_FILE" == "true" ]]; then
    warn "Keeping unit file (per flag): $UNIT_PATH"
  else
    if [[ -f "$UNIT_PATH" ]]; then
      info "Removing unit file: $UNIT_PATH"
      rm -f "$UNIT_PATH"
      systemctl --user daemon-reload || true
    else
      info "Unit file not found (skipping): $UNIT_PATH"
    fi
  fi
}

remove_app_dir() {
  if [[ "$KEEP_APP" == "true" ]]; then
    warn "Keeping app directory (per flag): $APP_DIR"
  else
    if [[ -d "$APP_DIR" ]]; then
      info "Removing app directory: $APP_DIR"
      rm -rf "$APP_DIR"
    else
      info "App directory not found (skipping): $APP_DIR"
    fi
  fi
}

conda_exists() {
  command -v conda &>/dev/null || [[ -x "$HOME/miniconda3/bin/conda" ]]
}

remove_conda_env() {
  if [[ "$KEEP_ENV" == "true" ]]; then
    warn "Keeping conda environment (per flag): $ENV_NAME"
    return
  fi

  if ! conda_exists; then
    warn "Conda not found; cannot remove env $ENV_NAME. Skipping."
    return
  fi

  # Ensure conda in PATH for this shell
  if ! command -v conda &>/dev/null; then
    if [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
      # shellcheck disable=SC1090
      source "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
      export PATH="$HOME/miniconda3/bin:$PATH"
    fi
  fi

  if conda env list | grep -qE "^[[:space:]]*$ENV_NAME[[:space:]]"; then
    info "Removing conda env: $ENV_NAME"
    conda remove -n "$ENV_NAME" --all -y || true
  else
    info "Conda env not found (skipping): $ENV_NAME"
  fi
}

main() {
  info "Uninstalling $APP_NAME (safe defaults)"
  stop_disable_unit
  remove_unit
  remove_app_dir
  remove_conda_env

  echo ""
  info "Uninstall complete."
  echo "If you previously enabled user lingering for boot start, you can disable it with:"
  echo "  sudo loginctl disable-linger \$USER"
}

main "$@"
