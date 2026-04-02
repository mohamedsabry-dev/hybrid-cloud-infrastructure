#!/bin/bash
#
# =============================================================================
# REFRESH REPOSITORY EXPLORER
# =============================================================================
#
# Quick script to regenerate the Repository Explorer in the documentation site.
# Run this anytime you want to update the visual file browser with the current
# repository structure.
#
# Usage:
#   ./deployment-site/refresh-explorer.sh
#
# Or from the deployment-site directory:
#   ./refresh-explorer.sh
#
# =============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     HYBRID CLOUD INFRASTRUCTURE - REPO EXPLORER REFRESH    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if Python3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}❌ Python3 is required but not installed.${NC}"
    exit 1
fi

# Run the generator
echo -e "${GREEN}🔄 Regenerating Repository Explorer...${NC}"
echo ""

python3 "$SCRIPT_DIR/generate-repo-explorer.py"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Done! Open index.html in your browser to see the updated   ${NC}"
echo -e "${GREEN}     repository explorer with the latest file structure.        ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  📂 File: ${BLUE}$SCRIPT_DIR/index.html${NC}"
echo ""

# Optionally open in browser (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    read -p "  Open in browser now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "$SCRIPT_DIR/index.html"
    fi
fi
