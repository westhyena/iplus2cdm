#!/bin/bash

# -------------------------------------------------------------------------
# Run Achilles Wrapper Script
# -------------------------------------------------------------------------

set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

# Check if R is installed
if ! command -v Rscript &> /dev/null; then
    echo "Error: Rscript is not found. Please install R."
    echo "You can try running bin/install_achilles.sh if on Ubuntu, or install R for your OS."
    exit 1
fi

echo "=================================================="
echo "Starting Achilles Analysis"
echo "=================================================="

Rscript "$SCRIPT_DIR/run_achilles.R"
