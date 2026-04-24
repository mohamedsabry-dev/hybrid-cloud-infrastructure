#!/bin/bash
################################################################################
# Simple User Creation Script with Password
################################################################################

set -e  # Exit on any error

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root (use sudo)"
   exit 1
fi

################################################################################
# CONFIGURATION - Edit these values
################################################################################

USERNAME="veeam_emergency"
USER_COMMENT="Local Emergency Backup User"
USER_PASSWORD="Change_Me"  # Change the default password after first login
ENABLE_PASSWORDLESS_SUDO="no"  # yes or no (no = requires password for sudo)

################################################################################
# SCRIPT START
################################################################################

echo "=================================="
echo "User Creation Script"
echo "=================================="
echo ""

# Step 1: Create User
echo "[1/2] Creating user: $USERNAME"
if id "$USERNAME" &>/dev/null; then
    echo "  → User already exists"
else
    useradd -m -s /bin/bash -c "$USER_COMMENT" "$USERNAME"
    echo "  → User created successfully"
fi
echo ""

# Step 2: Set Password
echo "[2/2] Setting password"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "  → Password set"
echo ""

# Step 3: Configure Sudo Access
echo "[3/3] Configuring sudo access"
SUDOERS_FILE="/etc/sudoers.d/$USERNAME"

if [ "$ENABLE_PASSWORDLESS_SUDO" = "yes" ]; then
    # Passwordless sudo - no password required
    echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
else
    # Sudo with password - password required for sudo commands
    echo "$USERNAME ALL=(ALL) ALL" > "$SUDOERS_FILE"
fi

chmod 440 "$SUDOERS_FILE"

# Validate sudoers file
if visudo -cf "$SUDOERS_FILE"; then
    if [ "$ENABLE_PASSWORDLESS_SUDO" = "yes" ]; then
        echo "  → Sudo enabled (passwordless)"
    else
        echo "  → Sudo enabled (requires password)"
    fi
else
    echo "  No ERROR: Invalid sudoers configuration, removing file"
    rm -f "$SUDOERS_FILE"
    exit 1
fi
echo ""

################################################################################
# SUMMARY
################################################################################

echo "=================================="
echo "Yes User Setup Complete!"
echo "=================================="
echo "Username:     $USERNAME"
echo "Password:     $USER_PASSWORD"
echo "Sudo Access:  $([ "$ENABLE_PASSWORDLESS_SUDO" = "yes" ] && echo "Enabled (passwordless)" || echo "Enabled (requires password)")"
echo ""
echo "Test login with:"
echo "  su - $USERNAME"
echo ""
echo "Test sudo with:"
echo "  sudo whoami  # Will $([ "$ENABLE_PASSWORDLESS_SUDO" = "yes" ] && echo "NOT" || echo "")ask for password"
echo ""
