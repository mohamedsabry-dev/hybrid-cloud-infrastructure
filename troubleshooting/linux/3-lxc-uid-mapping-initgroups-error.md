# Case 3: LXC UID Mapping - initgroups Invalid Argument

## Status: RESOLVED
## Date: 2026-03-05
## Environment: DEV (lab.local)
## Affected Systems: All unprivileged LXC containers

---

## Symptom

SSH to LXC containers fails immediately after authentication.

```bash
ssh super_bot@vault1.lab.local
Connection to vault1.lab.local closed by remote host.

# In sshd logs on vault1:
fatal: initgroups: super_bot: Invalid argument
```

---

## Root Cause

### The UID Mapping Problem

Unprivileged LXC containers use **UID namespace mapping** for security. Container UIDs are mapped to different host UIDs:

```
Container UID 0     → Host UID 100000
Container UID 1000  → Host UID 101000
Container UID 65535 → Host UID 165535
```

FreeIPA by default assigns UIDs starting at **1719400000** (or similar high numbers). These are **way outside** the mapped range:

```
Container UID 1719400000 → NOT MAPPED → FAILS
```

When SSHD calls `initgroups()` to set up user groups, the kernel rejects the unmapped UID.

### Visual Explanation

```
Unprivileged LXC Container
┌─────────────────────────────────┐
│ Mapped Range: UID 0 - 65535     │  ✓ Works
│                                 │
│ FreeIPA Default: UID 1719400000 │  ✗ Unmapped!
└─────────────────────────────────┘
                │
                ▼
        "Invalid argument"
```

---

## Failed Approaches (What NOT to Do)

### 1. Manual Unprivileged → Privileged Conversion

```bash
# Attempted: Edit /etc/pve/lxc/<id>.conf
unprivileged: 0  # Changed from 1
```

**Result:** Container became inaccessible. Files were created with mapped UIDs (100000+), but privileged mode expects real UIDs (0+). Permissions broke completely.

### 2. Custom UID Mapping on Proxmox

```bash
# Attempted: Extend subuid/subgid
echo "root:1719400000:65536" >> /etc/subuid

# Add complex idmap rules
lxc.idmap: u 0 100000 1719400000
lxc.idmap: u 1719400000 1719400000 65536
```

**Result:** Complex, error-prone, requires manual steps per container.

### 3. Privileged Containers via Terraform (root@pam token)

```hcl
# Terraform with API token
unprivileged = false
features { nesting = true }
```

**Result:** `Permission check failed (changing feature flags for privileged container is only allowed for root@pam)`. API tokens cannot create privileged containers with feature flags, even with `privsep=0`.

### 4. Privileged Containers Without Nesting

```hcl
unprivileged = false
features { nesting = false }
```

**Result:** Container created but Terraform failed with: `WARN: Systemd 257 detected. You may need to enable nesting.` Terraform treats warnings as errors, corrupting state.

---

## Working Solution: Custom FreeIPA UID Range

Configure FreeIPA to assign UIDs **within the container's mapped range** (0-65535).

### Implementation

**File:** `playbooks/freeipa/freeipa_setup.yml`

```yaml
vars:
  # ID Range Configuration
  # Must be > UID_MAX (60000) from /etc/login.defs
  # Must be < 65536 for LXC unprivileged mapping
  ipaserver_idstart: 60001
  ipaserver_idmax: 65500
```

### Why This Range?

```
0 - 999      : System users (root, bin, daemon)
1000 - 59999 : Local users (created with useradd)
60000        : UID_MAX in /etc/login.defs
60001 - 65500: FreeIPA users (our range)
65536        : Unprivileged LXC mapping limit
```

### Container Configuration (No Changes Needed)

```hcl
# All LXC containers stay unprivileged
unprivileged = true
features { nesting = true }
```

---

## Benefits of This Solution

| Aspect | Result |
|--------|--------|
| Security | Containers stay unprivileged |
| Terraform | No permission issues |
| FreeIPA | Users get UIDs 60001-65500 |
| Simplicity | No manual mapping required |
| Compatibility | Works on all LXC containers |

---

## Simple Explanation

Think of UID mapping like apartment numbering:

**Inside the container (apartment building):**
- Apartment 1, 2, 3... up to 65535

**From the host's view (city records):**
- Building A apartments are numbered 100001, 100002, 100003...

If FreeIPA gives someone apartment number **1,719,400,000**, the building doesn't have that apartment! The doorman (kernel) says "Invalid argument - that apartment doesn't exist."

**The fix:** Tell FreeIPA to use apartment numbers the building actually has (60001-65500).

---

## Verification

```bash
# Check FreeIPA UID range
ipa idrange-show LAB.LOCAL_id_range

# Check a user's UID
id super_bot
# uid=60001(super_bot) gid=60001(super_bot) groups=...

# SSH should work now
ssh super_bot@vault1.lab.local
```

---

## Important Notes

1. **This must be set during FreeIPA server installation.** Changing the UID range after users are created requires user recreation.

2. **Limited user capacity:** Range 60001-65500 = ~5500 users max. Sufficient for small/medium deployments.

3. **For larger deployments:** Consider using privileged containers or VMs, or implement proper subuid mapping on Proxmox hosts.

---

## Commands Reference

### Check User UID
```bash
# Check UID of a user
id <username>

# Check UID range assigned by FreeIPA
getent passwd <username>
```

### Check FreeIPA ID Range
```bash
# View ID range configuration
ipa idrange-show LAB.LOCAL_id_range

# List all ID ranges
ipa idrange-find
```

### Check LXC UID Mapping
```bash
# On Proxmox host - check container config
cat /etc/pve/lxc/<container-id>.conf | grep -E "^lxc|unprivileged"

# Check subuid/subgid mapping
cat /etc/subuid
cat /etc/subgid
```

### Debug SSH Issues
```bash
# Check sshd logs on container
journalctl -u sshd -n 50

# Test SSH with verbose output
ssh -v <user>@<host>
```

### Check Login Defs
```bash
# View UID limits
grep -E "^UID" /etc/login.defs
```

---

## References

- [LXC Unprivileged Containers](https://linuxcontainers.org/lxc/security/)
- [FreeIPA ID Ranges](https://freeipa.readthedocs.io/en/latest/designs/id-ranges.html)
- [Proxmox UID Mapping](https://pve.proxmox.com/wiki/Unprivileged_LXC_containers)
