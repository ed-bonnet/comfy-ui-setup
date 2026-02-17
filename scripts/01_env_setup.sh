#!/usr/bin/env bash
set -euo pipefail

# Script 01: Environment Setup
# Load .env file and validate required environment variables using utils.sh

echo "🔧 Step 01: Environment Setup"

# Source the utils.sh script
source "$(dirname "$0")/utils.sh"

# Load and validate environment
setup_environment

echo "✅ Step 01 completed: Environment setup successful"
