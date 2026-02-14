#!/usr/bin/env bash
set -e

echo ""
echo "=== Proxmox VE 9.x Post-Install Bootstrap (PROD) ==="
echo ""

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Run as root"
    exit 1
fi

# --- 1. Disable Sleep/Suspend ---
echo "[1/7] Disabling sleep/suspend..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
echo "Done."
echo ""
read -p "Press Enter to continue..."

# --- 2. Fix APT Repos ---
echo ""
echo "[2/7] Fixing APT repositories..."
SOURCES_DIR="/etc/apt/sources.list.d"
for f in ceph.sources pve-enterprise.list pve-enterprise.sources; do
    [[ -f "${SOURCES_DIR}/$f" ]] && mv "${SOURCES_DIR}/$f" "${SOURCES_DIR}/${f}.disabled" && echo "Disabled: $f"
done
# Only create if pve-install-repo.list doesn't already have trixie no-subscription
if grep -q "trixie pve-no-subscription" "${SOURCES_DIR}/pve-install-repo.list" 2>/dev/null; then
    echo "No-subscription repo already exists in pve-install-repo.list"
else
    echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" > "${SOURCES_DIR}/pve-no-subscription.list"
    echo "Created: pve-no-subscription.list"
fi
echo ""
read -p "Press Enter to continue..."

# --- 3. APT Update ---
echo ""
echo "[3/7] Running apt update..."
apt update
echo ""
read -p "Press Enter to continue..."

# --- 4. APT Upgrade ---
echo ""
echo "[4/7] Running apt upgrade..."
apt upgrade -y
echo ""
read -p "Press Enter to continue..."

# --- 5. Enable Snippets on Local Storage ---
echo ""
echo "[5/8] Enabling snippets on local storage..."
mkdir -p /var/lib/vz/snippets
/usr/sbin/pvesm set local --content backup,iso,vztmpl,snippets
echo "Done."
echo ""
read -p "Press Enter to continue..."

# --- 6. Remove Subscription Nag ---
echo ""
echo "[6/8] Removing subscription nag..."
PROXMOXLIB="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
if [[ -f "$PROXMOXLIB" ]]; then
    sed -Ezi.bak "s/(Ext\.Msg\.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" "$PROXMOXLIB"
    echo "Patched: proxmoxlib.js"
else
    echo "proxmoxlib.js not found, skipping"
fi
echo ""
read -p "Press Enter to continue..."

# --- 7. Create admin_prod Management User (PAM) ---
echo ""
echo "[7/8] Creating admin_prod management user (PAM)..."

ADMIN_NAME="admin_prod"
ADMIN_USER="${ADMIN_NAME}@pam"

# Check if Linux user exists
if id "$ADMIN_NAME" &>/dev/null; then
    echo "Linux user ${ADMIN_NAME} already exists"
else
    echo "Creating Linux user ${ADMIN_NAME}..."
    useradd -m -s /bin/bash "$ADMIN_NAME"
    echo "Set password for ${ADMIN_NAME}:"
    passwd "$ADMIN_NAME"
fi

# Check if Proxmox user exists
if pveum user list | grep -q "^${ADMIN_USER}"; then
    echo "Proxmox user ${ADMIN_USER} already exists"
else
    pveum user add "${ADMIN_USER}" --comment "Admin Prod - Full Admin"
fi

# Ensure admin role
pveum acl modify "/" --users "${ADMIN_USER}" --roles Administrator

echo ""
echo "==========================================="
echo "  ADMIN USER CREATED (PAM)"
echo "==========================================="
echo "Username: ${ADMIN_USER}"
echo "Scope: / (Full Admin)"
echo "Can login via: Console, SSH, and Web GUI"
echo "==========================================="
echo ""
read -p "Press Enter to continue..."

# --- 8. Create tf_prod Automation User ---
echo ""
echo "[8/8] Creating tf_prod automation user..."

USERNAME="tf_prod"
REALM="pve"
TOKEN_ID="terraform"
FULL_USER="${USERNAME}@${REALM}"

if pveum user list | grep -q "^${FULL_USER}"; then
    echo "User ${FULL_USER} already exists"
    read -p "Delete and recreate? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        pveum user delete "${FULL_USER}" || true
    else
        echo "Skipping user creation"
        SKIP_USER=1
    fi
fi

if [[ -z "$SKIP_USER" ]]; then
    pveum user add "${FULL_USER}" --comment "Terraform Prod - Full Admin"
    pveum acl modify "/" --users "${FULL_USER}" --roles Administrator

    echo ""
    echo "==========================================="
    echo "  API TOKEN - SAVE THIS NOW!"
    echo "==========================================="
    pveum user token add "${FULL_USER}" "${TOKEN_ID}" --privsep 0 --expire 0
    echo ""
    echo "Token ID: ${FULL_USER}!${TOKEN_ID}"
    echo "Scope: / (Full Admin)"
    echo "==========================================="
fi

echo ""
echo "All configurations complete!"
echo ""
read -p "Press Enter to restart services (session may disconnect)..."

# --- Restart Services (LAST STEP) ---
echo ""
echo "Restarting pveproxy..."
systemctl restart pveproxy

echo ""
echo "=== Done! Clear browser cache and refresh web UI ==="
echo ""
