# TS-IDN-008 | 2026-03-05 | RESOLVED

## 1. Context
- System: FreeIPA / LXC / Chronyd
- Environment: DEV (lab.local)
- Related components: FreeIPA client enrollment, all LXC containers
- **Related tickets:** [TS-LNX-002](../linux/2-lxc-chronyd-adjtimex-failure.md) - Chronyd adjtimex failure (same root cause, OS-level symptom)

## 2. Issue
- Symptom: NTP/Chronyd configuration fails or behaves inconsistently on LXC containers during FreeIPA domain join
- Error: Various - chronyd fails to start, time sync issues, ansible task failures

## 3. Analysis

**Check 1: How does time sync work on LXC vs VM?**

| Type | Time Management |
|------|-----------------|
| **VMs** | Run their own kernel, chronyd works normally |
| **LXC** | Share Proxmox host kernel, inherit time from host |

Finding: LXC containers share the host kernel including system clock.

**Check 2: What happens when FreeIPA tries to configure NTP on LXC?**
```bash
# FreeIPA client enrollment tries to start chronyd
systemctl start chronyd
# Fails with various errors (see TS-LNX-002)
```
Finding: chronyd cannot run in unprivileged LXC - requires `CAP_SYS_TIME` capability.

**Check 3: Where should time sync happen?**
```
Proxmox Host
    │
    ├── chronyd → External NTP servers (pool.ntp.org)
    │
    └── LXC Containers (inherit time automatically)
            │
            └── No NTP config needed
```
Finding: Time sync must happen at host level, not container level.

## 4. Root Cause
> LXC containers **share the host kernel**, including the system clock. They cannot run their own time synchronization services. When FreeIPA client enrollment tries to configure NTP, it fails because:
> 1. LXC containers inherit time directly from Proxmox host
> 2. Chronyd requires capabilities not available in unprivileged containers
> 3. Time sync must happen at the host level

**Analogy:** LXC containers are like apartments in a building - they share the building's clock (host kernel). You can't set a different time in your apartment. VMs are like separate houses - each has its own clock.

## 5. Solution
> Disable NTP configuration during FreeIPA client enrollment for LXC containers.

**Why this works:** LXC containers automatically inherit correct time from Proxmox host. No NTP needed inside container.

**File:** `ansible/dev/inventory/group_vars/all.yml`

**Location:** Ansible inventory configuration (applies to all hosts)

**Configuration:**
```yaml
ipaclient_no_ntp: true                # Correct variable - skips NTP during enrollment
ipaclient_configure_ntp: false        # Also set for completeness
# ipaclient_ntp_servers:              # Must be commented out
#   - freeipa.lab.local
```

**Important:** The FreeIPA ansible role uses `ipaclient_no_ntp: true` (not `ipaclient_configure_ntp: false`) to actually skip NTP configuration.

**Verification:**
```bash
# On LXC container - check time status
timedatectl
# System clock synchronized: yes
# NTP service: inactive (expected for LXC)

# On Proxmox host - verify chrony is running
systemctl status chrony
chronyc tracking
chronyc sources -v
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: If Proxmox host time drifts, all LXC containers will have wrong time. Ensure chrony is configured on Proxmox host.

## 7. Impact After Fix
- Observed: FreeIPA client enrollment succeeds without NTP errors
- LXC containers have correct time inherited from host
- No new issues caused

## 8. Notes

**Proper NTP architecture:**
- **Proxmox Host:** External NTP sources (no link between SVC and MGMT plane)
- **FreeIPA:** External NTP sources + serves as NTP for domain (allows 10.0.0.0/16)
- **LXC Containers:** Skip NTP config (inherits from Proxmox host)
- **VMs:** Can use FreeIPA as NTP source

**Time consistency:** Both Proxmox and FreeIPA use the same external NTP sources, ensuring consistent time across the environment.

**Evidence - Proxmox host config:**
```bash
root@pve-dev:~# cat /etc/chrony/chrony.conf
# Use Debian vendor zone.
pool 0.pool.ntp.org iburst
pool 1.pool.ntp.org iburst

server time.cloudflare.com iburst
```

**Evidence - FreeIPA config:**
```bash
[root@freeipa ~]# cat /etc/chrony.conf
##### Deploy Against FreeIPA #####
## Create As config ansible/dev/config_files/chrony_ipa.conf

# Use public NTP servers from the pool.ntp.org project.
# The 'iburst' option allows for faster initial synchronization.

# 1. Reliable secondary public sources (For redundancy)
pool 0.pool.ntp.org iburst
pool 1.pool.ntp.org iburst

# 2. Cloudflare
server time.cloudflare.com iburst

allow 10.0.0.0/16
```

**Commands reference:**
```bash
# Check time on LXC container
timedatectl
timedatectl show --property=Timezone

# Set timezone on container
timedatectl set-timezone Africa/Cairo

# Check NTP on Proxmox host
systemctl status chrony
chronyc tracking
chronyc sources -v
```

## 9. Workaround (if any)
> N/A - this IS the correct approach for LXC containers.

## References
- [LXC Container Limitations](https://linuxcontainers.org/lxc/introduction/)
- [FreeIPA Client NTP Options](https://freeipa.readthedocs.io/)
