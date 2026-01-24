#!/bin/bash
# ============================================================================
# LEGACY ANSIBLE SERVICE ACCOUNT CONFIGURATION (CLEAN VERSION)
# ============================================================================
# Purpose: Create 'sshadmin' user for Ansible VM to manage IPA and K8s nodes
# Security: Passwordless sudo for automation - USE WITH CAUTION
# ============================================================================

# Authenticate as IPA admin first
kinit admin

# ----------------------------------------------------------------------------
# STEP 1: Create Service Account and SSH Access Group
# ----------------------------------------------------------------------------

# Create the sshadmin user (service account for Ansible automation)
ipa user-add sshadmin --first=SSH --last=Admin --password

# Create group for SSH access control
ipa group-add sshusers --desc="Users allowed to SSH into managed clients"

# Add sshadmin to sshusers group
ipa group-add-member sshusers --users=sshadmin

# Add sshadmin to IPA admins group (full IPA admin privileges)
ipa group-add-member admins --users=sshadmin

# ----------------------------------------------------------------------------
# STEP 2: Configure HBAC Rules (SSH Access Control)
# ----------------------------------------------------------------------------

# Create HBAC rule for SSH access
ipa hbacrule-add allow_ssh --desc="Allow sshusers group to SSH to managed hosts"

# Associate SSHD service with the rule
ipa hbacrule-add-service allow_ssh --hbacsvcs=sshd

# Add sshusers group to the rule
ipa hbacrule-add-user allow_ssh --groups=sshusers

# Add all managed hosts to the rule
ipa hbacrule-add-host allow_ssh --hosts=ipa.home.lab
ipa hbacrule-add-host allow_ssh --hosts=ansible.home.lab
ipa hbacrule-add-host allow_ssh --hosts=k8s-master.home.lab
ipa hbacrule-add-host allow_ssh --hosts=k8s-worker1.home.lab
ipa hbacrule-add-host allow_ssh --hosts=k8s-worker2.home.lab

# ----------------------------------------------------------------------------
# STEP 3: Configure Sudo Rules (Passwordless Root Access)
# ----------------------------------------------------------------------------

# Create sudo rule for passwordless root access (DANGEROUS - Automation only!)
ipa sudorule-add allow-root-nopass \
    --desc="Passwordless sudo for sshadmin service account" \
    --cmdcat=all

# Add ONLY sshadmin user (NOT the entire sshusers group for security)
ipa sudorule-add-user allow-root-nopass --users=sshadmin

# Add all managed hosts
ipa sudorule-add-host allow-root-nopass --hosts=ipa.home.lab
ipa sudorule-add-host allow-root-nopass --hosts=ansible.home.lab
ipa sudorule-add-host allow-root-nopass --hosts=k8s-master.home.lab
ipa sudorule-add-host allow-root-nopass --hosts=k8s-worker1.home.lab
ipa sudorule-add-host allow-root-nopass --hosts=k8s-worker2.home.lab

# Disable password prompt for sudo
ipa sudorule-add-option allow-root-nopass --sudooption='!authenticate'

# Allow running commands as root
ipa sudorule-add-runasuser allow-root-nopass --users=root

# ----------------------------------------------------------------------------
# STEP 4: Verification
# ----------------------------------------------------------------------------

echo "================================"
echo "Configuration Complete!"
echo "================================"
echo ""
echo "Verify with the following commands:"
echo ""
echo "1. Check HBAC rules:"
echo "   ipa hbacrule-show allow_ssh"
echo ""
echo "2. Check sudo rules:"
echo "   ipa sudorule-show allow-root-nopass"
echo ""
echo "3. Test HBAC access:"
echo "   ipa hbactest --user=sshadmin --host=k8s-master.home.lab --service=sshd"
echo ""
echo "4. Test SSH from Ansible VM:"
echo "   ssh sshadmin@k8s-master.home.lab 'sudo whoami'"
echo "   (Should return 'root' without password prompt)"
echo ""

# Destroy admin ticket
kdestroy
