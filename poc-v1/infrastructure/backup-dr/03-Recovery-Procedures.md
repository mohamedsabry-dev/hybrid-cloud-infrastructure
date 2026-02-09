================================================================================
RECOVERY PROCEDURES
Disaster Recovery Guide - Part 5
================================================================================
Last Updated: 2026-01-03
Back to: [README.md](README.md)

================================================================================
TABLE OF CONTENTS
================================================================================
1. Recovery Overview & Decision Tree
2. Inner Layer Recovery (Normal Operations)
3. Outer Layer Recovery (Standalone ESXi)
4. Emergency Recovery (Domain Offline)
5. Special Scenarios

================================================================================
1. RECOVERY OVERVIEW & DECISION TREE
================================================================================

## Quick Decision Guide

**START HERE:** What failed and what's still online?

```
┌─────────────────────────────────────────┐
│ What needs to be restored?              │
└─────────────────┬───────────────────────┘
                  │
        ┌─────────┴────────────┐
        │                      │
    Inner Layer            Outer Layer
    (K8s, Vault, etc.)    (vCenter, ESXi, NAS, etc.)
        │                      │
        ↓                      ↓
   Is IPA online?         Always use
        │                 Standalone ESXi
    ┌───┴───┐                 │
    │       │                 ↓
   YES     NO           Section 3
    │       │
    ↓       ↓
Section 2  Section 4
(Domain)  (Emergency)
```

## Three Recovery Paths

### Path 1: Inner Layer Recovery (Normal - Domain Online)

**Use When:**
- Restoring inner layer VMs (K8s, Vault, Jenkins, Ansible, Monitor)
- IPA is online and accessible
- Domain authentication working

**Connection:**
- Outer Veeam → vCenter (10.0.20.89) → Production ESXi (10.0.20.101)

**User Account:**
- veeam@home.lab (domain user with passwordless sudo)

**See:** Section 2

---

### Path 2: Outer Layer Recovery (Always Standalone ESXi)

**Use When:**
- Restoring outer layer infrastructure VMs
- IPA, pfSense, NAS, vCenter, ESXi hosts, or Inner Veeam VM

**Connection:**
- Inner Veeam → ESXi Master (10.0.20.100) [Standalone - NOT vCenter]

**User Account:**
- veeam_emergency (local user with password)

**Why Standalone ESXi?**
- See [06-Design-Decisions.md](06-Design-Decisions.md#why-standalone-esxi-for-outer-layer-backups)
- Eliminates circular dependency (vCenter can't restore itself through itself)

**See:** Section 3

---

### Path 3: Emergency Recovery (Domain Offline)

**Use When:**
- IPA is down or unreachable
- Domain authentication not available
- Need to restore inner layer VMs but can't use domain user

**Connection:**
- Outer Veeam → vCenter → Production ESXi (connection still works)
- But: Use veeam_emergency (local user) instead of veeam@home.lab

**User Account:**
- veeam_emergency (local user with SSH key from Vault)

**See:** Section 4

================================================================================
2. INNER LAYER RECOVERY (NORMAL OPERATIONS)
================================================================================

## Scenario: Restore Inner Layer VM (Domain Online)

**Target VMs:** K8s Master, K8s Workers, Vault cluster, Jenkins, Ansible, Monitor

**Prerequisites:**
- IPA is online (10.0.20.89)
- vCenter is online (10.0.20.89)
- Production ESXi is online (10.0.20.101)
- Domain authentication working

## Recovery Steps

### Step 1: Verify Prerequisites

```bash
# From Windows Host
ping 10.0.20.89    # IPA online?
ping 10.0.20.101   # Production ESXi online?
```

**Connect to vCenter:**
- Open vSphere Client
- Connect to 10.0.20.89
- Verify Production ESXi shows as "Connected"

### Step 2: Open Outer Veeam

1. Open Veeam Backup & Replication (Outer instance on Windows Host)
2. Navigate to "Home" > "Backups" > "Disk"
3. Locate the VM backup you need to restore

**Backup Location:** Default Backup Repository (Host storage: D:\Veeam_Backups\)

### Step 3: Choose Restore Point

1. Right-click VM backup
2. Select "Restore entire VM"
3. Choose restore point (date/time)
4. Click "Next"

### Step 4: Configure Restore Options

**Restore Mode:** Restore to the original location
**Reason:** VM needs to be on Production ESXi with same network config

**VM Name:** Keep original or rename if testing
**Resource Pool:** Select Production ESXi (10.0.20.101)
**Network:** 10.0.20.x (VM Network)

**Power On:** Choose based on scenario
- Immediate production: Power on after restore
- Testing: Leave powered off, verify, then power on

### Step 5: Guest Processing (Domain User)

**CRITICAL:** This is where domain user is used

**Application-Aware Processing:**
- Enable: "Application-aware processing"
- Guest OS Credentials: **veeam@home.lab** (FreeIPA domain user)

**Why This Works:**
- veeam@home.lab has passwordless sudo
- Domain user can access VM filesystem
- Veeam can perform application-consistent restore

**What Happens:**
1. Veeam connects to restored VM using veeam@home.lab
2. Mounts filesystem
3. Performs application-aware operations
4. Ensures database consistency, etc.

### Step 6: Execute Restore

1. Review summary
2. Click "Finish"
3. Monitor restore progress in Veeam console

**Typical Restore Time:**
- Small VM (10 GB): 5-10 minutes
- Medium VM (50 GB): 15-30 minutes
- Large VM (100 GB): 30-60 minutes

### Step 7: Post-Restore Validation

**After VM Powers On:**

```bash
# SSH to restored VM
ssh <vm-ip>

# Verify services
systemctl status <service-name>

# Check logs for errors
journalctl -xe

# Verify domain connectivity (if applicable)
getent passwd veeam@home.lab

# Test application functionality
```

**For K8s Nodes:**
```bash
kubectl get nodes        # Verify node rejoined cluster
kubectl get pods -A      # Check pod status
```

**For Vault Nodes:**
```bash
vault status             # Check Vault status
vault operator raft list-peers  # Verify raft cluster
```

## Troubleshooting Normal Recovery

**Issue: Cannot connect using veeam@home.lab**

**Cause:** Domain authentication issue

**Checks:**
1. Is IPA online? `ping 10.0.20.89`
2. Can VM reach IPA? `getent passwd veeam@home.lab`
3. Is user in correct groups?

**Solution:**
- If IPA is down, use Emergency Recovery (Section 4)
- If IPA online but user issue, fix in IPA web UI

**Issue: Restore completes but VM won't boot**

**Cause:** Corrupted restore or hardware mismatch

**Solution:**
1. Try different restore point (earlier backup)
2. Check VM hardware settings match original
3. Review VMware Tools logs
4. Boot into rescue mode to check filesystem

================================================================================
3. OUTER LAYER RECOVERY (STANDALONE ESXI)
================================================================================

## Scenario: Restore Outer Layer Infrastructure VM

**Target VMs:** IPA, pfSense, NAS, vCenter, ESXi hosts (nested), Inner Veeam VM

**Connection Method:** **ALWAYS Standalone ESXi Master (NOT vCenter)**

**Why?** See [06-Design-Decisions.md](06-Design-Decisions.md#why-standalone-esxi-for-outer-layer-backups)

## Recovery Steps

### Step 1: Open Inner Veeam

**Access Inner Veeam:**
1. RDP or console to Inner Veeam VM (10.0.20.195)
2. Open Veeam Backup & Replication
3. Navigate to "Home" > "Backups" > "Disk"

**Backup Location:** Backup Repository Host (NAS storage: /mnt/backups/veeam/)

### Step 2: Locate Backup

**Backup Jobs (Reference):**
- IPA - Daily automated backup
- pfSense - Daily automated backup
- NAS Server - Manual backup
- Production ESXi - Manual backup
- DR ESXi - Manual backup
- vCenter - Manual backup
- Veeam (Inner) - Daily automated backup

**Choose Restore Point:**
1. Right-click VM backup
2. Select "Restore entire VM"
3. Choose restore point

### Step 3: Configure Restore Target

**CRITICAL: Connection Configuration**

**Infrastructure:**
- **NOT** vCenter
- **YES** Standalone ESXi Master (10.0.20.100)

**In Veeam UI:**
1. Restore Mode: "Restore to the original location"
2. Host: **ESXi Master (10.0.20.100)** [Standalone connection]
3. Resource Pool: ESXi Master inventory
4. Datastore: Select appropriate datastore on ESXi Master

**Why Standalone?**
- If restoring vCenter, can't restore through vCenter itself (circular dependency)
- Standalone ESXi connection works independently
- No dependency on vCenter being online

### Step 4: Guest Processing (Emergency User)

**User Account:** veeam_emergency (local user with password)

**Application-Aware Processing:**
- Enable if needed for application consistency
- Guest OS Credentials: **veeam_emergency** (local user with password)

**Password Source:** Stored on Windows Host (secure location)

**Why Not SSH Key?**
- Outer layer uses password, not SSH key
- Avoids dependency on Inner Veeam (which stores SSH private key)
- Outer layer must be restorable independently

### Step 5: Execute Restore

1. Review summary
2. Verify target is Standalone ESXi Master (NOT vCenter)
3. Click "Finish"
4. Monitor restore progress

### Step 6: Post-Restore Validation

**After VM Powers On:**

**For IPA:**
```bash
# Verify DNS
dig home.lab @10.0.20.89

# Verify IPA services
ipactl status

# Test domain authentication
kinit admin@HOME.LAB
```

**For vCenter:**
```
# Access vCenter UI
https://10.0.20.89

# Verify inventory
Check ESXi hosts appear
Check VM inventory accurate
```

**For NAS:**
```bash
# Verify NFS exports
showmount -e 10.0.20.x

# Test mount from another VM
mount -t nfs 10.0.20.x:/export /mnt/test
```

## Special Case: Restoring Inner Veeam VM

**Scenario:** Inner Veeam VM failed, need to restore

**Backup Source:** Outer Veeam (Windows Host)
**Target:** ESXi Master (10.0.20.100)

**Steps:**
1. Open Outer Veeam (Windows Host)
2. Locate "Veeam (Inner)" backup
3. Restore to ESXi Master (via vCenter connection - this is OK)
4. Power on Inner Veeam VM
5. Reconnect to NAS repository
6. Verify backup jobs resume

**Post-Restore:**
```powershell
# On Inner Veeam VM
# Reconnect to NAS repository
# Veeam should auto-detect existing backups
# Verify job configurations intact
```

================================================================================
4. EMERGENCY RECOVERY (DOMAIN OFFLINE)
================================================================================

## Scenario: Restore Inner Layer VM When IPA is Down

**Situation:**
- Need to restore inner layer VM (K8s, Vault, etc.)
- But IPA is offline or unreachable
- Domain authentication not available

**User Account:** veeam_emergency (local user with SSH key)

## Prerequisites

**SSH Key Must Be Available:**
- Private key stored in: HashiCorp Vault (secret/data/infra/veeam_emergency)
- Alternative: Private key on Veeam server (if Vault is also down)

**Retrieve SSH Key from Vault:**
```bash
vault kv get -field=private_key secret/infra/veeam_emergency > /tmp/veeam_emergency_key
chmod 600 /tmp/veeam_emergency_key
```

## Recovery Steps

### Step 1: Verify IPA is Actually Down

```bash
ping 10.0.20.89        # Is IPA reachable?
ssh admin@10.0.20.89   # Can you access IPA?
```

**If IPA is down:**
- Proceed with emergency recovery
- Use veeam_emergency instead of veeam@home.lab

**If IPA is online:**
- Use normal recovery (Section 2)
- Troubleshoot why domain auth isn't working

### Step 2: Configure Veeam to Use Emergency User

**In Outer Veeam:**
1. Navigate to backup job
2. Restore entire VM
3. Choose restore point

**Guest Processing Configuration:**
- Application-aware processing: Disable (or configure with veeam_emergency)
- Guest OS Credentials: **veeam_emergency**
- Authentication: SSH key
- SSH Key Path: /path/to/veeam_emergency_key

**Why SSH Key?**
- veeam_emergency on inner layer VMs uses SSH key authentication
- No password required
- Key stored in Vault for security

### Step 3: Execute Restore

1. Verify connection uses veeam_emergency (not veeam@home.lab)
2. Execute restore
3. Monitor progress

### Step 4: Post-Restore (Without Domain)

**VM will boot without domain connectivity:**

```bash
# SSH using emergency user
ssh -i /path/to/key veeam_emergency@<vm-ip>

# Services may fail to start (if they depend on IPA)
systemctl status <service>

# Check logs
journalctl -xe | grep -i ipa
```

**Temporary Workaround (Until IPA Restored):**
- Configure services to skip IPA dependency temporarily
- Use local authentication
- Restore IPA as priority

### Step 5: Restore IPA (Priority)

**Once inner layer VM restored:**
1. Immediately proceed to restore IPA (Section 3)
2. Use Standalone ESXi method
3. Use veeam_emergency (password) for IPA VM

**After IPA Online:**
- Inner layer VMs can rejoin domain
- Switch back to normal recovery procedures
- Domain authentication restored

## Emergency User Deployment (If Missing)

**Scenario:** veeam_emergency user doesn't exist on restored VM

**Solution:** Deploy via Ansible

```bash
cd /03-AUTOMATION/ansible-playbooks/os-services
ansible-playbook 01-emergency-user.yml --limit <restored-vm>
```

**What This Does:**
1. Creates veeam_emergency user
2. Retrieves SSH public key from Vault
3. Deploys to ~/.ssh/authorized_keys
4. Configures passwordless sudo

See [02-User-Accounts.md](02-User-Accounts.md) for full details.

================================================================================
5. SPECIAL SCENARIOS
================================================================================

## Scenario A: Complete Infrastructure Loss

**Situation:** All VMs lost, need to rebuild from scratch

**Recovery Order:**
1. **ESXi Master** - Manual VM import to VMware Workstation
2. **IPA** - Restore using Standalone ESXi (Section 3)
3. **pfSense** - Restore for network connectivity
4. **NAS** - Restore for backup repository
5. **vCenter** - Restore for management
6. **Inner Veeam** - Restore from Outer Veeam backup
7. **Production ESXi** - Restore nested hypervisor
8. **Inner Layer VMs** - Restore using normal procedure (Section 2)

## Scenario B: NAS Failure (Backup Repository Down)

**Problem:** NAS VM failed, backup repository unavailable

**Impact:**
- Outer layer backups inaccessible
- Inner Veeam can't access its repository
- vCenter built-in backups also on NAS (if using /mnt/datastor2)

**Recovery:**
1. **NAS VM restore:** Use Inner Veeam → Standalone ESXi
   - But wait, NAS backup is ON NAS (circular dependency!)

**Solution:**
- NAS VM backup stored on NAS repository
- Need to restore NAS VM first to access repository
- Use standalone ESXi to access VM files directly
- Manual VM registration and power-on
- Then reconnect Inner Veeam to repository

**Alternative:**
- If NAS VM backup copy exists on Windows Host (secondary repository)
- Restore from there instead
- See [01-Backup-Strategy.md](01-Backup-Strategy.md) for repository strategy

## Scenario C: vCenter Failure

**Problem:** vCenter VM failed

**Impact:**
- Can't manage ESXi hosts
- Can't restore inner layer VMs (need vCenter for connection)
- Management operations unavailable

**Recovery:**
1. **Use Inner Veeam → Standalone ESXi Master**
2. Restore vCenter VM
3. Power on vCenter
4. Verify inventory
5. Resume normal operations

**Built-in Backup Alternative:**
- vCenter has built-in backup on /mnt/datastor2 (see [01-Backup-Strategy.md](01-Backup-Strategy.md))
- Can restore using vCenter recovery ISO if Veeam unavailable
- Application-aware recovery for vCenter-specific data

## Scenario D: Both Veeam Instances Down

**Problem:** Inner and Outer Veeam both failed

**Impact:**
- No Veeam to restore from
- Need alternative recovery method

**Recovery:**
1. **Outer Veeam:** Reinstall Veeam on Windows Host
   - Reconnect to repository (D:\Veeam_Backups\)
   - Import backup jobs
   - Restore Inner Veeam VM

2. **Inner Veeam:** Restore from Outer Veeam
   - Power on Inner Veeam VM
   - Reconnect to NAS repository
   - Import backup jobs
   - Resume operations

**Prevention:**
- Outer Veeam backs up Inner Veeam VM (cross-protection)
- Veeam configuration database backed up

================================================================================
RECOVERY CHECKLIST
================================================================================

## Pre-Recovery

- [ ] Identify what failed (inner vs outer layer?)
- [ ] Check if IPA is online (determines user account)
- [ ] Verify vCenter is accessible
- [ ] Locate most recent backup restore point
- [ ] Document current state (for comparison)

## During Recovery

- [ ] Choose correct recovery path (Section 2, 3, or 4)
- [ ] Use correct user account (veeam@home.lab vs veeam_emergency)
- [ ] Use correct connection (vCenter vs Standalone ESXi)
- [ ] Monitor restore progress
- [ ] Check for errors

## Post-Recovery

- [ ] VM powers on successfully
- [ ] Services start correctly
- [ ] Network connectivity works
- [ ] Domain authentication works (if applicable)
- [ ] Application functionality verified
- [ ] Logs reviewed for errors
- [ ] Backup jobs resume normally

================================================================================
RELATED DOCUMENTATION
================================================================================

- [01-Backup-Strategy.md](01-Backup-Strategy.md) - Where backups are stored
- [02-User-Accounts.md](../Identity/02-User-Accounts.md) - Domain user vs emergency user details
- [06-Design-Decisions.md](06-Design-Decisions.md) - Why standalone ESXi for outer layer?
- [07-Configuration-Reference.md](07-Configuration-Reference.md) - IP addresses, paths

Back to: [README.md](README.md)
