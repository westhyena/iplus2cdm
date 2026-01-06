#!/bin/bash

# -------------------------------------------------------------------------
# Run Achilles Ares Export
# -------------------------------------------------------------------------
# This script executes the R script to export Achilles results to Ares format.
# Usage:
#   bin/run_achilles_export.sh
# -------------------------------------------------------------------------

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJECT_ROOT="$SCRIPT_DIR/.."

# Load environment variables
ENV_FILE="$PROJECT_ROOT/.env"

if [ -f "$ENV_FILE" ]; then
    echo "Loading configuration from $ENV_FILE"
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
else
    echo "Warning: .env file not found at $ENV_FILE"
    echo "Using existing environment variables or defaults."
fi

echo "=================================================="
echo "Starting Achilles Ares Export"
echo "=================================================="

if ! command -v Rscript &> /dev/null; then
    echo "Error: Rscript is not found. Please install R."
    exit 1
fi

Rscript "$SCRIPT_DIR/export_achilles_ares.R"
