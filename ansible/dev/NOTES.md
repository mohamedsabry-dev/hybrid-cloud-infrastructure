# Ansible Dev Environment Notes

## Quick Start - Manual Steps After Provisioning

After the ansible node is provisioned, run these manual steps to complete setup:

```bash
# 1. SSH to ansible node
ssh root@ansible.lab.local

# 2. Set Ansible config location (persists across reboots)
echo 'export ANSIBLE_CONFIG=/srv/repo/ansible/dev/ansible.cfg' >> ~/.bashrc
source ~/.bashrc

# 3. Create vault password file (get password from AWS Secrets Manager or team)
echo 'YOUR_VAULT_PASSWORD_HERE' > ~/.ansible_vault
chmod 600 ~/.ansible_vault

# 4. Configure git pull strategy
git config --global pull.rebase true

# 5. Verify setup
cd /srv/repo
ansible --version  # Should show config file path
ansible all -m ping  # Should ping all hosts
```

**Note:** The vault password file path is configured in `ansible/dev/ansible.cfg`:
```ini
vault_password_file = ~/.ansible_vault
```

---

## Ansible Config Location

We used the export approach to ensure Ansible picks up the correct config file regardless of the current working directory:

```bash
echo 'export ANSIBLE_CONFIG=/srv/repo/ansible/dev/ansible.cfg' >> ~/.bashrc
source ~/.bashrc
```

This is added to the ansible node's `~/.bashrc` so it persists across reboots.

## NTP Configuration Disabled

NTP configuration via FreeIPA client (`ipaclient_configure_ntp`) has been disabled due to inconsistency between VMs and LXC containers:

- **VMs (k8s_masters, k8s_workers)**: Chronyd works normally
- **LXC containers (vault_cluster, nginx, ansible, local_runners)**: Chronyd fails because LXC containers inherit time from the Proxmox host and systemd services don't run properly in containers

**Current setting in `group_vars/all.yml`:**
```yaml
ipaclient_no_ntp: true                # Correct variable - skips NTP during enrollment
ipaclient_configure_ntp: false        # Also set for completeness
# ipaclient_ntp_servers:              # Must be commented out
#   - freeipa.lab.local
```

**Note:** The FreeIPA ansible role uses `ipaclient_no_ntp: true` (not `ipaclient_configure_ntp: false`) to actually skip NTP configuration during client enrollment.

**TODO:** Configure NTP separately with direct Ansible playbooks:
- VMs: Configure chronyd pointing to FreeIPA server
- LXC: Skip NTP config (inherits from Proxmox host)

## Git Push from Ansible Node

The ansible node needs write access to push changes back to the repository.

### Deploy Key Configuration

The GitHub deploy key was initially set as **read-only**. Updated the workflow to use write access:

```yaml
# .github/workflows/dev-ansible-full-setup.yml (line ~135)
# Changed from:
-F read_only=true
# To:
-F read_only=false
```

To apply the change:
1. Delete existing deploy key on GitHub (Settings → Deploy keys → Delete `ansible-dev`)
2. Set `DEV_SVC_DEPLOY_KEY_LOCK` to `false` in repo variables
3. Re-run the workflow to re-add key with write access

### Git Pull Strategy

Configure rebase as default pull strategy on the ansible node to avoid merge commits:

```bash
git config --global pull.rebase true
```

This ensures `git pull` automatically rebases local commits on top of remote changes, keeping a clean linear history.

### Typical Workflow for Ansible Admin

```bash
# SSH to ansible node
ssh root@ansible.lab.local

# Pull latest changes
cd /srv/repo
git pull origin dev

# Make edits, test playbooks
vim ansible/dev/inventory/group_vars/all.yml
ansible-playbook ansible/dev/playbooks/freeipa/join-domain.yml

# Commit and push changes back
git add -A
git commit -m "Update configuration"
git push origin dev
```

## FreeIPA DNS Recursion Fix

The ansible-freeipa role does not properly configure DNS recursion for internal networks. After installation, clients could not resolve external domains (e.g., `mirrors.fedoraproject.org`) because:

1. **Forwarders not applied**: Despite setting `ipaserver_forwarders` in the playbook, `ipa dnsconfig-show` showed empty configuration
2. **Recursion denied**: BIND defaults to allowing recursion only from localhost (127.0.0.1). Clients received `REFUSED` with `EDE: 18 (Prohibited)`

**Symptoms:**
```bash
# From client - external DNS fails
dig @10.0.60.10 google.com
# status: REFUSED, WARNING: recursion requested but not available

# From FreeIPA server itself - works (queries from 127.0.0.1)
dig google.com
# works fine
```

**Fix added to `freeipa_setup.yml` post_tasks:**
```yaml
post_tasks:
  - name: Configure DNS forwarders
    freeipa.ansible_freeipa.ipadnsconfig:
      ipaadmin_password: "{{ ipaadmin_password }}"
      forwarders:
        - 8.8.8.8
        - 1.1.1.1
      forward_policy: first

  - name: Allow DNS recursion from internal networks
    ansible.builtin.blockinfile:
      path: /etc/named/ipa-options-ext.conf  # NOT ipa-ext.conf!
      block: |
        allow-recursion { 127.0.0.1; 10.0.0.0/8; };
        allow-query-cache { 127.0.0.1; 10.0.0.0/8; };
```

**Important:** Use `/etc/named/ipa-options-ext.conf` (included inside BIND options block), NOT `/etc/named/ipa-ext.conf` which is outside the options context.

## FreeIPA User SSH Login Issues

### Issue 1: VMs - SSH Permission Denied for IPA Users

**Symptoms:**
```bash
ssh super_bot@k8s-master1.lab.local
super_bot@k8s-master1.lab.local: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).
```

**Root Cause:**
Cloud-init sets `PasswordAuthentication no` in `/etc/ssh/sshd_config.d/50-cloud-init.conf`, which overrides the main sshd_config. GSSAPI (Kerberos) authentication requires a valid ticket and proper configuration.

**Solution:**
Enable password authentication on VMs:
```bash
# Via Ansible
ansible k8s_masters,k8s_workers -m replace -a "path=/etc/ssh/sshd_config.d/50-cloud-init.conf regexp='PasswordAuthentication no' replace='PasswordAuthentication yes'" --become
ansible k8s_masters,k8s_workers -m service -a "name=sshd state=restarted" --become
```

Or use GSSAPI with Kerberos ticket:
```bash
kinit super_bot
ssh super_bot@k8s-master1.lab.local
```

**Verification:**
```bash
# Check sshd config
cat /etc/ssh/sshd_config.d/*.conf | grep PasswordAuthentication

# Test HBAC from FreeIPA server
ipa hbactest --user=super_bot --host=k8s-master1.lab.local --service=sshd
```

### Issue 2: LXC Containers - initgroups Invalid Argument

**Symptoms:**
```bash
ssh super_bot@vault1.lab.local
Connection to vault1.lab.local closed by remote host.

# In sshd logs:
fatal: initgroups: super_bot: Invalid argument
```

**Root Cause:**
Unprivileged LXC containers use UID/GID mapping (e.g., container UID 0 → host UID 100000). FreeIPA by default uses high UIDs (1719400000+) which are outside the default mapping range (0-65535).

**Explanation:**
```
# Default unprivileged mapping:
Container UID 0-65535 → Host UID 100000-165535
Container UID 1719400000 → NOT MAPPED → fails with "Invalid argument"
```

#### Failed Approaches

**1. Manual config edit (unprivileged → privileged)**
```bash
# Attempted: Edit /etc/pve/lxc/<id>.conf
unprivileged: 0  # Changed from 1
```
**Result:** Container became inaccessible. File permissions broke because UID mappings changed but files were already created with mapped UIDs.

**2. Custom UID mapping on Proxmox host**
```bash
# Attempted: Add FreeIPA UID range to subuid/subgid
echo "root:1719400000:65536" >> /etc/subuid
echo "root:1719400000:65536" >> /etc/subgid

# Add to container config
lxc.idmap: u 0 100000 1719400000
lxc.idmap: g 0 100000 1719400000
lxc.idmap: u 1719400000 1719400000 65536
lxc.idmap: g 1719400000 1719400000 65536
```
**Result:** Complex to manage, prone to errors, requires manual steps per container.

**3. Privileged containers via Terraform with root@pam API token**
```bash
# Created root@pam API token with privsep=0
pveum user token add root@pam terraform --privsep=0
```
```hcl
# Terraform config
unprivileged = false
features { nesting = true }
```
**Result:** Failed with `Permission check failed (changing feature flags for privileged container is only allowed for root@pam)`. Even with privsep=0, API tokens cannot create privileged containers with feature flags - only password auth for root@pam works.

**4. Privileged containers with nesting disabled**
```hcl
# Terraform config
unprivileged = false
features { nesting = false }
```
**Result:** Container was created but Terraform failed with warning: `WARN: Systemd 257 detected. You may need to enable nesting.` Terraform treats warnings as failures, corrupting state.

**5. Password auth for root@pam in Terraform**
```hcl
provider "proxmox" {
  username = "root@pam"
  password = var.proxmox_root_password
}
```
**Result:** Would work but requires changing entire Terraform provider config and all workflows - too disruptive.

#### Working Solution: Custom FreeIPA UID Range

Configure FreeIPA to use UIDs within the unprivileged container's mapped range (0-65535).

**In `ansible/dev/playbooks/freeipa/freeipa_setup.yml`:**
```yaml
vars:
  # ID Range Configuration (fits within LXC unprivileged UID mapping 0-65535)
  # Range 50000-60000 avoids conflicts with local users (typically 1000-9999)
  ipaserver_idstart: 50000
  ipaserver_idmax: 60000
```

**Keep containers unprivileged with nesting:**
```hcl
# All LXC containers
unprivileged = true
features { nesting = true }
```

**Result:**
- Containers stay unprivileged (more secure)
- FreeIPA users get UIDs 50000-60000 (within mapped range)
- No Terraform permission issues
- No initgroups errors
- No workflow changes needed

---

## FreeIPA DNS Forwarders - Dictionary Syntax Error

**Symptom:**
```
TASK [Configure DNS forwarders]
fatal: [freeipa.lab.local]: FAILED! => "msg": "dictionary requested, could not parse JSON or key=value"
```

**Root Cause:**
The `freeipa.ansible_freeipa.ipadnsconfig` module expects forwarders as a list of dictionaries with `ip_address` keys, not plain strings.

**Wrong:**
```yaml
forwarders:
  - 8.8.8.8
  - 1.1.1.1
```

**Correct:**
```yaml
forwarders:
  - ip_address: 8.8.8.8
  - ip_address: 1.1.1.1
```

---

## Kerberos/GSSAPI Auth Requires Hostnames, Not IPs

**Symptom:**
```bash
# Using IP - FAILS
ansible all -m ping
# super_bot@10.0.64.11: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password)

# Using hostname - WORKS
ssh super_bot@k8s-worker1.lab.local
# Successfully connects with Kerberos ticket
```

**Root Cause:**
Kerberos authentication validates service principals using hostnames. When connecting via IP, GSSAPI cannot verify the service principal (`host/hostname@REALM`).

**Solution:**
Remove `ansible_host=IP` from inventory and use FQDNs directly. FreeIPA provides DNS resolution.

**Before:**
```ini
[k8s_workers]
k8s-worker1.lab.local ansible_host=10.0.64.10
```

**After:**
```ini
[k8s_workers]
k8s-worker1.lab.local
```

**Pre-requisite:** Run `kinit super_bot` before running Ansible commands.

---

## FreeIPA Password Policy - cospriority Required

**Symptom:**
```
TASK [Set password policy for automation users (4 years)]
fatal: [freeipa.lab.local]: FAILED! => "msg": "pwpolicy_add: automation_users: 'cospriority' is required"
```

**Root Cause:**
Group-based password policies require `cospriority` (Class of Service Priority) to determine which policy wins when a user belongs to multiple groups.

**Solution:**
Add `cospriority` to password policy tasks (lower number = higher priority):

```yaml
- name: Set password policy for automation users (4 years)
  freeipa.ansible_freeipa.ipapwpolicy:
    ipaadmin_principal: "{{ ipaadmin_principal }}"
    ipaadmin_password: "{{ ipaadmin_password }}"
    name: automation_users
    maxlife: 1460
    cospriority: 10

- name: Set password policy for admin users (1 year)
  freeipa.ansible_freeipa.ipapwpolicy:
    ipaadmin_principal: "{{ ipaadmin_principal }}"
    ipaadmin_password: "{{ ipaadmin_password }}"
    name: admin_users
    maxlife: 360
    cospriority: 20
```

---

## FreeIPA Server Doesn't Use SSSD for Sudo

**Symptom:**
```bash
# On FreeIPA server
ansible freeipa -m command -a "id -u"
freeipa.lab.local | FAILED | rc=-1 >> Missing sudo password

# Checking sudo rules shows nothing
sudo -l -U super_bot
User super_bot is not allowed to run sudo on freeipa.
```

But all other hosts (IPA clients) work fine.

**Root Cause:**
The FreeIPA **server** (IPA master) is the identity provider, not a client. It does not use SSSD for sudo lookups - sudo rules via SSSD only apply to IPA **clients**.

**Verification:**
```bash
# Host is in the hostgroup
ipa hostgroup-show automation_group
# Shows freeipa.lab.local as member

# Sudo rule exists
ipa sudorule-show super_bot
# Shows correct configuration

# But SSSD doesn't apply it on the server itself
sudo -l -U super_bot
# "not allowed to run sudo"
```

**Solution:**
Manage the FreeIPA server separately with root access in inventory:

```ini
[freeipa]
freeipa.lab.local ansible_user=root

[managed_hosts:children]
k8s_masters
k8s_workers
vault_cluster
ansible
local_runners
nginx

[managed_hosts:vars]
ansible_user=super_bot
ansible_become=yes
ansible_become_method=sudo
```

Use `ansible managed_hosts` for normal operations and `ansible freeipa` for IPA server management.

---

## FreeIPA UID Range - Must Be Above UID_MAX

**Symptom:**
```
TASK [freeipa.ansible_freeipa.ipaserver]
fatal: "ipaserver_idstart must be larger than UID_MAX"
```

**Root Cause:**
FreeIPA requires `ipaserver_idstart` to be higher than `UID_MAX` from `/etc/login.defs` (default 60000) to avoid conflicts with local users.

**Solution:**
Set UID range above 60000 but below 65536 (for LXC unprivileged container compatibility):

```yaml
# In freeipa_setup.yml
vars:
  # Must be > UID_MAX (60000) but < 65536 for LXC
  ipaserver_idstart: 60001
  ipaserver_idmax: 65500
```

---

## Utility Commands

**Clear SSH known_hosts after recreating infrastructure:**
```bash
for ip in 10.0.60.10 10.0.61.10 10.0.61.11 10.0.61.12 10.0.62.10 10.0.62.11 10.0.62.12 10.0.63.10 10.0.63.20 10.0.64.10 10.0.64.11 10.0.64.12 10.0.65.10; do ssh-keygen -R "$ip" 2>/dev/null; done
```

**Create vault-encrypted variable:**
```bash
ansible-vault encrypt_string 'your_secret_password' --name 'variable_name'
```

**Test Ansible connectivity with Kerberos:**
```bash
kinit super_bot
ansible managed_hosts -m command -a "id -u"
# All should return 0 (root)
```