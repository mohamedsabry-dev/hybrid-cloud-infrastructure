# FreeIPA Server - Initial Setup Guide (DEV)

Note: If you face issues during deployment, check the troubleshooting/ folder
for the related technology section. Most common issues have been documented there.
Relevant folder: troubleshooting/identity/

---

## Overview

This guide covers the setup of FreeIPA as the identity management and DNS server
for the lab environment. FreeIPA provides Kerberos authentication, LDAP directory,
and DNS services for all infrastructure nodes.

IMPORTANT: FreeIPA is the FIRST service to deploy. All other services (Vault, K8s)
depend on FreeIPA for domain trust and DNS resolution.

### Why FreeIPA comes first

Everything else I deploy depends on identity and DNS being in place before it
can come up. FreeIPA is the foundation — once it is running, every other
service plugs into it:

  - DNS for lab.local. Every host is addressed as <name>.lab.local, plus the
    service VIPs (vault.lab.local, k8s.lab.local). Without FreeIPA's DNS I
    would be stitching /etc/hosts files across the fleet by hand.

  - Kerberos realm LAB.LOCAL. This is the auth layer super_bot uses to run
    Ansible passwordlessly against domain-joined hosts. No Kerberos = back
    to SSH-key juggling for every node.

  - LDAP directory with HBAC and sudo rules. Defines who can SSH where and
    what they can run. Replaces a mess of per-host /etc/sudoers files.

  - Service principals and certificates. Vault pulls its TLS certs from
    FreeIPA via ipa-getcert (automatic renewal, no manual cert management).

If I deployed Vault before FreeIPA I would have to manually issue and rotate
Vault's TLS certs. If I deployed Kubernetes before FreeIPA I would have no
DNS for the API VIP and no clean keytab path for Flux automation. So the
order is forced from below: identity first, then everything that leans on
identity.

The only things that come before FreeIPA are the AWS Secrets (because the
FreeIPA workflow reads the admin/DM passwords from there) and the Ansible +
Local Runner pair (because something has to actually run the FreeIPA
playbook against the new VM — see ansible-runner-setup-guide.txt for that
reasoning).

---

## Network Layout

| VLAN | Subnet     | Purpose              | Hosts                    |
|------|------------|----------------------|--------------------------|
| 60   | 10.0.60.x  | FreeIPA              | freeipa (10.0.60.10)     |
| 61   | 10.0.61.x  | K8s Masters          | k8s-master1/2/3          |
| 62   | 10.0.62.x  | Vault Cluster (LXC)  | vault1/2/3               |
| 63   | 10.0.63.x  | Ansible/Runners (LXC)| ansible, local-runner    |
| 64   | 10.0.64.x  | K8s Workers          | k8s-worker1/2/3          |
| 65   | 10.0.65.x  | Nginx (LXC)          | ex-nginx                 |

---

## Prerequisites

### AWS Secrets Manager (CRITICAL)

All GitHub workflows depend on secrets stored in AWS Secrets Manager.
These must be created and populated BEFORE any infrastructure deployment.

See: aws-secrets-setup-guide.txt

Required secrets for FreeIPA:
- dev/proxmox/terraform-token
- dev/ansible/ssh-public-key
- dev/golden-image/vm-root-password
- dev/freeipa/admin-password
- dev/freeipa/dm-password

### Ansible & Local Runner (CRITICAL)

Ansible LXC and Local Runner must be deployed BEFORE FreeIPA.
All workflows depend on these nodes for playbook execution.

See: ansible-runner-setup-guide.txt

### Golden VM Template

Before deploying FreeIPA, ensure the golden VM template exists:

Terraform Path: terraform/dev/proxmox/vms/golden-image/
Bootstrap Script: proxmox/golden_templates/golden-vm-setup.sh
GitHub Workflow: .github/workflows/dev-golden-full-setup.yml

IMPORTANT: The golden image/template scripts include FreeIPA client installation
(ipa-client) on ALL nodes. This is required for domain joining later.

### First Setup Inventory

Before FreeIPA exists, there is no Kerberos authentication available.
Initial deployments use SSH key-based authentication:

Inventory File: ansible/dev/inventory/first_setup_inventory.ini

This inventory:
- Uses IP addresses (no DNS yet)
- Uses root user (no domain users yet)
- Uses SSH key authentication (injected via Terraform/cloud-init)
- SSH key fetched from AWS Secrets Manager: dev/ansible/ssh-public-key

### NTP Synchronization

Kerberos is time-sensitive. Ensure NTP is configured before FreeIPA setup.
Time skew > 5 minutes will cause authentication failures.

---

## Phase 1: Deploy FreeIPA Infrastructure

### 1.1 Deploy FreeIPA VM

Terraform Path: terraform/dev/proxmox/vms/freeipa/

GitHub Workflow: .github/workflows/dev-freeipa-full-setup.yml

Gate Lock: DEV_INFRA_FREEIPA_LOCK - Set to 'false' to allow deployment

Job 1 (deploy-vm) creates the FreeIPA VM from the golden image.

FreeIPA IP: 10.0.60.10

---

## Phase 2: Install FreeIPA Server

### 2.1 Run FreeIPA Setup

Gate Lock: DEV_SVC_FREEIPA_SETUP - Set to 'false' to allow setup

IMPORTANT: Both locks (INFRA and SVC) can be opened at the same time to run
the full deployment in one workflow execution.

Job 2 (install-freeipa) runs the setup playbook:

Playbook: ansible/dev/playbooks/freeipa/freeipa_setup.yml

  cd ansible/dev/

  # Note: Uses first_setup_inventory.ini (SSH key auth, no Kerberos yet)
  ansible-playbook -i inventory/first_setup_inventory.ini playbooks/freeipa/freeipa_setup.yml

### 2.2 What freeipa_setup.yml Does

- Uninstalls any existing IPA client (pre_task to avoid conflicts)
- Disables cloud-init /etc/hosts management
- Fixes /etc/hosts entries for proper FQDN resolution
- Installs FreeIPA server with DNS using ansible_freeipa role
- Configures DNS forwarders (8.8.8.8, 1.1.1.1)
- Enables DNS recursion for internal networks (10.0.0.0/8)

For more details, see: ansible/dev/playbooks/freeipa/README.md

### 2.3 FreeIPA Configuration

| Setting      | Value                                    |
|--------------|------------------------------------------|
| Domain       | lab.local                                |
| Realm        | LAB.LOCAL                                |
| Hostname     | freeipa.lab.local                        |
| IP Address   | 10.0.60.10                               |
| ID Range     | 60001-65500 (fits LXC unprivileged UID)  |
| DNS          | Enabled with forwarders                  |

### 2.4 Required Secrets

The workflow fetches these from AWS Secrets Manager:
- dev/freeipa/admin-password - IPA admin user password
- dev/freeipa/dm-password - Directory Manager (LDAP bind) password

---

## Phase 3: Post-Installation Verification

### 3.1 Access FreeIPA Web UI

After installation, access the web UI:

  URL: https://freeipa.lab.local
  Username: admin
  Password: <from AWS Secrets Manager: dev/freeipa/admin-password>

### 3.2 Verify Services

SSH to FreeIPA server:

  ssh root@10.0.60.10

  # Check IPA services
  ipactl status

  # Check DNS
  dig @localhost freeipa.lab.local

  # Check Kerberos
  kinit admin
  klist

### 3.3 FreeIPA Management Access

IMPORTANT: FreeIPA is managed using ROOT access only.
The super_bot service account is NOT authorized to manage FreeIPA itself.

### Why I manage FreeIPA as root, not super_bot

FreeIPA is the identity provider, not one of its own clients. It does not
enroll itself into the realm it runs — the SSSD, HBAC, and sudo rules I set
up for super_bot apply to FreeIPA clients, not to the FreeIPA server itself.

If I managed FreeIPA using its own auth layer (super_bot + Kerberos), I would
create a dependency loop: the moment FreeIPA breaks, the tool I need to fix
it is also broken. That is the worst kind of outage — you stare at the
machine that runs identity, with no way in because identity is down.

So I kept the FreeIPA VM deliberately outside its own trust domain. Even in
the main inventory.ini, the [freeipa] group is pinned to ansible_user=root
(and the first_setup_inventory.ini already uses root everywhere). This way
I always have a break-glass path to reach and repair the server, regardless
of what state the directory or Kerberos is in.

Same philosophy as why I kept first_setup_inventory.ini around as a fallback:
never let a service be managed only by the thing it provides.

For FreeIPA admin tasks, use:
- Web UI with admin credentials
- SSH to freeipa node as root
- kinit admin (then use ipa commands)

---

## Phase 4: Domain Configuration

After FreeIPA is running, configure the domain with users, groups, and policies.

### 4.1 Run Domain Config Playbook

Playbook: ansible/dev/playbooks/freeipa/domain_config.yml

  cd ansible/dev/

  # Still uses first_setup_inventory.ini (domain users don't exist yet)
  ansible-playbook -i inventory/first_setup_inventory.ini playbooks/freeipa/domain_config.yml

### 4.2 What domain_config.yml Does

- Creates host groups for service clusters
- Creates bot users (super_bot) with passwordless sudo
- Creates admin users with sudo (requires password)
- Creates user groups (automation_users, admin_users)
- Sets password policies per group
- Creates HBAC rules for SSH access

For more details, see: ansible/dev/playbooks/freeipa/README.md

### 4.3 Host Groups Created

| Group            | Description              | Hosts                        |
|------------------|--------------------------|------------------------------|
| automation_group | All managed hosts        | All nodes except freeipa     |
| k8s_masters      | K8s control plane        | k8s-master1/2/3.lab.local    |
| k8s_workers      | K8s worker nodes         | k8s-worker1/2/3.lab.local    |
| vault_cluster    | Vault HA cluster         | vault1/2/3.lab.local         |
| ansible_nodes    | Ansible control node     | ansible.lab.local            |
| runner_nodes     | CI/CD runners            | local-runner.lab.local       |
| nginx_nodes      | Nginx reverse proxy      | ex-nginx.lab.local           |

### 4.4 Users Created

**Bot Users (passwordless sudo):**
- super_bot - Automation service account for Ansible

**Admin Users (sudo with password):**
- k8s_admin - Access to k8s_masters, k8s_workers
- vault_admin - Access to vault_cluster
- nginx_admin - Access to nginx_nodes
- ansible_admin - Access to ansible_nodes
- runner_admin - Access to runner_nodes

**Vault UI Users (created for vault_setup.yml):**
- sabry - Vault super admin
- vault_operator - Vault operator

### 4.5 Password Policies

| Group             | Max Lifetime | Priority |
|-------------------|--------------|----------|
| automation_users  | 1460 days (4 years) | 10  |
| admin_users       | 360 days (1 year)   | 20  |

### 4.6 HBAC Rules

SSH access rules are created per user/hostgroup:
- super_bot can SSH to automation_group (all managed hosts)
- k8s_admin can SSH to k8s_masters, k8s_workers
- vault_admin can SSH to vault_cluster
- etc.

---

## Phase 5: Generate super_bot Keytab

After domain_config.yml creates super_bot, generate the keytab for automation.

### 5.1 Generate Keytab

SSH to FreeIPA server:

  ssh root@10.0.60.10

  # Generate keytab for super_bot
  ipa-getkeytab -s freeipa.lab.local -p super_bot@LAB.LOCAL -k /tmp/super_bot.keytab

  # Base64 encode for storage
  base64 /tmp/super_bot.keytab > /tmp/super_bot.keytab.b64

  # Display for copying
  cat /tmp/super_bot.keytab.b64

  # Cleanup
  rm -f /tmp/super_bot.keytab /tmp/super_bot.keytab.b64

### 5.2 Store in AWS Secrets Manager

Upload the base64-encoded keytab to:
- Secret: dev/super_bot/keytab

This keytab is used by GitHub workflows to authenticate as super_bot
for running Ansible playbooks against domain-joined hosts.

---

## Phase 6: Join Other Nodes to Domain

After FreeIPA and domain_config are complete, other nodes can join the domain.

### 6.1 Run Join Playbooks

Playbook Directory: ansible/dev/playbooks/freeipa/

Run these playbooks IN SEQUENCE for each service cluster:

  cd ansible/dev/

  # Step 1: Join hosts to FreeIPA domain
  ansible-playbook -i inventory/first_setup_inventory.ini playbooks/freeipa/add_hosts_to_ipa.yml

  # Step 2: (LXC only) Fix Kerberos keyring issue
  ansible-playbook -i inventory/first_setup_inventory.ini playbooks/freeipa/fix_lxc_krb5_keyring.yml

  # Step 3: Add DNS records for VIPs
  ansible-playbook -i inventory/first_setup_inventory.ini playbooks/freeipa/add_dns_records.yml

### 6.2 What Each Playbook Does

**add_hosts_to_ipa.yml:**
- Sets FQDN hostname on each node
- Fixes /etc/hosts entries
- Adds FreeIPA to /etc/hosts for DNS bootstrap
- Runs ipaclient role to join domain

**fix_lxc_krb5_keyring.yml (LXC only):**
- Fixes Kerberos ccache on unprivileged LXC containers
- Switches from kernel keyring to FILE-based ccache
- Required due to UID mapping in LXC

**add_dns_records.yml:**
- Adds vault.lab.local -> 10.0.62.100 (Vault VIP)
- Adds k8s.lab.local -> 10.0.61.100 (K8s VIP)

For more details, see: ansible/dev/playbooks/freeipa/README.md

---

## Phase 7: Switch to Production Inventory

After nodes are domain-joined, switch to the main inventory with Kerberos auth.

### 7.1 Inventory Comparison

| Aspect          | first_setup_inventory.ini | inventory.ini            |
|-----------------|---------------------------|--------------------------|
| Host format     | IP addresses              | FQDN hostnames           |
| User            | root                      | super_bot                |
| Auth method     | SSH key                   | Kerberos/GSSAPI          |
| When to use     | Before/during IPA setup   | After domain join        |
| FreeIPA host    | root user                 | root user (always)       |

### 7.2 Using Production Inventory

Before running playbooks with inventory.ini, authenticate with Kerberos:

  # On Ansible control node
  kinit super_bot@LAB.LOCAL
  # Enter password (from default_bot_user_password in ansible vault)

  # Verify ticket
  klist

  # Now run playbooks (uses inventory.ini by default per ansible.cfg)
  ansible-playbook playbooks/...

Note: FreeIPA host ALWAYS uses root user in both inventories to avoid
the dependency loop of using IPA auth to manage IPA itself.

---

## Summary - File Reference

| Component              | Path                                            |
|------------------------|-------------------------------------------------|
| Golden VM Template TF  | terraform/dev/proxmox/vms/golden-image/         |
| FreeIPA VM TF          | terraform/dev/proxmox/vms/freeipa/              |
| Golden VM Bootstrap    | proxmox/golden_templates/golden-vm-setup.sh     |
| Golden Setup Workflow  | .github/workflows/dev-golden-full-setup.yml     |
| FreeIPA Setup Workflow | .github/workflows/dev-freeipa-full-setup.yml    |
| First Setup Inventory  | ansible/dev/inventory/first_setup_inventory.ini |
| Main Inventory         | ansible/dev/inventory/inventory.ini             |
| FreeIPA Group Vars     | ansible/dev/inventory/group_vars/freeipa.yml    |
| FreeIPA Playbooks      | ansible/dev/playbooks/freeipa/                  |
| FreeIPA Setup Playbook | ansible/dev/playbooks/freeipa/freeipa_setup.yml |
| Domain Config Playbook | ansible/dev/playbooks/freeipa/domain_config.yml |
| Add Hosts Playbook     | ansible/dev/playbooks/freeipa/add_hosts_to_ipa.yml |
| Fix LXC Krb5 Playbook  | ansible/dev/playbooks/freeipa/fix_lxc_krb5_keyring.yml |
| Add DNS Playbook       | ansible/dev/playbooks/freeipa/add_dns_records.yml |

---

## AWS Secrets Reference

| Secret                             | Purpose                          |
|------------------------------------|----------------------------------|
| dev/proxmox/terraform-token        | Proxmox API credentials          |
| dev/ansible/ssh-public-key         | SSH key for initial VM access    |
| dev/golden-image/vm-root-password  | VM root password                 |
| dev/freeipa/admin-password         | FreeIPA admin password           |
| dev/freeipa/dm-password            | Directory Manager password       |
| dev/super_bot/keytab               | Kerberos keytab (base64)         |

---

## Ansible Vault Encrypted Variables

Location: ansible/dev/inventory/group_vars/freeipa.yml

| Variable                    | Purpose                              |
|-----------------------------|--------------------------------------|
| default_admin_user_password | Password for admin users             |
| default_bot_user_password   | Password for bot users (super_bot)   |

Note: Decrypt with ansible-vault or use vault password file configured in ansible.cfg

---

## Deployment Order Reference

Complete deployment order:

0. AWS Secrets (see aws-secrets-setup-guide.txt) - VERY FIRST
1. Ansible + Local Runner (see ansible-runner-setup-guide.txt)
2. FreeIPA (this guide)
3. Vault (see vault-initial-setup-guide.txt)
4. Kubernetes (see k8s-initial-setup-guide.txt)

Each subsequent service follows the pattern:
1. Deploy infrastructure (Terraform)
2. Join domain (add_hosts_to_ipa.yml)
3. Fix LXC keyring if needed (fix_lxc_krb5_keyring.yml)
4. Add DNS records (add_dns_records.yml)
5. Setup service (service-specific playbooks)

---
