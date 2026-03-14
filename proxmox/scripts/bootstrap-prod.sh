#!/usr/bin/env bash
# 1. Disable Sleep/Suspend
# 2. Ensure DNS (add 8.8.8.8 fallback)
# 3. Fix APT Repos
# 4. APT Update & Upgrade
# 5. Remove Subscription Nag
# 6. Create admin_prod Management User (PAM)
# 7. Create tf_prod Automation User


set -e

echo ""
echo "=== Proxmox VE 9.x Post-Install Bootstrap ==="
echo ""

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Run as root"
    exit 1
fi

# ======================================================================= #
# ======================================================================= #
# ======================================================================= #


# --- 1. Disable Sleep/Suspend ---
echo ""
echo "[1/7] Disabling sleep/suspend..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
echo "Done."


# ======================================================================= #
# ======================================================================= #
# ======================================================================= #


# --- 2. Ensure DNS (fallback to 8.8.8.8) ---
echo ""
echo "[2/7] Ensuring DNS configuration..."

RESOLV_CONF="/etc/resolv.conf"
FALLBACK_DNS="nameserver 8.8.8.8"

if grep -q "8.8.8.8" "$RESOLV_CONF" 2>/dev/null; then
    echo "8.8.8.8 already in resolv.conf"
else
    echo "Adding 8.8.8.8 as fallback DNS..."
    echo "$FALLBACK_DNS" >> "$RESOLV_CONF"
    echo "Done."
fi


# ======================================================================= #
# ======================================================================= #
# ======================================================================= #


# --- 3. Fix APT Repos ---
echo ""
echo "[3/7] Fixing APT repositories..."

SOURCES_DIR="/etc/apt/sources.list.d"
ENTERPRISE_REPOS="ceph.sources pve-enterprise.list pve-enterprise.sources"
FREE_REPO="deb http://download.proxmox.com/debian/pve trixie pve-no-subscription"

# Disable enterprise repos (require paid subscription)
for file in $ENTERPRISE_REPOS; do
    if [[ -f "$SOURCES_DIR/$file" ]]; then
        mv "$SOURCES_DIR/$file" "$SOURCES_DIR/${file}.disabled"
        echo "Disabled: $file"
    fi
done

# Add free no-subscription repo if not exists
if grep -q "pve-no-subscription" "$SOURCES_DIR/pve-install-repo.list" 2>/dev/null; then
    echo "Free repo already exists"
else
    echo "$FREE_REPO" > "$SOURCES_DIR/pve-no-subscription.list"
    echo "Created: pve-no-subscription.list"
fi


# ======================================================================= #
# ======================================================================= #
# ======================================================================= #


# --- 4. APT Update & Upgrade ---
echo ""
echo "[4/7] Running apt update && upgrade..."
apt update && apt upgrade -y


# ======================================================================= #
# ======================================================================= #
# ======================================================================= #


# --- 5. Remove Subscription Nag ---
echo ""
echo "[5/7] Removing subscription nag..."
PROXMOXLIB="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
if [[ -f "$PROXMOXLIB" ]]; then
    sed -Ezi.bak "s/(Ext\.Msg\.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" "$PROXMOXLIB"
    echo "Patched: proxmoxlib.js"
else
    echo "proxmoxlib.js not found, skipping"
fi


# ======================================================================= #
# ======================================================================= #
# ======================================================================= #


# --- 6. Create admin_prod Management User (PAM) ---
echo ""
echo "[6/7] Creating admin_prod management user (PAM)..."

ADMIN_NAME="admin_prod"
ADMIN_USER="${ADMIN_NAME}@pam"

# Check if Linux user exists
if id "$ADMIN_NAME" &>/dev/null; then
    echo "Linux user ${ADMIN_NAME} already exists"
    SKIP_LINUX=1
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
echo "  ADMIN USER CREATED (PAM)"


# ======================================================================= #
# ======================================================================= #
# ======================================================================= #


# --- 7. Create tf_prod Automation User ---
echo ""
echo "[7/7] Creating tf_prod automation user..."

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

    echo "  API TOKEN - SAVE THIS NOW!"
    pveum user token add "${FULL_USER}" "${TOKEN_ID}" --privsep 0 --expire 0
    echo ""
    echo "Token ID: ${FULL_USER}!${TOKEN_ID}"
fi


# ======================================================================= #
# ======================================================================= #
# ======================================================================= #

echo ""
echo "=== All configurations complete! ==="
echo ""
read -p "Restart pveproxy now? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "Restarting pveproxy..."
    systemctl restart pveproxy
    echo "Done! Clear browser cache and refresh web UI."
else
    echo "Skipped. Run 'systemctl restart pveproxy' later to apply nag patch."
fi
