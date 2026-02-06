#!/bin/bash
#
# Create plan_cross_tf user with READ-ONLY access on Proxmox VE
# This user will have API token access for Terraform plan operations only
# Access: Read-only on entire Proxmox cluster (all nodes including dev)
#

set -e

# Configuration
USERNAME="plan_cross_tf"
REALM="pve"
TOKEN_ID="terraform"
FULL_USER="${USERNAME}@${REALM}"

echo "============================================"
echo "Creating Proxmox READ-ONLY user: ${FULL_USER}"
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
pveum user add "${FULL_USER}" --comment "Terraform Plan - Read-Only Access (all environments)"

# Assign PVEAuditor role at root path (read-only access to entire Proxmox)
echo "Assigning PVEAuditor (read-only) role at root path..."
pveum acl modify / --users "${FULL_USER}" --roles PVEAuditor

# Create API token (non-expiring, with full privileges of the user)
echo "Creating API token..."
TOKEN_OUTPUT=$(pveum user token add "${FULL_USER}" "${TOKEN_ID}" --privsep 0 --expire 0 2>&1)

cat << EOF

============================================
SUCCESS: Read-only user and token created!
============================================

User Details:
  Username: ${FULL_USER}
  Role: PVEAuditor (read-only)
  Scope: / (entire Proxmox cluster, all nodes)

This user can:
  - View all VMs, containers, nodes, storage
  - Run terraform plan

This user CANNOT:
  - Create, modify, or delete any resources
  - Run terraform apply

============================================
API TOKEN CREDENTIALS - SAVE THESE NOW!
============================================

${TOKEN_OUTPUT}

Token ID: ${FULL_USER}!${TOKEN_ID}

============================================
Terraform Provider Configuration Example:
============================================

provider "proxmox" {
  endpoint  = "https://<proxmox-host>:8006"
  api_token = "${FULL_USER}!${TOKEN_ID}=<token-value-from-above>"
  insecure  = true
}

============================================
EOF
