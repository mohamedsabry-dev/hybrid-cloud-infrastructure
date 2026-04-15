# TS-IDN-009 | 2026-04-15 | RESOLVED

## 1. Context
- System: SSSD / FreeIPA / SSH / Ansible
- Environment: DEV (lab.local)
- Related components: Ansible automation, SSH KnownHostsCommand, sss_ssh_knownhosts
- Discovery: **Discovered during IPA Domain Down DR Test (Part 2)**

## 2. Issue
- Symptom: Ansible ad-hoc commands and playbooks take ~28-34 seconds to execute when FreeIPA is down
- Direct SSH connections work normally (~1-2 seconds)
- `raw` module executes fast (~0.7 seconds)
- `ping`, `shell`, `command` modules are slow (~28-34 seconds)

**Example (slow):**
```bash
[root@ansible dev]# time ansible -i inventory/first_setup_inventory.ini 10.0.64.10 -m ping
10.0.64.10 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}

real    0m34.479s
user    0m0.856s
sys     0m0.318s
```

**Example (fast with raw module):**
```bash
[root@ansible dev]# time ansible -i inventory/first_setup_inventory.ini 10.0.64.10 -m raw -a 'hostname'
10.0.64.10 | CHANGED | rc=0 >>
k8s-worker1.lab.local

real    0m0.716s
user    0m0.378s
sys     0m0.087s
```

## 3. Analysis

### Check 1: Initial hypothesis - Python interpreter discovery
```
| Module | Time   | Uses Python on Target |
|--------|--------|----------------------|
| raw    | 0.7s   | No                   |
| ping   | 28s    | Yes                  |
```
Initial finding: Suspected Python-related DNS lookups. **This was incorrect.**

### Check 2: Test with explicit Python interpreter
```bash
time ansible -i inventory/first_setup_inventory.ini 10.0.64.10 -m ping \
  -e 'ansible_python_interpreter=/usr/bin/python3'

real    0m28.253s  # Still slow - not the root cause
```
Finding: Python interpreter discovery is NOT the root cause.

### Check 3: Test SSH directly
```bash
time ssh root@10.0.64.10 'hostname'
k8s-worker1.lab.local
real    0m1.2s  # Fast
```
Finding: Direct SSH is fast. Issue is Ansible-specific.

### Check 4: Test with PreferredAuthentications
```bash
# Added to inventory:
ansible_ssh_common_args='-o PreferredAuthentications=publickey'

# Result: Still slow ~28 seconds
```
Finding: Kerberos/GSSAPI fallback is NOT the root cause.

### Check 5: Destroy Kerberos tickets
```bash
kdestroy
time ansible -i inventory/first_setup_inventory.ini 10.0.64.10 -m ping
# Result: Still slow ~28 seconds
```
Finding: Kerberos tickets are NOT the root cause.

### Check 6: Deep verbose analysis (-vvvv)
```bash
time ansible -i inventory/first_setup_inventory.ini 10.0.64.10 -m ping -vvvv
```

**Critical finding in SSH debug output:**
```
debug3: subprocess: KnownHostsCommand-ORDER command "/usr/bin/sss_ssh_knownhosts 10.0.64.10" running as root (flags 0x1a)
debug3: subprocess: KnownHostsCommand-ORDER pid 4948
...
debug3: subprocess: KnownHostsCommand-HOSTNAME command "/usr/bin/sss_ssh_knownhosts 10.0.64.10" running as root (flags 0x1a)
debug3: subprocess: KnownHostsCommand-HOSTNAME pid 4949
```

This is configured by FreeIPA in `/etc/ssh/ssh_config.d/04-ipa.conf`:
```
Match exec "true"
    KnownHostsCommand /usr/bin/sss_ssh_knownhosts %H
```

### Check 7: Count SSH connections per Ansible ping
From verbose output, Ansible `ping` module requires **7 SSH connections**:

| Step | Purpose |
|------|---------|
| 1 | Get home directory (`echo ~root`) |
| 2 | Create temp directory |
| 3 | Python interpreter discovery |
| 4 | Get platform info via Python |
| 5 | SFTP upload module |
| 6 | chmod the module |
| 7 | Execute the module |
| 8 | Cleanup temp files |

Each SSH connection calls `sss_ssh_knownhosts` **TWICE**:
- KnownHostsCommand-ORDER
- KnownHostsCommand-HOSTNAME

### Check 8: Calculate the delay
```
| Component                        | Count |
|----------------------------------|-------|
| SSH connections per ping         | 7-8   |
| sss_ssh_knownhosts calls per SSH | 2     |
| Total SSSD lookups               | 14-16 |
| Timeout per lookup (approx)      | ~2s   |
| Total delay                      | ~28s  |
```

## 4. Root Cause
> When FreeIPA is down, the SSH `KnownHostsCommand` (`/usr/bin/sss_ssh_knownhosts`) attempts to contact SSSD to retrieve host keys from FreeIPA. SSSD times out waiting for the IPA server on each lookup. Since Ansible makes 7-8 SSH connections per module execution, and each SSH connection triggers 2 SSSD lookups, the cumulative timeout is ~28-34 seconds.

**Key insight:** This is NOT related to:
- Kerberos/GSSAPI authentication
- Python interpreter discovery
- SSH connection itself
- DNS resolution

It is specifically the **SSSD-based SSH host key lookup** timing out.

## 5. Solution
> Disable the SSSD KnownHostsCommand for Ansible connections.

**Why this works:** SSH will use local `known_hosts` files instead of querying SSSD/FreeIPA for host keys.

**Location:** Ansible inventory file (`inventory/first_setup_inventory.ini`)

**Add to inventory:**
```ini
[all:vars]
ansible_ssh_common_args='-o KnownHostsCommand=none'
```

**Verification:**
```bash
[root@ansible dev]# time ansible -i inventory/first_setup_inventory.ini 10.0.64.10 -m ping
10.0.64.10 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}

real    0m2.996s
user    0m0.502s
sys     0m0.161s
```

**Result:** From **28 seconds to 3 seconds** - issue resolved.

## 6. Solution Risk
- Risk level: LOW
- Potential impact: SSH host key verification will use local `known_hosts` instead of SSSD/FreeIPA
- Security consideration: Host keys are still verified, just not dynamically fetched from IPA

## 7. Impact After Fix
- Observed: Ansible commands execute in ~3 seconds regardless of FreeIPA availability
- No negative side effects observed
- Ansible automation remains functional during IPA outages

## 8. Alternative Solutions Considered

### Option A: Reduce SSSD timeout (NOT recommended)
```bash
# /etc/sssd/sssd.conf
[domain/lab.local]
dns_resolver_timeout = 1
```
**Risk:** May cause false failures during network blips, affecting user authentication.

### Option B: Modify IPA SSH config (NOT recommended)
```bash
# Comment out KnownHostsCommand in:
/etc/ssh/ssh_config.d/04-ipa.conf
```
**Risk:** Affects all SSH connections system-wide, not just Ansible.

### Option C: SSSD SSH-specific timeout (Alternative)
```bash
# /etc/sssd/sssd.conf
[ssh]
ssh_known_hosts_timeout = 1
```
**Risk:** May have unintended effects on other SSH operations.

**Selected: Option via `ansible_ssh_common_args`** - Targeted, low-risk, Ansible-specific.

## 9. Workaround (if any)
> Use `raw` module for critical operations when IPA is down - it doesn't require Python and uses single SSH connection.

```bash
# Fast even without the fix:
ansible -i inventory/first_setup_inventory.ini all -m raw -a 'systemctl status sshd'
```

## 10. Evidence Summary

### Timeline of Investigation
| Time | Test | Result | Conclusion |
|------|------|--------|------------|
| 22:51 | ping module | 34.479s | Slow |
| 22:52 | raw module | 0.716s | Fast |
| 22:53 | ansible_python_interpreter | 28.253s | Still slow - not Python |
| 22:54 | PreferredAuthentications | 28s | Still slow - not Kerberos |
| 22:55 | kdestroy | 28s | Still slow - not tickets |
| 23:02 | -vvvv analysis | Found sss_ssh_knownhosts | Root cause identified |
| 23:05 | KnownHostsCommand=none | 2.996s | **SOLVED** |

### Comparison: Before vs After Fix
| Metric | Before Fix | After Fix |
|--------|------------|-----------|
| Ansible ping | ~28-34 seconds | ~3 seconds |
| SSH connections | 7-8 | 7-8 (unchanged) |
| SSSD lookups | 14-16 (all timeout) | 0 |

## Related Files
- `/etc/ssh/ssh_config.d/04-ipa.conf` - FreeIPA SSH configuration
- `/usr/bin/sss_ssh_knownhosts` - SSSD host key lookup command
- `ansible/dev/inventory/first_setup_inventory.ini` - Ansible inventory with fix
- `disaster-recovery/tmp-ipa-domain-down-part1.md` - IPA DR test documentation

## Notes
- This issue only manifests when FreeIPA is unavailable
- Normal operations with IPA running are unaffected (SSSD responds instantly)
- The fix is additive and doesn't break any existing functionality
- Consider adding this to all inventory files as a resilience measure
