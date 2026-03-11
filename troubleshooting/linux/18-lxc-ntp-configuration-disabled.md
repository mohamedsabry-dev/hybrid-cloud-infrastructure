# TS-002: LXC NTP Configuration Disabled

**Date:** 2026-03-05
**Environment:** DEV (lab.local)
**Affected Systems:** All LXC containers
**Status:** RESOLVED (by design)

---

## Symptom

NTP/Chronyd configuration fails or behaves inconsistently when joining LXC containers to FreeIPA domain.

---

## Root Cause

LXC containers **share the host kernel**, including the system clock. They cannot run their own time synchronization services independently.

| Type | Time Management |
|------|-----------------|
| **VMs** | Run their own kernel, chronyd works normally |
| **LXC** | Share Proxmox host kernel, inherit time from host |

When FreeIPA client enrollment tries to configure NTP on LXC containers, chronyd fails because:
1. LXC containers inherit time directly from Proxmox host
2. Systemd services like chronyd don't run properly in containers
3. Time sync must happen at the host level, not container level

---

## Solution

Disable NTP configuration during FreeIPA client enrollment.

**File:** `group_vars/all.yml`

```yaml
ipaclient_no_ntp: true                # Correct variable - skips NTP during enrollment
ipaclient_configure_ntp: false        # Also set for completeness
# ipaclient_ntp_servers:              # Must be commented out
#   - freeipa.lab.local
```

**Important:** The FreeIPA ansible role uses `ipaclient_no_ntp: true` (not `ipaclient_configure_ntp: false`) to actually skip NTP configuration.

---

## Proper NTP Architecture

```
Proxmox Host
    │
    ├── chronyd → External NTP servers (pool.ntp.org)
    │
    └── LXC Containers (inherit time automatically)
            │
            └── No NTP config needed
```

**TODO:** If NTP needs to be configured:
- **VMs:** Configure chronyd pointing to FreeIPA server or external NTP
- **LXC:** Skip NTP config (inherits from Proxmox host)
- **Proxmox Host:** Ensure host has proper NTP configuration

---

## Simple Explanation

LXC containers are like apartments in a building - they share the building's clock (host kernel). You can't set a different time in your apartment. VMs are like separate houses - each has its own clock that needs synchronization.

---

## References

- [LXC Container Limitations](https://linuxcontainers.org/lxc/introduction/)
- [FreeIPA Client NTP Options](https://freeipa.readthedocs.io/)
