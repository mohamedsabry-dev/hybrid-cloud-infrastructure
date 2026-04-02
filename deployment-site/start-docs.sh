#!/bin/bash
#
# =============================================================================
# START DOCUMENTATION SERVER
# =============================================================================
#
# Starts the interactive documentation server for the Hybrid Cloud
# Infrastructure repository. This server provides live file browsing
# with syntax highlighting for all repository files.
#
# Usage:
#   ./deployment-site/start-docs.sh [--port 8080]
#
# Then open: http://localhost:8080
#
# =============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   HYBRID CLOUD INFRASTRUCTURE - DOCUMENTATION SERVER      ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if Python3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}❌ Python3 is required but not installed.${NC}"
    exit 1
fi

# Parse arguments
PORT=${1:-8080}
if [[ "$1" == "--port" ]] || [[ "$1" == "-p" ]]; then
    PORT=${2:-8080}
fi

echo -e "  ${GREEN}Starting server on port ${PORT}...${NC}"
echo ""

# Start the server
cd "$SCRIPT_DIR"
python3 serve-docs.py --port "$PORT"
