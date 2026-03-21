# Session Summary - 2026-03-20
## Consolidation Phase + Vault Setup Chain of Issues

---

## Context: How It Started

Tested Vault configuration commands manually on a single vault node:
- Enabled audit logging
- Enabled LDAP auth with FreeIPA
- Created super_admin and readonly policies
- Mapped vault-admins group to policy
- Created local emergency user

Commands worked successfully. Decided to rollback and test same with Ansible automation.

---

## Issue Chain Discovery

### 1. Forgot to Take Snapshot Before Manual Testing

**Problem:** Wanted to rollback vault node to pre-config state but no snapshot existed.

**Attempted Solution:** Use Proxmox backup to restore to yesterday's state.

**Discovery:** Backup didn't exist → Led to discovering backup issues.

---

### 2. Backup Not Running (Dev Environment)

**Root Cause:** `repeat-missed` flag not enabled on dev backup job. Laptop was closed during scheduled backup time (Thu/Sat 21:00), so backup was skipped entirely.

**Why Not Noticed Before:** Prod had `repeat-missed 1` enabled, dev didn't.

**Fix:** Enabled `repeat-missed 1` via Proxmox Web UI on dev.

**Documentation:**
- `troubleshooting/proxmox/37-proxmox-backup-missed-not-retried.md`
- Updated `proxmox/backup/backup_config_guide.txt`

---

### 3. LXC Mount Points Not Backed Up

**Discovery:** While checking backup job details, noticed mp0 volumes showing "No - Disabled".

**Root Cause:** Terraform bpg/proxmox provider defaults `backup = false` for mount_points.

**Fix:** Updated all 16 Terraform LXC files (8 LXCs × 2 environments) with `backup = true`.

**Documentation:** `troubleshooting/proxmox/38-lxc-mount-point-backup-disabled.md`

---

### 4. Reverted to Old Snapshot → Need Vault Setup Workflow

**Action:** Reverted vault node to old snapshot (pre-vault setup state).

**Next Step:** Run vault_setup playbook via GitHub workflow to automate the setup.

---

### 5. Vault Workflow Failed - Kerberos Ticket Missing

**Error:** `super_bot` user unreachable - no valid Kerberos ticket.

**Why It Worked Before:** 2 days ago during active operation, had valid half-day ticket from manual kinit. Workflow succeeded because ticket already existed.

**Root Cause:** No automated kinit in workflow - relied on existing ticket which expired.

---

### 6. Keytab Authentication Failed

**Attempted Fix:** Fetch keytab from AWS Secrets Manager and use `kinit -k -t`.

**Error:** `kinit: Pre-authentication failed: Invalid argument`

**Root Cause:** `super_bot` password expired ~2 weeks ago. Password was changed, but keytab was generated BEFORE password change. Keytab keys are derived from password, so old keytab became invalid.

**Fix:**
1. Generated new keytab on FreeIPA: `ipa-getkeytab -s freeipa.lab.local -p super_bot -k /tmp/super_bot.keytab`
2. Uploaded to AWS Secrets Manager (base64 encoded) for both dev and prod
3. Updated workflows to fetch keytab and kinit before running playbook

**Documentation:**
- `ansible/dev/playbooks/freeipa/generate_keytab_guide.txt`
- `ansible/prod/playbooks/freeipa/generate_keytab_guide.txt`
- `troubleshooting/identity/36-keytab-preauthentication-failed.md`

---

## Final Actions Completed

1. **Keytab regenerated and saved to AWS** - Both dev and prod environments
2. **Vault workflows updated** - Added keytab fetch + kinit steps
3. **Backup configs mirrored** - Ensured prod backup matches dev settings
4. **Mount point backup enabled** - Terraform updated, will apply in-place
5. **Ran `vault operator init` manually** - Saved new unseal keys to AWS
6. **Will take full dev backup** - Oldest backup from March 15, need fresh backup

---

## Next Steps

1. Run Terraform apply to enable mount point backup on all LXCs
2. Take manual backup of dev environment
3. ~~Start working on Ansible playbook for Vault configuration automation~~ **DONE**

---

## Part 2: Vault Configuration Playbook Development

### Goal
Create `vault_config.yml` playbook to automate post-init Vault configuration:
- Enable audit logging
- Enable LDAP auth with FreeIPA
- Create policies (super_admin, readonly)
- Map vault-admins group to policy
- Create emergency userpass user

### Approach Evolution

#### Attempt 1: community.hashi_vault Modules (API approach)

Started with `community.hashi_vault.vault_login` and `vault_write` modules.

**Issues encountered:**

1. **hvac Python library missing**
   - Error: `No module named 'hvac'`
   - `community.hashi_vault` requires `hvac` Python library
   - Needed to install `python3-pip` first, then `pip install hvac`

2. **Where to install hvac?**
   - Options: vault_config.yml pre_tasks vs ansible_setup.yml vs pre_setup.yml
   - Decision: Added to `pre_setup.yml` so all nodes have it

3. **Idempotency failures**
   - Second run failed: `path is already in use at ldap/`
   - Required complex `failed_when` with error message parsing:
     ```yaml
     failed_when:
       - ldap_enable.failed
       - "'already in use' not in ldap_enable.msg | default('')"
     ```

4. **Jinja2 template conflict**
   - Vault LDAP uses `{{.UserDN}}` (Go template syntax)
   - Ansible interprets `{{` as Jinja2 variable
   - Error: `unexpected '.'`
   - Fix: Escape with `{{ '{{' }}.UserDN{{ '}}' }}`

#### Attempt 2: Shell Commands (Final approach)

Switched to `ansible.builtin.shell` with vault CLI commands.

**Advantages:**
- Simpler, more readable
- Vault CLI already installed
- `|| true` handles "already enabled" cleanly
- Environment variables apply to all commands
- One-time setup doesn't need complex idempotency

**Final playbook structure:**
```yaml
environment:
  VAULT_ADDR: "https://vault1.lab.local:8200"
  VAULT_TOKEN: "{{ vault_root_token }}"
  VAULT_CACERT: "/etc/ipa/ca.crt"

tasks:
  - name: Enable LDAP auth
    ansible.builtin.shell: vault auth enable ldap || true
```

### Decision: Shell vs API Modules

| Factor | API Modules | Shell Commands |
|--------|-------------|----------------|
| Complexity | High | Low |
| Dependencies | hvac Python library | None (CLI installed) |
| Idempotency | Complex error handling | `\|\| true` |
| Readability | Verbose | Matches CLI docs |
| Use case | Repeatable automation | One-time setup |

**Decision:** Shell commands for one-time setup playbooks.

### Decision: Idempotency Reporting

Options for `changed_when`:
1. `changed_when: false` - Always shows `ok` (but lies about real changes)
2. Custom logic per task - Complex and unreliable
3. Default behavior - Always shows `changed`

**Decision:** Leave default. For one-time setup, `changed` status is acceptable and honest.

### Decision: VAULT_AUTH_METHOD Environment Variable

Attempted to set `VAULT_AUTH_METHOD=ldap` in `/etc/profile.d/vault.sh` for shorter login commands.

**Issue:** `VAULT_AUTH_METHOD` is not a native Vault environment variable. `vault login` still prompted for token.

**Decision:** Keep native commands, document properly:
- `vault login -method=ldap username=<user>`
- `vault login -method=userpass username=vault-emergency`
- `vault login <root-token>`

### Files Created/Modified

**New/Updated Playbooks:**
- `ansible/dev/playbooks/vault/vault_config.yml` - Full implementation
- `ansible/prod/playbooks/vault/vault_config.yml` - Mirrored

**Updated pre_setup.yml (dev & prod):**
- Added pip installation
- Added hvac installation
- Made mirror fix idempotent

**Updated READMEs:**
- `ansible/dev/playbooks/vault/README.md` - Added decision log entries 11-14
- `ansible/prod/playbooks/vault/README.md` - Mirrored
- `ansible/dev/playbooks/common/README.md` - Updated pre_setup.yml docs
- `ansible/prod/playbooks/common/README.md` - Mirrored

### Vault Configuration Tested

Successfully configured:
- Audit logging enabled
- LDAP auth with FreeIPA
- Policies: super_admin, readonly
- Group mapping: vault-admins → super_admin
- Emergency user: vault-emergency

Login tested:
- `vault login -method=ldap username=sabry` ✅
- `vault login -method=userpass username=vault-emergency` ✅

---

## Files Created/Modified

### New Documentation
- `troubleshooting/proxmox/37-proxmox-backup-missed-not-retried.md`
- `troubleshooting/proxmox/38-lxc-mount-point-backup-disabled.md`
- `troubleshooting/identity/36-keytab-preauthentication-failed.md`
- `ansible/dev/playbooks/freeipa/generate_keytab_guide.txt`
- `ansible/prod/playbooks/freeipa/generate_keytab_guide.txt`

### Updated Files
- `.github/workflows/dev-vault-full-setup.yml` - Added keytab/kinit
- `.github/workflows/prod-vault-full-setup.yml` - Added keytab/kinit
- `proxmox/backup/backup_config_guide.txt` - Added Web UI steps

### Terraform Updates (16 files)
Added `backup = true` to mount_point blocks:
- `terraform/dev/proxmox/lxc/ansible/` (variables.tf, main.tf)
- `terraform/dev/proxmox/lxc/local_runner/` (variables.tf, main.tf)
- `terraform/dev/proxmox/lxc/nginx/` (variables.tf, main.tf)
- `terraform/dev/proxmox/lxc/vault_cluster/` (variables.tf, main.tf)
- `terraform/prod/proxmox/lxc/ansible/` (variables.tf, main.tf)
- `terraform/prod/proxmox/lxc/local_runner/` (variables.tf, main.tf)
- `terraform/prod/proxmox/lxc/nginx/` (variables.tf, main.tf)
- `terraform/prod/proxmox/lxc/vault_cluster/` (variables.tf, main.tf)

---

## Lessons Learned

1. **Always snapshot before testing** - Manual testing without snapshot leads to dependency on backups
2. **Verify backups actually run** - Check backup job details, not just that job exists
3. **Keytabs invalidate on password change** - Keys derived from password hash
4. **Don't rely on existing tickets** - Automate kinit in workflows
5. **Check all disk types in backup** - Mount points default to backup=false
6. **Mirror configs between environments** - Dev and prod should match

---

## Part 3: AWS Terraform Consolidation (2026-03-21)

### Goal
Consolidate `terraform/dev/aws` and `terraform/prod/aws` modules so code is identical between environments, with only `variables.tf` and `provider.tf` differing.

### Modules Consolidated

| Module | Files Made Identical | State Migration |
|--------|---------------------|-----------------|
| compute | main.tf, outputs.tf | No |
| network | main.tf, outputs.tf | No |
| iam | roles.tf, policies.tf, outputs.tf | Yes |
| secrets | main.tf, outputs.tf | No |
| kms-vault-unseal | kms.tf, user.tf, secret.tf, outputs.tf | No |

### Naming Convention Change
Changed from prefix pattern to suffix pattern:
- Old: `dev-wireguard-sg`, `SecurityBoundary-Dev`
- New: `wireguard-sg-dev`, `SecurityBoundary-dev`

### IAM State Migration Commands (Executed 2026-03-21)
```bash
terraform state mv aws_iam_role.dev_wireguard_ssm aws_iam_role.wireguard_ssm
terraform state mv aws_iam_role_policy_attachment.dev_wireguard_ssm_core aws_iam_role_policy_attachment.wireguard_ssm_core
terraform state mv aws_iam_instance_profile.dev_wireguard_ssm aws_iam_instance_profile.wireguard_ssm
terraform state mv aws_iam_policy.terraform_state_dev aws_iam_policy.terraform_state
terraform state mv aws_iam_policy.security_boundary_dev aws_iam_policy.security_boundary
```

### Workflow Execution Order (IMPORTANT)

**After IAM consolidation, run workflows in this order:**

1. **IAM workflow first** - Recreates IAM resources with new names
2. **Compute workflow second** - Updates EC2 to use new instance profile name

**Why:** Compute module references IAM instance profile via remote state:
```hcl
iam_instance_profile = data.terraform_remote_state.iam.outputs.wireguard_instance_profile_name
```

Between step 1 and step 2, EC2 temporarily loses SSM Session Manager access (instance profile deleted, new one not yet attached).

### Issues Encountered

#### Security Group Rename Stuck
- **Problem:** SG rename caused Terraform to get stuck on "Still destroying..."
- **Cause:** Can't delete SG while attached to EC2 ENI
- **Fix:** Temporarily assigned default VPC SG via AWS Console, Terraform completed
- **Prevention:** Uncomment `create_before_destroy` lifecycle block before renaming
- **Documentation:** `troubleshooting/terraform/40-terraform-security-group-rename-stuck.md`

### Files Updated

**Workflows (removed state migration after execution):**
- `.github/workflows/dev-aws-iam.yml`
- `.github/workflows/prod-aws-iam.yml`

**Added troubleshooting:**
- `troubleshooting/terraform/40-terraform-security-group-rename-stuck.md`

**Updated READMEs with troubleshooting section:**
- `terraform/dev/aws/compute/README.md`
- `terraform/prod/aws/compute/README.md`

**Added commented lifecycle block:**
- `terraform/dev/aws/compute/main.tf`
- `terraform/prod/aws/compute/main.tf`
