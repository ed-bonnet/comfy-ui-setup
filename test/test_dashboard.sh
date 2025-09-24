#!/usr/bin/env bash
# Test script for ComfyUI Dashboard deployment
# Run after install: Validates service, binding, access, and configs
set -euo pipefail

APP_NAME="comfyui-dashboard"
APP_DIR="$HOME/$APP_NAME"
SERVICE="$APP_NAME.service"
PORT="8080"
BIND_HOST="0.0.0.0"

info() { echo -e "➜ \e[32m$*\e[0m"; }
error() { echo -e "❌ \e[31m$*\e[0m" >&2; exit 1; }
pass() { echo -e "✅ \e[32m$*\e[0m"; }

check_service() {
  info "Checking service status..."
  if systemctl --user is-active --quiet "$SERVICE"; then
    pass "Service $SERVICE is active"
  else
    error "Service $SERVICE is not active"
  fi
}

check_bind() {
  info "Checking network binding..."
  if ss -tuln | grep -q "$BIND_HOST:$PORT"; then
    pass "Bound to $BIND_HOST:$PORT (remote accessible)"
  else
    error "Not bound to $BIND_HOST:$PORT (check .env and restart)"
  fi
}

check_env() {
  info "Checking .env config..."
  if [[ -f "$APP_DIR/.env" ]] && grep -q "^BIND_HOST=$BIND_HOST" "$APP_DIR/.env"; then
    pass "BIND_HOST=$BIND_HOST in .env"
  else
    error "BIND_HOST not set to $BIND_HOST in $APP_DIR/.env"
  fi
}

test_local() {
  info "Testing local access..."
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" | grep -q "^200$"; then
    pass "Local access OK (200)"
  else
    error "Local access failed (check service)"
  fi
}

test_remote() {
  info "Testing remote access..."
  LOCAL_IP=$(hostname -I | awk '{print $1}' | tr -d '[:space:]')
  if curl -s -o /dev/null -w "%{http_code}" "http://$LOCAL_IP:$PORT" | grep -q "^200$"; then
    pass "Remote access OK from $LOCAL_IP (200)"
  else
    error "Remote access failed (check firewall/bind)"
  fi
}

check_logs() {
  info "Checking recent logs for errors..."
  if ! journalctl --user -u "$SERVICE" -n 20 | grep -qi "error\|fail\|exception"; then
    pass "No errors in recent logs"
  else
    warn "Potential issues in logs (review: journalctl --user -u $SERVICE)"
  fi
}

# Run all checks
echo "=== ComfyUI Dashboard Tests ==="
check_service
check_bind
check_env
test_local
test_remote
check_logs
echo "=== All tests passed ==="

# Optional: Wait for service if restarting
# sleep 5  # Uncomment if needed post-restart
