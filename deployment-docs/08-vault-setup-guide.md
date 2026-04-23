# HashiCorp Vault HA Cluster - Initial Setup Guide (DEV)

Note: If you face issues during deployment, check the troubleshooting/ folder
for the related technology section. Most common issues have been documented there.
Relevant folders: troubleshooting/vault/, troubleshooting/identity/

---

## Overview

This guide covers the complete setup of a 3-node HashiCorp Vault HA cluster running on Proxmox LXC containers, integrated with FreeIPA for domain trust and AWS KMS for auto-unseal.

---

## Prerequisites

Before starting Vault deployment:

### AWS Secrets Manager (CRITICAL)

All GitHub workflows depend on secrets stored in AWS Secrets Manager.
These must be created and populated BEFORE any infrastructure deployment.

See: aws-secrets-setup-guide.txt

Required secrets for Vault:
- dev/proxmox/terraform-token
- dev/ansible/ssh-public-key
- dev/golden-image/lxc-root-password
- dev/super_bot/keytab
- dev/vault/unseal-credentials (created by KMS workflow)

### Other Prerequisites

1. FreeIPA must be running and functional (see freeipa-initial-setup-guide.txt)
2. super_bot keytab must exist in AWS Secrets Manager (dev/super_bot/keytab)
3. AWS KMS must be deployed first (Phase 4 can be done before Phase 1-3)

---

## Phase 1: Golden LXC Template Creation

### 1.1 Deploy Base LXC Container

Terraform Path: terraform/dev/proxmox/lxc/golden-template/

GitHub Workflow: .github/workflows/dev-golden-full-setup.yml

Note: The LXC job has its own gate lock (DEV_INFRA_GOLDEN_LXC_LOCK) to prevent accidental re-runs.

### 1.2 Bootstrap the Golden Image

After Terraform completes, run the bootstrap script inside the LXC:

Script Path: proxmox/golden_templates/golden_lxc_setup.sh

  # SSH into the container and run:
  ./golden_lxc_setup.sh

### 1.3 Create Template Image

1. Shutdown the container
2. Copy to a new CT ID
3. Convert to template
4. Save to NAS storage for reuse

---

## Phase 2: Deploy Vault Cluster Infrastructure

### 2.1 Deploy 3 Vault LXC Containers

Terraform Path: terraform/dev/proxmox/lxc/vault_cluster/

GitHub Workflow: .github/workflows/dev-vault-full-setup.yml

Gate Lock: DEV_INFRA_VAULT_CLUSTER_LOCK - Set to 'false' to allow deployment

The workflow Job 1 (deploy-lxc) creates 3 LXC containers for Vault HA.

---

## Phase 3: FreeIPA Domain Integration

Run the following Ansible playbooks IN SEQUENCE after Vault LXCs are deployed and FreeIPA is functional:

Playbook Directory: ansible/dev/playbooks/freeipa/

  cd ansible/dev/

  # Step 1: Register hosts in FreeIPA
  ansible-playbook -i inventory/inventory.ini playbooks/freeipa/add_hosts_to_ipa.yml

  # Step 2: Configure domain settings
  ansible-playbook -i inventory/inventory.ini playbooks/freeipa/domain_config.yml

  # Step 3: Fix LXC Kerberos keyring issue
  ansible-playbook -i inventory/inventory.ini playbooks/freeipa/fix_lxc_krb5_keyring.yml

  # Step 4: Add DNS records
  ansible-playbook -i inventory/inventory.ini playbooks/freeipa/add_dns_records.yml

For more details on each playbook, see: ansible/dev/playbooks/freeipa/README.md

### 3.1 Manual: Generate and Store Keytab

After domain integration:

1. Generate keytab for 'super_bot' service account on FreeIPA
2. Base64 encode and store in AWS Secrets Manager: dev/super_bot/keytab

---

## Phase 4: AWS KMS Setup for Auto-Unseal

### 4.1 Deploy KMS Key and IAM Policies

Terraform Path: terraform/dev/aws/kms-vault-unseal/

GitHub Workflow: .github/workflows/dev-aws-kms-vault-unseal.yml

Important: Must merge to 'env-security' branch to have 'assume role fullAdmin' permissions for deployment.

This creates:
- KMS key for Vault auto-unseal (alias: vault-unseal, region: us-east-1)
- IAM user with encrypt/decrypt permissions only
- Access credentials stored in Secrets Manager: dev/vault/unseal-credentials

---

## Phase 5: Vault Service Installation

### 5.1 Run Vault Setup Workflow

GitHub Workflow: .github/workflows/dev-vault-full-setup.yml

Gate Lock: DEV_SVC_VAULT_SETUP - Set to 'false' to allow setup

Job 2 (setup) performs:

1. Pre-setup playbook - Base configuration for vault nodes
   playbooks/common/pre_setup.yml --limit vault_cluster

2. NTP configuration
   playbooks/common/ntp.yml --limit vault_cluster

3. Vault installation and configuration
   playbooks/vault/vault_setup.yml

### 5.2 What vault_setup.yml Does

This playbook performs the following:
- Creates FreeIPA service principals for Vault nodes and VIP
- Creates vault-admins group and admin users in FreeIPA
- Installs Vault from HashiCorp repository
- Requests FreeIPA-signed TLS certificates via certmonger
- Deploys vault.hcl config (Raft storage, KMS auto-unseal, TLS)
- Deploys AWS credentials for KMS (/etc/vault.d/vault.env)
- Sets shell environment variables (/etc/profile.d/vault.sh)
- Adds /etc/hosts entries for cluster nodes
- Starts and enables Vault service

For more details, see: ansible/dev/playbooks/vault/README.md

### 5.3 Configuration Details

Vault configuration highlights:
- Storage: Raft with retry_join to all 3 nodes
- Auto-unseal: AWS KMS (alias/vault-unseal)
- TLS: FreeIPA-signed certificates with VIP SAN
- UI: Enabled at https://vault.lab.local:8200
- disable_mlock: true (required for LXC containers)

---

## Phase 6: Vault VIP Setup (High Availability)

### 6.1 Configure Keepalived for VIP

Playbook: ansible/dev/playbooks/vault/vault_vip.yml

This playbook sets up Keepalived for a Virtual IP (VIP) that floats between Vault nodes:

  - VIP Address: 10.0.62.100 (vault.lab.local)
  - Priority: vault1 (101) > vault2 (100) > vault3 (99)

  cd ansible/dev/

  ansible-playbook -i inventory/inventory.ini playbooks/vault/vault_vip.yml

For more details, see: ansible/dev/playbooks/vault/README.md

### 6.2 DNS Configuration

Ensure FreeIPA DNS has an A record:
- vault.lab.local -> 10.0.62.100 (VIP)

This allows clients to connect to the active Vault node via the VIP.

---

## Phase 7: Vault Initialization (Manual)

### 7.1 Initialize Vault

SSH to the primary Vault node:

  ssh root@vault1.lab.local

  export VAULT_ADDR="https://vault1.lab.local:8200"
  export VAULT_CACERT="/etc/ipa/ca.crt"

  vault operator init

Note: With KMS auto-unseal configured, Vault automatically generates recovery keys
instead of unseal keys. The output contains:
- 5 Recovery Keys (for recovery operations, NOT for daily unsealing - KMS handles that)
- 1 Root Token

### 7.2 Save Keys to AWS Secrets Manager

Manually store the initialization output in AWS Secrets Manager:
- Secret: dev/vault/init-keys

IMPORTANT: Save the recovery keys securely. They are needed for recovery operations
like migrating to a different KMS key or disaster recovery.

---

## Phase 8: Vault Basic Configuration

### 8.1 Run Configuration Playbook

Playbook: ansible/dev/playbooks/vault/vault_config.yml

  cd ansible/dev/

  ansible-playbook -i inventory/inventory.ini playbooks/vault/vault_config.yml \
    -e "vault_root_token=hvs.xxxxx"

This playbook configures:
- Audit logging, LDAP auth (FreeIPA), policies, group mappings, emergency user

For more details, see: ansible/dev/playbooks/vault/README.md

### 8.2 Verify Access

Test LDAP login with a domain admin user:

  vault login -method=ldap username=<your-domain-user>

Test emergency user:

  vault login -method=userpass username=vault-emergency

Access Web UI:

  URL: https://vault.lab.local
  Login: LDAP or userpass method

### 8.3 Revoke Root Token

After confirming all authentication methods work:

  vault token revoke <root-token>

---

## Summary - File Reference

| Component              | Path                                            |
|------------------------|-------------------------------------------------|
| Golden Template TF     | terraform/dev/proxmox/lxc/golden-template/      |
| Vault Cluster TF       | terraform/dev/proxmox/lxc/vault_cluster/        |
| KMS Unseal TF          | terraform/dev/aws/kms-vault-unseal/             |
| Golden Setup Workflow  | .github/workflows/dev-golden-full-setup.yml     |
| Vault Setup Workflow   | .github/workflows/dev-vault-full-setup.yml      |
| KMS Workflow           | .github/workflows/dev-aws-kms-vault-unseal.yml  |
| FreeIPA Playbooks      | ansible/dev/playbooks/freeipa/                  |
| Vault Playbooks        | ansible/dev/playbooks/vault/                    |
| Vault Setup Playbook   | ansible/dev/playbooks/vault/vault_setup.yml     |
| Vault VIP Playbook     | ansible/dev/playbooks/vault/vault_vip.yml       |
| Vault Config Playbook  | ansible/dev/playbooks/vault/vault_config.yml    |
| Vault Group Vars       | ansible/dev/inventory/group_vars/vault_cluster.yml |

---

## AWS Secrets Reference

| Secret                             | Purpose                          |
|------------------------------------|----------------------------------|
| dev/proxmox/terraform-token        | Proxmox API credentials          |
| dev/ansible/ssh-public-key         | SSH key for LXC access           |
| dev/golden-image/lxc-root-password | LXC root password                |
| dev/super_bot/keytab               | Kerberos keytab (base64)         |
| dev/vault/unseal-credentials       | KMS unseal IAM credentials       |
| dev/vault/init-keys                | Vault init output (manual)       |
| dev/freeipa/admin-password         | FreeIPA admin (used by setup)    |

---

## Ansible Vault Encrypted Variables

Location: ansible/dev/inventory/group_vars/vault_cluster.yml

| Variable                     | Purpose                              |
|------------------------------|--------------------------------------|
| vault_aws_access_key_id      | KMS credentials (env lookup or encrypted) |
| vault_aws_secret_access_key  | KMS credentials (env lookup or encrypted) |
| ldap_bindpass                | LDAP bind password for Vault config  |
| emergency_password           | Emergency user password              |
| vault_keepalived_auth_pass   | Keepalived authentication password   |

Note: Decrypt with ansible-vault or use vault password file configured in ansible.cfg

---
