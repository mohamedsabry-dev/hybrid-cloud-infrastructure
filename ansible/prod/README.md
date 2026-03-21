# Ansible PROD Environment

This directory contains Ansible configuration for the PROD environment infrastructure.

---

## Directory Structure

```
ansible/prod/
├── ansible.cfg                 # Ansible configuration
├── README.md                   # This file
├── operation_guide.txt         # Day-to-day operations guide
├── inventory/
│   ├── inventory.ini           # Main inventory (FQDN, FreeIPA DNS)
│   ├── first_setup_inventory.ini  # Bootstrap inventory (IP-based, root)
│   └── group_vars/
│       ├── all.yml             # Variables for all hosts
│       ├── freeipa.yml         # FreeIPA server/domain config
│       ├── vault_cluster.yml   # HashiCorp Vault cluster config
│       ├── k8s_masters.yml     # K8s master nodes (reserved)
│       ├── k8s_workers.yml     # K8s worker nodes (reserved)
│       ├── ansible.yml         # Ansible control node (reserved)
│       ├── local_runner.yml    # CI/CD runners (reserved)
│       └── nginx.yml           # Nginx proxy (reserved)
└── playbooks/
    ├── ansible/                # Ansible node setup
    │   ├── README.md
    │   ├── ansible_setup.yml
    │   ├── test.yml
    │   └── templates/
    │       └── requirements.yml
    ├── common/                 # Cross-platform tasks
    │   ├── README.md
    │   ├── pre_setup.yml       # Combined: mirror fix + SSH auth + packages
    │   ├── ntp.yml
    │   ├── setup_breakglass.yml  # TODO
    │   └── templates/
    ├── freeipa/                # Identity management
    │   ├── README.md
    │   ├── freeipa_setup.yml
    │   ├── domain_config.yml
    │   ├── add_hosts_to_ipa.yml
    │   └── fix_lxc_krb5_keyring.yml
    ├── vault/                  # HashiCorp Vault
    │   ├── README.md           # Includes decision log
    │   ├── vault_setup.yml
    │   ├── vault_config.yml    # TODO
    │   └── templates/
    └── local-runner/           # CI/CD runners
        ├── README.md
        └── setup_tools.yml
```

---

## Inventory Files

### Two-Phase Approach

We use two inventory files for different stages of infrastructure lifecycle:

| File | Phase | User | Resolution | Use Case |
|------|-------|------|------------|----------|
| `first_setup_inventory.ini` | Bootstrap | root | IP addresses | Before FreeIPA exists |
| `inventory.ini` | Production | super_bot | FQDN hostnames | After FreeIPA configured |

### Why Two Inventories?

**first_setup_inventory.ini (Bootstrap)**
- Uses IP addresses because FreeIPA DNS doesn't exist yet
- Uses root user because domain users (super_bot) don't exist yet
- SSH keys pre-copied during Terraform provisioning
- Usage: `ansible-playbook -i inventory/first_setup_inventory.ini playbooks/...`

**inventory.ini (Production)**
- Uses FQDN hostnames because FreeIPA provides DNS
- Uses super_bot domain user with HBAC rules and sudo
- Kerberos/GSSAPI authentication requires hostnames (not IPs)
- Requires `kinit super_bot` before running Ansible
- Usage: `ansible-playbook playbooks/...` (default from ansible.cfg)

### Special Cases

**FreeIPA Server uses root, not super_bot**
- FreeIPA is the identity provider, not a client
- SSSD/sudo rules don't apply to the IPA server itself
- Avoids dependency loop (can't use IPA auth to manage IPA)

**Ansible Group is local connection**
- Ansible node runs playbooks locally
- Uses `ansible_connection=local`
- No SSH needed for self-management

### Host Groups

| Group | Type | VLAN | Purpose |
|-------|------|------|---------|
| `freeipa` | VM | 50 | Identity/DNS server |
| `k8s_masters` | VM | 51 | Kubernetes control plane |
| `k8s_workers` | VM | 54 | Kubernetes worker nodes |
| `vault_cluster` | LXC | 52 | HashiCorp Vault HA cluster |
| `ansible` | LXC | 53 | Ansible control node |
| `local_runners` | LXC | 53 | GitHub Actions runners |
| `nginx` | LXC | 55 | Reverse proxy |

**Meta Groups:**
- `k8s` - All Kubernetes nodes (masters + workers)
- `managed_hosts` - All hosts managed by super_bot (excludes freeipa)
- `vms` - All virtual machines
- `lxc` - All LXC containers

---

## Group Variables

### all.yml
Variables applied to all hosts:
- `initial_packages` - Base packages installed on all nodes
- `ipaclient_*` - FreeIPA client enrollment settings
- `ipaadmin_principal/password` - FreeIPA admin credentials (vault encrypted)
- `ipa_managed_hosts` - List of all hosts for FreeIPA host groups
- `k8s_api_vip` - Kubernetes API virtual IP (reserved)

### freeipa.yml
FreeIPA server and domain configuration:
- `ipa_host_groups` - Logical host groupings for HBAC/sudo rules
- `domain_bot_users` - Automation service accounts (super_bot)
- `ipa_admin_users` - Human admin accounts per service
- `default_*_password` - Default passwords (vault encrypted)
- `hashicorp_vault_users` - Users for Vault UI/API access

### vault_cluster.yml
HashiCorp Vault cluster settings:
- `vault_aws_access_key_id` - AWS KMS access key for auto-unseal
- `vault_aws_secret_access_key` - AWS KMS secret key for auto-unseal

**Two approaches available:**
1. Environment lookup (active) - Used by GitHub workflows
2. Ansible Vault encrypted (commented) - For manual/local testing

---

## Ansible Vault Encrypted Values

We use Ansible Vault (not HashiCorp Vault) for encrypting sensitive values at this stage because HashiCorp Vault isn't deployed yet during initial infrastructure setup.

### Encrypted Variables Summary

| Variable | File | Purpose |
|----------|------|---------|
| `ipaadmin_password` | all.yml | FreeIPA admin password |
| `default_admin_user_password` | freeipa.yml | Default password for admin users |
| `default_bot_user_password` | freeipa.yml | Default password for bot users |
| `vault_aws_access_key_id` | vault_cluster.yml | AWS KMS key (commented, backup) |
| `vault_aws_secret_access_key` | vault_cluster.yml | AWS KMS secret (commented, backup) |

### Vault Password Setup

The vault password file location is configured in `ansible.cfg`:
```ini
vault_password_file = ~/.ansible_vault
```

**Create the password file on ansible node:**
```bash
echo 'YOUR_VAULT_PASSWORD' > ~/.ansible_vault
chmod 600 ~/.ansible_vault
```

### Common Commands

**Encrypt a new value:**
```bash
ansible-vault encrypt_string 'SECRET_VALUE' --name 'variable_name'
```

**View encrypted value:**
```bash
ansible localhost -m debug -a "var=ipaadmin_password" -e @inventory/group_vars/all.yml
```

**Edit encrypted file:**
```bash
ansible-vault edit inventory/group_vars/all.yml
```

**Re-encrypt with new password:**
```bash
ansible-vault rekey inventory/group_vars/all.yml
```

---

## Day-to-Day Operations

### Running Playbooks

**With FreeIPA (normal operation):**
```bash
# Get Kerberos ticket first
kinit super_bot

# Run playbook (uses default inventory)
ansible-playbook playbooks/freeipa/domain_config.yml

# Target specific hosts
ansible-playbook playbooks/common/ntp.yml --limit vault_cluster
```

**Before FreeIPA (bootstrap):**
```bash
# Use first_setup inventory with root
ansible-playbook -i inventory/first_setup_inventory.ini playbooks/freeipa/freeipa_setup.yml
```

### Testing Connectivity

```bash
# Test all managed hosts
kinit super_bot
ansible managed_hosts -m ping

# Test specific group
ansible vault_cluster -m command -a "hostname"

# Test FreeIPA server (uses root)
ansible freeipa -m ping
```

### Common Tasks

**Clear SSH known_hosts after recreating nodes:**
```bash
for ip in 10.0.50.10 10.0.51.10 10.0.51.11 10.0.51.12 10.0.52.10 10.0.52.11 10.0.52.12 10.0.53.10 10.0.53.20 10.0.54.10 10.0.54.11 10.0.54.12 10.0.55.10; do
  ssh-keygen -R "$ip" 2>/dev/null
done
```

**Check Ansible config:**
```bash
ansible --version  # Shows config file path
ansible-config dump --only-changed
```

---

## Configuration Decisions

### NTP Disabled for FreeIPA Client

NTP configuration via `ipaclient_configure_ntp` is disabled because:
- VMs: Chronyd works normally
- LXC containers: Chronyd fails - containers share kernel time with Proxmox host

Settings in `all.yml`:
```yaml
ipaclient_configure_ntp: false
ipaclient_no_ntp: true
```

NTP is configured separately via `playbooks/common/ntp.yml` with different templates for VMs vs LXC.

### FreeIPA UID Range

FreeIPA configured with custom UID range (60001-65500) to fit within LXC unprivileged container UID mapping:
- Must be > UID_MAX (60000) from /etc/login.defs
- Must be < 65536 for unprivileged LXC container compatibility
- See /troubleshooting/linux/21-lxc-uid-mapping-initgroups-error.md for full explanation

### Credential Approaches

**vault_cluster.yml** supports two credential approaches:
1. **Environment lookup** (active) - Credentials from AWS Secrets Manager via workflow
2. **Ansible Vault** (commented) - Encrypted in file for manual testing

This allows flexibility between CI/CD and local development.

### Playbook Consolidation

**common/pre_setup.yml** combines three small playbooks into one:
1. Mirror fix (required due to old Rocky Linux repo issues)
2. SSH password auth (cloud-init overrides this during TF template creation)
3. Initial packages (vim, git, curl, htop, unzip)

**Decision:** Single playbook is cleaner for initial node setup workflow.

---

## Playbooks Documentation

Each playbook folder has its own README.md with specific documentation:

| Folder | README Contents |
|--------|----------------|
| `playbooks/ansible/` | Collections installed, test playbook usage |
| `playbooks/common/` | Pre-setup details, NTP configuration, LXC notes |
| `playbooks/freeipa/` | Deployment order, playbook details, troubleshooting refs |
| `playbooks/vault/` | Decision log, architectural principles, setup steps |
| `playbooks/local-runner/` | Tools installed, workflow integration |

---

## Related Documentation

- **operation_guide.txt** - Day-to-day operations, keytab setup, git workflow
- **ansible.cfg** - Ansible configuration settings (with detailed comments)
- **/troubleshooting/** - Troubleshooting cases (identity, linux, vault, etc.)
- **.github/workflows/** - GitHub Actions workflows that run these playbooks

---

## Network Reference

| VLAN | Subnet | Purpose |
|------|--------|---------|
| 50 | 10.0.50.0/24 | FreeIPA/Identity |
| 51 | 10.0.51.0/24 | K8s Masters |
| 52 | 10.0.52.0/24 | Vault Cluster |
| 53 | 10.0.53.0/24 | Ansible/Runners |
| 54 | 10.0.54.0/24 | K8s Workers |
| 55 | 10.0.55.0/24 | Nginx/Proxy |
