#!/usr/bin/env bash
set -euo pipefail

# Main orchestrator script for ComfyUI Docker environment setup
# Calls numbered scripts in sequence for modular, testable deployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Default values
SKIP_STEPS=""
DRY_RUN=false
VERBOSE=false

# Function to display usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Deploy ComfyUI Docker environment with modular, step-by-step execution.

OPTIONS:
    -s, --skip STEPS      Skip specific steps (comma-separated, e.g., "02,05")
    -d, --dry-run         Show what would be executed without running
    -v, --verbose         Enable verbose output
    -h, --help            Show this help message

AVAILABLE STEPS:
    01 - Environment setup (.env loading and validation)
    02 - NVIDIA GPU setup (drivers and container toolkit)
    03 - Docker installation and configuration
    04 - Volume creation (shared storage directories)
    05 - Base image build (CUDA/PyTorch foundation)
    06 - ComfyUI install script generation
    07 - Application image build
    08 - Service deployment (container startup)

EXAMPLES:
    $0                    # Run all steps
    $0 -s 02,03          # Skip NVIDIA and Docker setup
    $0 -d                # Dry run to see execution plan
    $0 -v                # Verbose mode for debugging
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--skip)
            SKIP_STEPS="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Function to check if a step should be skipped
should_skip_step() {
    local step="$1"
    if [[ -n "$SKIP_STEPS" ]]; then
        IFS=',' read -ra SKIP_ARRAY <<< "$SKIP_STEPS"
        for skip_step in "${SKIP_ARRAY[@]}"; do
            if [[ "$skip_step" == "$step" ]]; then
                return 0  # Skip this step
            fi
        done
    fi
    return 1  # Don't skip
}

# Function to run a script with proper error handling
run_script() {
    local step="$1"
    local script_name="$2"
    local script_path="${SCRIPTS_DIR}/${script_name}"
    
    if [[ ! -f "$script_path" ]]; then
        echo "Error: Script not found: $script_path" >&2
        return 1
    fi
    
    if should_skip_step "$step"; then
        echo "⏭️  Skipping step $step: $script_name"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "📋 [DRY RUN] Would execute: $script_path"
        return 0
    fi
    
    echo "🚀 Executing step $step: $script_name"
    
    # Make script executable
    chmod +x "$script_path"
    
    # Run the script
    if [[ "$VERBOSE" == "true" ]]; then
        bash -x "$script_path"
    else
        bash "$script_path"
    fi
    
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "❌ Step $step failed with exit code: $exit_code" >&2
        return $exit_code
    fi
    
    echo "✅ Step $step completed successfully: $script_name"
    return 0
}

# Main execution function
main() {
    echo "🔧 Starting ComfyUI Docker Environment Deployment"
    echo "================================================"
    
    # Check if scripts directory exists
    if [[ ! -d "$SCRIPTS_DIR" ]]; then
        echo "Error: Scripts directory not found: $SCRIPTS_DIR" >&2
        echo "Please ensure all numbered scripts are in the scripts/ directory" >&2
        return 1
    fi
    
    # Execute steps in order
    run_script "01" "01_env_setup.sh" || return $?
    run_script "02" "02_nvidia_setup.sh" || return $?
    run_script "03" "03_docker_setup.sh" || return $?
    run_script "04" "04_volumes_setup.sh" || return $?
    run_script "05" "05_build_base_image.sh" || return $?
    run_script "06" "06_create_install_script.sh" || return $?
    run_script "07" "07_build_app_image.sh" || return $?
    run_script "08" "08_deploy_services.sh" || return $?
    
    echo "================================================"
    echo "🎉 Deployment completed successfully!"
    echo ""
    echo "Access your services:"
    echo "• ComfyUI: http://<host>:${COMFYUI_PORT:-8188}"
    echo "• Dashboard: http://<host>:${DASHBOARD_PORT:-3230}"
}

# Run main function
main "$@"
