#!/usr/bin/env bash
# Installer for comfyui-dashboard
# - Default: Reinstall (uninstall existing then install fresh)
# - Creates conda env, installs Flask/Gunicorn/python-dotenv
# - Configures app to run from repo's dashboard/ directory instead of deploying elsewhere
# - Writes/updates user systemd unit and starts/enables it (unless --no-start)
# - Uses scripts/install_conda.sh to ensure Conda is present
set -euo pipefail

APP_NAME="comfyui-dashboard"
ENV_NAME="$APP_NAME"
SERVICE_NAME="$APP_NAME.service"

PORT="8080"
BIND_HOST="0.0.0.0"
SERVICES=""
REINSTALL="true"
START_AFTER="true"
UNINSTALL_ONLY="false"

# Resolve repo root (this script lives in repo/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_NAME="$(basename "$REPO_ROOT")"
SRC_DIR="$REPO_ROOT/dashboard"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_PATH="$UNIT_DIR/$SERVICE_NAME"

info() { echo -e "➜ \e[32m$*\e[0m"; }
warn() { echo -e "⚠️  \e[33m$*\e[0m"; }
err()  { echo -e "❌ \e[31m$*\e[0m" >&2; }
die()  { err "$*"; exit 1; }

if [[ "${1:-}" == "--uninstall" ]]; then
  UNINSTALL_ONLY="true"
fi

# Ensure scripts/install_conda.sh exists
[[ -f "$SCRIPT_DIR/install_conda.sh" ]] || die "Missing $SCRIPT_DIR/install_conda.sh. Please keep install_conda in scripts/."

ensure_conda() {
  info "Ensuring Conda via scripts/install_conda.sh..."
  bash "$SCRIPT_DIR/install_conda.sh"

  # Make conda available in this shell if not
  if ! command -v conda &>/dev/null; then
    if [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
      # shellcheck disable=SC1090
      source "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
      export PATH="$HOME/miniconda3/bin:$PATH"
    fi
  fi
  command -v conda &>/dev/null || die "Conda not available after install_conda.sh"
  info "Conda ready: $(conda --version)"
}

stop_disable_unit() {
  if systemctl --user list-unit-files | grep -q "^$SERVICE_NAME"; then
    info "Stopping/disabling existing service $SERVICE_NAME (user)..."
    systemctl --user stop "$SERVICE_NAME" || true
    systemctl --user disable "$SERVICE_NAME" || true
  fi
}

remove_unit() {
  if [[ -f "$UNIT_PATH" ]]; then
    info "Removing unit file: $UNIT_PATH"
    rm -f "$UNIT_PATH"
  fi
  systemctl --user daemon-reload || true
}

remove_conda_env() {
  if conda env list | grep -qE "^\s*$ENV_NAME\s"; then
    info "Removing conda env: $ENV_NAME"
    conda remove -n "$ENV_NAME" --all -y || true
  fi
}

uninstall_all() {
  info "Uninstalling $APP_NAME (safe defaults)..."
  stop_disable_unit
  remove_unit
  remove_conda_env
  info "Uninstall completed."
}

copy_app_sources() {
  [[ -d "$SRC_DIR" ]] || die "Missing source directory: $SRC_DIR (expected dashboard/ in repo)"
  info "Configuring app in $SRC_DIR"
  # Ensure directory exists (though it should already be in repo)
  # Handle .env configuration
  if [[ -f "$SRC_DIR/.env.example" ]]; then
    cp -n "$SRC_DIR/.env.example" "$SRC_DIR/.env"
  fi

  # Apply defaults to .env
  sed -i "s/^PORT=.*/PORT=$PORT/" "$SRC_DIR/.env" || true
  sed -i "s/^BIND_HOST=.*/BIND_HOST=$BIND_HOST/" "$SRC_DIR/.env" || true
  if ! grep -q "^BIND_HOST=" "$SRC_DIR/.env"; then
    echo "BIND_HOST=$BIND_HOST" >> "$SRC_DIR/.env"
  fi
  sed -i "s|^SERVICES=.*|SERVICES=$SERVICES|" "$SRC_DIR/.env" || true
  if ! grep -q "^SERVICES=" "$SRC_DIR/.env"; then
    echo "SERVICES=$SERVICES" >> "$SRC_DIR/.env"
  fi

  # Generate SECRET_KEY if empty
  gen_hex() {
    if command -v openssl &>/dev/null; then
      openssl rand -hex 16
    else
      # fallback
      (head -c 16 /dev/urandom 2>/dev/null | xxd -p) || date +%s%N
    fi
  }
  if ! grep -q "^SECRET_KEY=" "$SRC_DIR/.env"; then
    echo "SECRET_KEY=$(gen_hex)" >> "$SRC_DIR/.env"
  else
    if [[ -z "$(grep '^SECRET_KEY=' "$SRC_DIR/.env" | cut -d= -f2-)" ]]; then
      sed -i "s/^SECRET_KEY=.*/SECRET_KEY=$(gen_hex)/" "$SRC_DIR/.env"
    fi
  fi
}

write_unit() {
  info "Writing user systemd unit: $UNIT_PATH"
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_PATH" <<EOF
[Unit]
Description=ComfyUI Dashboard
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/$REPO_NAME/dashboard
# Environment provided here for gunicorn bind and app config
Environment=SERVICES=$SERVICES
Environment=CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes
Environment=PATH=%h/miniconda3/envs/$ENV_NAME/bin:%h/miniconda3/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=%h/miniconda3/envs/$ENV_NAME/bin/gunicorn -c gunicorn.conf.py app:app --log-level debug --access-logfile - --error-logfile -
# ExecStart=/bin/bash -lc 'source %h/miniconda3/etc/profile.d/conda.sh && %h/miniconda3/bin/conda run -n $ENV_NAME gunicorn -c gunicorn.conf.py app:app'
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
}

enable_start() {
  if [[ "$START_AFTER" == "true" ]]; then
    info "Enabling and starting service: $SERVICE_NAME"
    systemctl --user enable "$SERVICE_NAME"
    systemctl --user restart "$SERVICE_NAME" || systemctl --user start "$SERVICE_NAME"
  else
    info "Skipping service enable/start (--no-start)"
  fi
}

create_env_and_deps() {
  info "Creating conda env: $ENV_NAME (python=3.11)"
  CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes conda create -n "$ENV_NAME" python=3.11 -y

  info "Upgrading pip in env"
  CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes conda run -n "$ENV_NAME" python -m pip install --upgrade pip

  info "Installing Python dependencies in env: Flask, Gunicorn, python-dotenv"
  CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes conda run -n "$ENV_NAME" python -m pip install flask gunicorn python-dotenv

  info "Verifying installed packages in env"
  MISSING=$(CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes conda run -n "$ENV_NAME" python - <<'PY'
import importlib.util
mods=["flask","gunicorn","dotenv"]
missing=[m for m in mods if importlib.util.find_spec(m) is None]
print(",".join(missing))
PY
)
  if [[ -n "$MISSING" ]]; then
    warn "Missing packages after install: $MISSING (retrying once)"
    CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes conda run -n "$ENV_NAME" python -m pip install $MISSING || true
    MISSING=$(CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes conda run -n "$ENV_NAME" python - <<'PY'
import importlib.util
mods=["flask","gunicorn","dotenv"]
missing=[m for m in mods if importlib.util.find_spec(m) is None]
print(",".join(missing))
PY
)
    if [[ -n "$MISSING" ]]; then
      die "Failed to install required packages into env $ENV_NAME. Still missing: $MISSING"
    fi
  fi
}

post_install_notes() {
  echo ""
  info "Install complete."
  echo "Service:     $SERVICE_NAME (user scope)"
  echo "App Dir:     $SRC_DIR (local repo)"
  echo "Conda Env:   $ENV_NAME"
  echo "Bind:        $BIND_HOST"
  echo "Port:        $PORT"
  echo "Dashboard:   http://$BIND_HOST:$PORT (remote accessible by default; secure with firewall and ACTION_TOKEN)"
  echo ""
  echo "Manage service:"
  echo "  systemctl --user status $SERVICE_NAME"
  echo "  systemctl --user restart $SERVICE_NAME"
  echo "  journalctl --user -u $SERVICE_NAME -f"
  echo ""
  echo "Start at boot (optional, once):"
  echo "  sudo loginctl enable-linger $USER"
  echo ""
  echo "Run tests: cd ../test && ./test_dashboard.sh"
}

# Main
ensure_conda

if [[ "$UNINSTALL_ONLY" == "true" ]]; then
  uninstall_all
  exit 0
fi

if [[ "$REINSTALL" == "true" ]]; then
  uninstall_all
fi

create_env_and_deps
copy_app_sources
write_unit
enable_start
post_install_notes
