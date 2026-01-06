#!/bin/bash

# -------------------------------------------------------------------------
# Run Achilles Results Server
# -------------------------------------------------------------------------
# 1. Runs the R script to export Achilles results to JSON.
# 2. Starts a Python HTTP server to view the results.
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

# Set output path for JSON files if not set in env
export ACHILLES_OUTPUT_PATH="${ACHILLES_OUTPUT_PATH:-$PROJECT_ROOT/achilles_results}"
SERVER_PORT="${ACHILLES_SERVER_PORT:-8000}"

echo "=================================================="
echo "Step 1: Exporting Achilles Results to JSON"
echo "=================================================="

if ! command -v Rscript &> /dev/null; then
    echo "Error: Rscript is not found. Please install R."
    exit 1
fi

Rscript "$SCRIPT_DIR/export_achilles_json.R"

echo "=================================================="
echo "Step 2: Starting Python HTTP Server"
echo "=================================================="
echo "Serving files from: $ACHILLES_OUTPUT_PATH"
echo "Open your browser to: http://localhost:$SERVER_PORT/Ares/ares/index.html"
echo "Note: If you are using standard AchillesWeb or Atlas, point to the correct index file."
echo "If this is just raw JSON, you can browse directory."
echo "=================================================="

# Check for python3
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
else
    echo "Error: Python is not found. Please install Python."
    exit 1
fi

# Change to the directory containing the results so the root is correct for the server
cd "$ACHILLES_OUTPUT_PATH"

$PYTHON_CMD -m http.server "$SERVER_PORT"
