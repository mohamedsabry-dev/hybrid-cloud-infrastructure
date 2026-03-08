# Troubleshooting: Static Route SSH Disconnect

## Case: ISP Router Static Route Causes SSH Disconnects

**Date:** 2026-02-12
**Status:** RESOLVED

---

## Environment

- Client: Mac Mini (192.168.0.223) on home network
- Router: ER605 WAN IP 192.168.0.175
- Target: Internal 10.x networks via ER605
- ISP Router: 192.168.0.1

---

## Goal

Allow Mac Mini to reach all internal 10.x networks through ER605 router.

---

## Failed Approach - ISP Router Static Route

Attempted to configure static route on ISP router:

| Setting             | Value                      |
|---------------------|----------------------------|
| Network Destination | 10.0.0.0                   |
| Subnet Mask         | 255.0.0.0                  |
| Default Gateway     | 192.168.0.175 (ER605 WAN)  |
| Interface           | LAN                        |

**Result:** SSH disconnects after ~30 seconds

**Issue:** Same issue encountered in POC-v1 with this router.
See: `poc-v1/troubleshooting/network/08-Static-Route-Loop-SSH-Disconnect.md`

---

## Working Approach - Local Static Route on Mac Mini

Configure the static route directly on the Mac Mini instead of the ISP router.

**Manual command:**
```bash
sudo route add -net 10.0.0.0/8 192.168.0.175
```

**Result:** Stable SSH connections

**Note:** Must be configured on each external device that needs access to internal 10.x networks.

---

## Persistent Route Setup (survives reboot)

**Scripts Location:** `foundation/mac-mini/`
- `com.local.route10.plist` - LaunchDaemon config
- `install-route.sh` - Installation script

**Install Command:**
```bash
cd foundation/mac-mini
sudo ./install-route.sh
```

**Files Installed:**
- `/usr/local/bin/add-route.sh` - Waits for network, adds route
- `/Library/LaunchDaemons/com.local.route10.plist` - Runs at boot

**How it works:** Runs at boot, pings ER605 to warm ARP, adds route

**Verify after reboot:**
```bash
netstat -rn | grep "^10"
# Should show: 10/8  192.168.0.175  UGSc  ...
```

---

## Key Takeaway

When ISP router static routes cause connection instability, configure the
static route locally on the client device instead. This avoids potential
routing loops or timing issues in consumer-grade ISP routers.
