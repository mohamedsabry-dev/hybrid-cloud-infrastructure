================================================================================
USER ACCOUNTS & AUTHENTICATION
Disaster Recovery Guide - Part 2
================================================================================
Last Updated: 2026-01-03
Back to: [README.md](README.md)

================================================================================
TABLE OF CONTENTS
================================================================================
1. Overview - Domain vs Emergency Users
2. Domain Account (Normal Operations)
3. Emergency Accounts (DR Scenarios)
4. Credential Storage & Security
5. Ansible Automation

================================================================================
1. OVERVIEW - DOMAIN VS EMERGENCY USERS
================================================================================

## Two-Tier Authentication Strategy

**Domain User (veeam@home.lab):**
- Purpose: Normal daily backup operations
- Requirement: Domain (FreeIPA) must be online
- Layer: Inner layer VMs (K8s, Vault, Jenkins, etc.)
- Auth: Passwordless sudo via domain membership

**Emergency User (veeam_emergency):**
- Purpose: Backup operations when domain is unavailable
- Requirement: Works even if IPA is offline
- Layer: Both inner and outer layers
- Auth: SSH key (inner layer) or Password (outer layer)

## When to Use Each Account

| Scenario | User Account | Layer | Authentication |
|----------|--------------|-------|----------------|
| Daily automated backups (inner layer) | veeam@home.lab | Inner (K8s, Vault, etc.) | Domain + Passwordless sudo |
| Manual backup when IPA online | veeam@home.lab | Inner | Domain + Passwordless sudo |
| IPA is down or unreachable | veeam_emergency | Inner | SSH key from Vault |
| Outer layer infrastructure backup | veeam_emergency | Outer (vCenter, ESXi, etc.) | Password |
| Emergency restore scenario | veeam_emergency | Both | SSH key or Password |

================================================================================
2. DOMAIN ACCOUNT (NORMAL OPERATIONS)
================================================================================

## veeam@home.lab

**Account Type:** FreeIPA domain user
**Primary Purpose:** Automated daily backups of inner layer VMs
**Scope:** 10 VMs on internal network (10.0.20.x)

### Systems Accessible

1. K8s Master
2. K8s Worker-1, K8s Worker-2, K8s Worker-3
3. Vault-01, Vault-02, Vault-03
4. Ansible
5. Jenkins
6. Monitor

### Authentication Method

- **SSH Access:** Domain-based authentication
- **Sudo Privileges:** Passwordless sudo enabled
- **Mechanism:** User is member of appropriate FreeIPA groups

### Configuration

```bash
# User is created in FreeIPA
# Groups: veeam_users (or similar)
# sudo rules configured via IPA to allow passwordless sudo
```

### Advantages

- Centralized user management
- Single account for all inner layer VMs
- Automatic propagation when VMs join domain
- Easy credential rotation via IPA

### Limitations

- **Requires IPA to be online**
- If IPA fails, this account is unavailable
- Cannot be used for outer layer infrastructure (IPA itself, pfSense, etc.)

================================================================================
3. EMERGENCY ACCOUNTS (DR SCENARIOS)
================================================================================

## veeam_emergency - Inner Layer VMs

**Account Type:** Local user on each VM
**Purpose:** Backup access when domain (IPA) is unavailable
**Authentication:** SSH key (no password)
**Key Storage:** Encrypted in HashiCorp Vault

### Key Location in Vault

```
Path: secret/data/infra/veeam_emergency
Fields:
  - private_key: <SSH private key>
  - public_key: <SSH public key>
```

### Configuration

**SSH Key Setup:**
- SSH key pair generated and stored in Vault
- Private key: Used by Veeam server to connect
- Public key: Deployed to ~/.ssh/authorized_keys on each VM
- Encryption: Keys stored encrypted in Vault database

**Sudo Configuration:**
```bash
# /etc/sudoers.d/veeam_emergency
veeam_emergency ALL=(ALL) NOPASSWD: ALL
```

**SSH Configuration:**
- Key-based authentication only (no password)
- Restricted to Veeam server subnet (optional via authorized_keys restrictions)

### Systems with veeam_emergency (Inner Layer)

1. K8s Master
2. K8s Worker-1, K8s Worker-2, K8s Worker-3
3. Vault-01, Vault-02, Vault-03
4. Ansible
5. Jenkins
6. Monitor

### Deployment

Automated via Ansible playbook:
```
Path: /03-AUTOMATION/ansible-playbooks/os-services/01-emergency-user.yml
```

**Playbook Actions:**
1. Creates veeam_emergency user on each VM
2. Retrieves SSH public key from Vault
3. Deploys public key to ~/.ssh/authorized_keys
4. Configures passwordless sudo
5. Sets appropriate file permissions

**Running the Playbook:**
```bash
cd /03-AUTOMATION/ansible-playbooks/os-services
ansible-playbook 01-emergency-user.yml
```

## veeam_emergency - Outer Layer Infrastructure

**Account Type:** Local user (password-based)
**Purpose:** Backup access for outer layer infrastructure VMs
**Authentication:** PASSWORD (not SSH key)

### Why Password Instead of SSH Key?

**Rationale:** Avoid dependency on Inner Veeam for outer layer access
- Inner Veeam VM contains SSH private key
- If Inner Veeam is down, SSH key is unavailable
- Outer layer needs to be backed up independently
- Password avoids circular dependency

### Systems with veeam_emergency (Outer Layer)

1. ESXi Master (10.0.20.100)
2. ESXi Production (10.0.20.101)
3. ESXi DR (10.0.20.102)
4. vCenter (10.0.20.89)
5. NAS Storage
6. pfSense
7. IPA (10.0.20.89)

### Configuration

**User Creation:**
```bash
# Script reference: /03-AUTOMATION/scripts/create-emergency-user.sh
# Creates user with password authentication
# Configures sudo with password requirement (or passwordless if desired)
```

**Password Storage:** Secure location on Windows Host (encrypted)

### Sudo Configuration

```bash
# /etc/sudoers.d/veeam_emergency
# Option 1: Password required for sudo
veeam_emergency ALL=(ALL) ALL

# Option 2: Passwordless sudo (if preferred)
veeam_emergency ALL=(ALL) NOPASSWD: ALL
```

================================================================================
4. CREDENTIAL STORAGE & SECURITY
================================================================================

## Vault Storage (Inner Layer SSH Keys)

**Path:** secret/data/infra/veeam_emergency

**Security:**
- Vault database encrypted at rest
- Access controlled via Vault policies
- Keys only accessible to authorized services
- Audit logging enabled for all access

**Retrieval:**
```bash
# From Ansible playbook or manual
vault kv get secret/infra/veeam_emergency
```

## Veeam Server Storage

**Windows Encrypted Credentials:**
```
Path: C:\Scripts\InnerWindowsCreds.xml
Path: C:\Scripts\vCenterCreds.xml
```

**Encryption:** Windows Data Protection API (DPAPI)
- Tied to user account on local machine
- Cannot be decrypted on different machine or by different user
- Safe to store in file system (user-scoped encryption)

## Password Storage (Outer Layer)

**Location:** Windows Host secure storage
**Protection:** Encrypted using Windows mechanisms
**Access:** Only from Windows Host for Inner Veeam operations

================================================================================
5. ANSIBLE AUTOMATION
================================================================================

## Emergency User Deployment Playbook

**Location:** `/03-AUTOMATION/ansible-playbooks/os-services/01-emergency-user.yml`

**Purpose:**
- Automates veeam_emergency user creation on all inner layer VMs
- Retrieves SSH keys from Vault
- Deploys SSH public key
- Configures sudo permissions

**Prerequisites:**
1. Vault server online and accessible
2. SSH keys already generated and stored in Vault
3. Ansible can connect to target VMs (using initial credentials)

**Playbook Structure:**
```yaml
---
- name: Deploy Veeam Emergency User
  hosts: inner_layer_vms
  tasks:
    - name: Create veeam_emergency user
    - name: Fetch SSH public key from Vault
    - name: Deploy SSH authorized_keys
    - name: Configure passwordless sudo
    - name: Set file permissions
```

## Manual Script for Outer Layer

**Location:** `/03-AUTOMATION/scripts/create-emergency-user.sh`

**Purpose:**
- Creates veeam_emergency user with password on outer layer VMs
- Configures sudo
- Manual execution (one VM at a time)

**Usage:**
```bash
# SSH to outer layer VM
ssh root@10.0.20.100

# Run script
/03-AUTOMATION/scripts/create-emergency-user.sh

# Enter password when prompted
```

================================================================================
SECURITY CONSIDERATIONS
================================================================================

## Principle of Least Privilege

**Domain User (veeam@home.lab):**
- Only has access to inner layer VMs
- Relies on IPA for centralized access control
- Can be disabled centrally if compromised

**Emergency User (veeam_emergency):**
- Local user on each system (harder to disable centrally)
- Should only be used when domain is unavailable
- Regularly verify SSH key access is still needed

## Key Rotation

**SSH Keys (Inner Layer):**
1. Generate new SSH key pair
2. Update Vault: `vault kv put secret/infra/veeam_emergency private_key=@new_key public_key=@new_key.pub`
3. Re-run Ansible playbook: `ansible-playbook 01-emergency-user.yml`
4. Verify new key works
5. Remove old private key from Veeam server

**Passwords (Outer Layer):**
1. Update password on each outer layer VM
2. Update password storage on Windows Host
3. Test backup job with new password

## Audit & Monitoring

- Monitor sudo usage for veeam_emergency account
- Alert on unexpected authentication attempts
- Review Vault audit logs for key access
- Periodically verify emergency user is still required

================================================================================
TROUBLESHOOTING
================================================================================

## Domain User Not Working

**Symptom:** veeam@home.lab cannot connect to VMs

**Checks:**
1. Is IPA server online? `ping 10.0.20.89`
2. Can VM reach IPA? `getent passwd veeam@home.lab`
3. Is user in correct groups? Check IPA web UI
4. Are sudo rules configured? `sudo -l -U veeam@home.lab`

**Solution:** If IPA is down, use veeam_emergency instead

## Emergency User SSH Key Not Working

**Symptom:** veeam_emergency SSH key authentication fails

**Checks:**
1. Is private key on Veeam server correct?
2. Is public key in ~/.ssh/authorized_keys on VM?
3. File permissions: `~/.ssh` (700), `authorized_keys` (600)
4. SELinux context: `restorecon -R ~/.ssh`

**Solution:**
```bash
# On VM
cat ~/.ssh/authorized_keys
# Verify public key is present

# From Veeam server
ssh -i /path/to/private_key veeam_emergency@<VM_IP>
```

## Emergency User Password Not Working (Outer Layer)

**Symptom:** veeam_emergency password fails on outer layer VM

**Checks:**
1. Is password correct in Windows Host storage?
2. Has password expired on VM?
3. Is account locked?

**Solution:**
```bash
# Reset password on VM
passwd veeam_emergency

# Update password in Windows Host storage
```

================================================================================
RELATED DOCUMENTATION
================================================================================

- [01-Backup-Strategy.md](../Backup-DR/01-Backup-Strategy.md) - How these accounts are used in backups
- [03-Recovery-Procedures.md](../Backup-DR/03-Recovery-Procedures.md) - When to use domain vs emergency user
- [04-Design-Decisions.md](../Backup-DR/04-Design-Decisions.md) - Why this authentication strategy?
- [05-Configuration-Reference.md](../Backup-DR/05-Configuration-Reference.md) - User accounts summary table

Back to: [README.md](README.md)
