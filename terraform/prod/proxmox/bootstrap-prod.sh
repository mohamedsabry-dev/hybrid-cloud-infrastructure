#!/bin/bash
#
# Create tf_prod user with full admin privileges on Proxmox VE 9.1
# This user will have API token access (no password) for Terraform automation
#

set -e

# Configuration
USERNAME="tf_prod"
REALM="pve"
TOKEN_ID="terraform"
FULL_USER="${USERNAME}@${REALM}"

echo "============================================"
echo "Creating Proxmox user: ${FULL_USER}"
echo "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root"
   exit 1
fi

# Check if user already exists
if pveum user list | grep -q "^${FULL_USER}"; then
    echo "Warning: User ${FULL_USER} already exists"
    read -p "Do you want to delete and recreate? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Deleting existing user..."
        pveum user delete "${FULL_USER}" || true
    else
        echo "Aborting."
        exit 1
    fi
fi

# Create user without password (token-only access)
echo "Creating user ${FULL_USER}..."
pveum user add "${FULL_USER}" --comment "Terraform Production - Full Admin Access"

# Assign Administrator role at root path (full access to entire Proxmox)
echo "Assigning Administrator role at root path..."
pveum acl modify / --users "${FULL_USER}" --roles Administrator

# Create API token (non-expiring, with full privileges)
echo "Creating API token..."
TOKEN_OUTPUT=$(pveum user token add "${FULL_USER}" "${TOKEN_ID}" --privsep 0 --expire 0 2>&1)

cat << EOF

============================================
SUCCESS: User and token created!
============================================

User Details:
  Username: ${FULL_USER}
  Role: Administrator
  Scope: / (entire Proxmox cluster)

============================================
API TOKEN CREDENTIALS - SAVE THESE NOW!
============================================

${TOKEN_OUTPUT}

Token ID: ${FULL_USER}!${TOKEN_ID}

============================================
Terraform Provider Configuration Example:
============================================

provider "proxmox" {
  pm_api_url          = "https://<proxmox-host>:8006/api2/json"
  pm_api_token_id     = "${FULL_USER}!${TOKEN_ID}"
  pm_api_token_secret = "<token-value-from-above>"
  pm_tls_insecure     = true  # Set to false in production with valid certs
}

============================================
EOF
