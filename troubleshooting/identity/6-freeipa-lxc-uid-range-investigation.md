# TS-IDN-006 | 2026-03-05 | RESOLVED

## 1. Context
- System: FreeIPA / LXC / UID Namespace
- Environment: DEV (lab.local)
- Related components: FreeIPA server, all unprivileged LXC containers (vault_cluster, ansible, local_runners, nginx)
- Related tickets:
  - [TS-IDN-001](1-lxc-kerberos-keyring-auth-failure.md) - LXC Kerberos keyring failure (related LXC UID issue, different solution)

## 2. Issue
- Symptom: Multiple failures related to FreeIPA user UIDs on LXC containers
- Errors encountered during investigation:

**Error 1 - FreeIPA Installation:**
```
TASK [freeipa.ansible_freeipa.ipaserver]
fatal: [freeipa.lab.local]: FAILED! => "msg": "ipaserver_idstart must be larger than UID_MAX"
```

**Error 2 - SSH to LXC after domain join:**
```bash
ssh super_bot@vault1.lab.local
Connection to vault1.lab.local closed by remote host.
```

**Error 3 - SSHD logs on LXC:**
```
fatal: initgroups: super_bot: Invalid argument
```

---

# PHASE 1: FreeIPA UID Range Error | 2026-03-05

## Symptoms (Phase 1)
FreeIPA server installation fails with UID range validation error.

---

## 3. Analysis (Phase 1)

**Check 1: What is UID_MAX?**
```bash
# On FreeIPA server
grep UID_MAX /etc/login.defs
UID_MAX    60000
```
Finding: Linux reserves UIDs 0-60000 for local users created with `useradd`.

---

**Check 2: Why does FreeIPA need UIDs above this?**

FreeIPA creates domain users with UIDs. If FreeIPA used UIDs in the local range:
- Local user `bob` (UID 1001) vs FreeIPA user `bob` (UID 1001) = conflict
- `id bob` would be ambiguous

FreeIPA must use UIDs **above** UID_MAX to avoid conflicts.

Finding: FreeIPA UIDs must be > 60000 to avoid local user conflicts. ✓

---

**Check 3: What about LXC containers?**

LXC unprivileged containers use UID namespace mapping:
```
Container UID 0-65535 → Host UID 100000-165535 (example mapping)
```

```bash
# On Proxmox host - check subuid mapping
cat /etc/subuid
root:100000:65536
```
Finding: LXC maps 65536 UIDs (0-65535). FreeIPA UIDs must fit within this range. ✓

---

**Check 4: What's the safe range?**
```
UID_MAX (local users)     = 60000
LXC max supported UID     = 65535

Safe FreeIPA range: 60001 - 65535
```
Finding: Intersection of requirements = 60001-65535. ✓

---

## 4. Root Cause (Phase 1)
> FreeIPA UIDs must satisfy two constraints:
> 1. **Above UID_MAX (60000)** - to avoid conflict with local users
> 2. **Below 65536** - to work in LXC unprivileged containers (UID namespace mapping)
>
> The intersection is: **60001 - 65535**

---

## 5. Solution (Phase 1)

**Configure FreeIPA UID range within safe bounds:**

**File:** `ansible/dev/playbooks/freeipa/freeipa_setup.yml`

```yaml
vars:
  # ID Range Configuration (fits within LXC unprivileged UID mapping 0-65535)
  # Must be above UID_MAX (60000) from /etc/login.defs
  # Must be below 65536 for LXC unprivileged containers
  ipaserver_idstart: 60001
  ipaserver_idmax: 65500
```

**Verification:**
```bash
# On FreeIPA server - check ID range
ipa idrange-show LAB.LOCAL_id_range
  Range name: LAB.LOCAL_id_range
  First Posix ID of the range: 60001
  Number of IDs in the range: 5500
```

---
---

# PHASE 2: SSH initgroups Failure | 2026-03-05

## Symptoms (Phase 2)
After FreeIPA was initially installed with **default UID range** (before Phase 1 fix), SSH to LXC containers failed:

```bash
ssh super_bot@vault1.lab.local
Connection to vault1.lab.local closed by remote host.
```

SSHD logs on vault1:
```
fatal: initgroups: super_bot: Invalid argument
```

---

## 3. Analysis (Phase 2)

**Check 1: What is initgroups doing?**
```
initgroups() - initializes the group access list for a user
Called by sshd after authentication to set up user's groups
```
Finding: Kernel is rejecting the UID when setting up groups.

---

**Check 2: What UID does the user have?**
```bash
# On FreeIPA server
ipa user-show super_bot --all | grep uidnumber
  uidnumber: 1719400001
```
Finding: FreeIPA assigned UID 1719400001 (default high range). ✗

---

**Check 3: How does LXC UID mapping work?**
```
Unprivileged LXC uses UID namespace mapping:

Container UID 0     → Host UID 100000
Container UID 1000  → Host UID 101000
Container UID 65535 → Host UID 165535

Mapped range: 0 - 65535 ONLY
```
Finding: Container can only handle UIDs 0-65535. ✓

---

**Check 4: Why does it fail?**
```
Container UID 1719400001 → NOT MAPPED → Kernel rejects → "Invalid argument"
```

```
Unprivileged LXC Container
┌─────────────────────────────────┐
│ Mapped Range: UID 0 - 65535     │  ✓ Works
│                                 │
│ FreeIPA Default: UID 1719400001 │  ✗ Unmapped!
└─────────────────────────────────┘
                │
                ▼
        "Invalid argument"
```

Finding: UID 1719400001 is outside LXC mapped range. ✓

---

## 4. Root Cause (Phase 2)
> FreeIPA default UID range (1719400000+) is **outside** the LXC unprivileged container's mapped UID range (0-65535). When SSHD calls `initgroups()` to set up user groups, the kernel rejects the unmapped UID.

**Analogy:** Think of UID mapping like apartment numbering. Inside the container (building), apartments are numbered 1-65535. FreeIPA gave someone apartment 1,719,400,000 - the building doesn't have that apartment! Doorman (kernel) says "Invalid argument."

---

## 5. Solution (Phase 2)
> Same as Phase 1 - configure FreeIPA to assign UIDs within the container's mapped range (60001-65500).

**After reconfiguring FreeIPA and recreating users:**
```bash
# Check a user's UID
id super_bot
uid=60001(super_bot) gid=60001(super_bot) groups=...

# SSH should work now
ssh super_bot@vault1.lab.local
[super_bot@vault1 ~]$
```

---

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Limited to ~5500 domain users (60001-65500). Sufficient for small/medium deployments.

## 7. Impact After Fix
- Observed: FreeIPA installation succeeds with correct UID range
- Domain users work in both VMs and LXC containers
- SSH to LXC containers works for all domain users
- No UID conflicts with local users

| Aspect | Result |
|--------|--------|
| Security | Containers stay unprivileged |
| FreeIPA | Users get UIDs 60001-65500 |
| Compatibility | Works on all LXC containers |
| VMs | Not affected (no UID mapping) |

## 8. Notes

**UID Range Planning:**
| Range | Purpose |
|-------|---------|
| 0-999 | System users (root, bin, daemon) |
| 1000-60000 | Local users (useradd) |
| 60001-65500 | FreeIPA domain users |
| 65501-65535 | Reserved buffer |

**Failed approaches (what NOT to do):**

1. **Manual Unprivileged → Privileged conversion**
   - Edit `/etc/pve/lxc/<id>.conf` → `unprivileged: 0`
   - Result: Container became inaccessible - permissions broke

2. **Custom UID mapping on Proxmox**
   - Extend subuid/subgid with complex idmap rules
   - Result: Complex, error-prone, manual per container

3. **Privileged containers via Terraform**
   - Result: `Permission check failed` - API tokens cannot create privileged containers with feature flags

4. **Privileged containers without nesting**
   - Result: Terraform treats systemd warnings as errors, corrupts state

**Important:** UID range must be set during FreeIPA server installation. Changing UID range after users exist requires user recreation.

**For larger deployments (no LXC):**
```yaml
ipaserver_idstart: 60001
ipaserver_idmax: 200000  # No LXC = no 65536 limit
```

## 9. Workaround (if any)
> Use VMs instead of LXC for systems that need domain users with high UIDs.

## References
- [Linux UID/GID Ranges](https://man7.org/linux/man-pages/man5/login.defs.5.html)
- [LXC Unprivileged Containers](https://linuxcontainers.org/lxc/security/)
- [FreeIPA ID Ranges](https://freeipa.readthedocs.io/en/latest/designs/id-ranges.html)
- [Proxmox UID Mapping](https://pve.proxmox.com/wiki/Unprivileged_LXC_containers)

