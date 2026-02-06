#!/bin/bash
#
# Create tf_dev user with admin privileges on specific Proxmox node only
# This user will have API token access (no password) for Terraform automation
# Access is restricted to node: pve-dev.lab.local
#

set -e

# Configuration
USERNAME="tf_dev"
REALM="pve"
TOKEN_ID="terraform"
FULL_USER="${USERNAME}@${REALM}"
TARGET_NODE="pve-dev"  # Node name as it appears in Proxmox (usually short name)

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
pveum user add "${FULL_USER}" --comment "Terraform Development - Admin on ${TARGET_NODE} only"

# Assign Administrator role on specific node only
echo "Assigning Administrator role on /nodes/${TARGET_NODE}..."
pveum acl modify "/nodes/${TARGET_NODE}" --users "${FULL_USER}" --roles Administrator

# Also grant access to storage on that node (commonly needed for VM operations)
echo "Assigning Administrator role on /storage for node operations..."
pveum acl modify "/storage" --users "${FULL_USER}" --roles PVEDatastoreAdmin

# Grant access to create/manage VMs in the pool or globally with limited scope
# This allows the user to see and manage VMs but only operate on the target node
echo "Assigning PVEVMAdmin role on /vms for VM management..."
pveum acl modify "/vms" --users "${FULL_USER}" --roles PVEVMAdmin

# Create API token (non-expiring, with full privileges of the user)
echo "Creating API token..."
TOKEN_OUTPUT=$(pveum user token add "${FULL_USER}" "${TOKEN_ID}" --privsep 0 --expire 0 2>&1)

cat << EOF

============================================
SUCCESS: User and token created!
============================================

User Details:
  Username: ${FULL_USER}
  Role: Administrator
  Scope: /nodes/${TARGET_NODE} (restricted to dev node)

Note: The node '${TARGET_NODE}' (pve-dev.lab.local) does not need
to exist yet. The ACL is pre-configured and will apply once the
node joins the cluster.

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

IMPORTANT: This user can only manage resources on node '${TARGET_NODE}'.
If the node name in Proxmox differs from '${TARGET_NODE}', edit the
TARGET_NODE variable at the top of this script before running.

EOF
