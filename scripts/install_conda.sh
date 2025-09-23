#!/usr/bin/env bash
# install_conda.sh
# Purpose: Ensure Conda (Miniconda) is installed and available on PATH.
# - Idempotent: If conda is already installed, prints explicit message and exits 0
# - If Miniconda directory exists but conda is not on PATH, attempts to fix PATH/init
# - Otherwise downloads and installs Miniconda for the current architecture
# - Does NOT create any environments or install other packages
# - Does NOT handle Anaconda TOS (left to caller if needed)

set -euo pipefail

MINICONDA_DIR="$HOME/miniconda3"
CONDA_BIN="conda"

have_conda() {
  command -v "$CONDA_BIN" &>/dev/null
}

print_conda_info() {
  local path
  path="$(command -v conda || true)"
  if [[ -n "${path}" ]]; then
    echo "✅ Conda available: ${path}"
    conda --version || true
  fi
}

warn_if_conda_update_available() {
  # Check if a newer conda is available and print an update hint + latest version
  # We use the defaults channel and auto-accept TOS to avoid prompts during dry-run.
  local out latest_pkg latest_ver
  out=$(CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes conda update -n base -c defaults conda --dry-run -y 2>/dev/null || true)
  if echo "$out" | grep -q "All requested packages already installed."; then
    return 0
  fi
  if echo "$out" | grep -qiE "will be updated"; then
    # Extract the target version from the dry-run plan
    latest_pkg=$(printf "%s\n" "$out" | awk '/The following packages will be UPDATED:/{flag=1; next} flag && $1=="conda"{for(i=1;i<=NF;i++){if($i=="-->"){print $(i+1); exit}}}')
    # Trim to numeric version prefix (strip build string)
    latest_ver=$(printf "%s" "$latest_pkg" | sed -E 's/^([0-9]+(\.[0-9]+)*).*/\1/')
    if [[ -n "$latest_ver" ]]; then
      echo "⚠️ Newer Conda version available: $latest_ver"
    else
      echo "⚠️ Newer Conda version available."
    fi
    echo "   Update with this command:"
    echo "   CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes conda update -n base -c defaults conda"
  fi
}

echo "🔧 Conda installer helper (install_conda.sh)"

# 1) If conda already on PATH → done
if have_conda; then
  echo "✅ Conda already installed and available on PATH."
  print_conda_info
  warn_if_conda_update_available
  exit 0
fi

# 2) If Miniconda dir exists but conda not on PATH → attempt to fix PATH/init
if [[ -d "${MINICONDA_DIR}" ]]; then
  echo "📁 Detected existing Miniconda at ${MINICONDA_DIR} but 'conda' not on PATH."
  echo "🔧 Attempting to initialize and fix PATH..."
  # Add to current PATH
  export PATH="${MINICONDA_DIR}/bin:${PATH}"

  # Initialize conda for bash if possible
  if [[ -x "${MINICONDA_DIR}/bin/conda" ]]; then
    "${MINICONDA_DIR}/bin/conda" init bash || true
  fi

  # Source conda profile if present
  if [[ -f "${MINICONDA_DIR}/etc/profile.d/conda.sh" ]]; then
    # shellcheck disable=SC1090
    source "${MINICONDA_DIR}/etc/profile.d/conda.sh"
  fi

  if have_conda; then
    echo "✅ Conda PATH/init fixed."
    print_conda_info
    warn_if_conda_update_available
    echo "ℹ️ New shells may require: source ~/.bashrc"
    exit 0
  else
    echo "⚠️ Conda still not available after PATH/init attempt."
    echo "   Proceeding to (re)install Miniconda in-place at ${MINICONDA_DIR}."
  fi
fi

# 3) Fresh (or in-place) install of Miniconda
arch="$(uname -m)"
case "${arch}" in
  x86_64)
    installer="Miniconda3-latest-Linux-x86_64.sh"
    ;;
  aarch64|arm64)
    installer="Miniconda3-latest-Linux-aarch64.sh"
    ;;
  *)
    echo "❌ Unsupported architecture: ${arch}"
    echo "   Supported: x86_64, aarch64/arm64"
    exit 1
    ;;
esac

url="https://repo.anaconda.com/miniconda/${installer}"
tmp_installer="/tmp/miniconda.sh"

echo "📥 Downloading Miniconda installer for ${arch}..."
if command -v curl &>/dev/null; then
  curl -fsSL "${url}" -o "${tmp_installer}"
elif command -v wget &>/dev/null; then
  wget -q -O "${tmp_installer}" "${url}"
else
  echo "❌ Neither curl nor wget is available to download Miniconda."
  echo "   Please install curl or wget, then re-run this script."
  exit 1
fi

echo "🛠️ Installing Miniconda to ${MINICONDA_DIR}..."
bash "${tmp_installer}" -b -p "${MINICONDA_DIR}"

# Initialize conda for bash
if [[ -x "${MINICONDA_DIR}/bin/conda" ]]; then
  "${MINICONDA_DIR}/bin/conda" init bash || true
fi

# Make conda available in current shell
export PATH="${MINICONDA_DIR}/bin:${PATH}"
if [[ -f "${MINICONDA_DIR}/etc/profile.d/conda.sh" ]]; then
  # shellcheck disable=SC1090
  source "${MINICONDA_DIR}/etc/profile.d/conda.sh"
fi

if have_conda; then
  echo "✅ Miniconda installed successfully."
  print_conda_info
  warn_if_conda_update_available
  echo "ℹ️ If conda is not available in new terminals, run: source ~/.bashrc"
  exit 0
else
  echo "❌ Conda not found after installation. Please check ${MINICONDA_DIR} and your shell init files."
  exit 1
fi
