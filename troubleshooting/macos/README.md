# macOS Troubleshooting Cases

Documentation of issues encountered on macOS workstation used for development and GitHub Actions runner.

---

## Cases

| # | File | Issue | Root Cause |
|---|------|-------|------------|
| 1 | [macos-local-network-permission](1-macos-local-network-permission.md) | Third-party apps can't reach local network | macOS Local Network privacy permission |
| 2 | [macos-persistent-route](reference/2-macos-persistent-route.md) | Routes lost after reboot | Need LaunchDaemon for persistent routes |

---

## Quick Reference

### Local Network Permission
- **Case 1:** System Settings > Privacy & Security > Local Network → enable apps

### Persistent Routes
- **Case 2:** Use LaunchDaemon with `/usr/local/bin/add-route.sh`

```bash
# Quick check route
netstat -rn | grep "^10"

# Expected
10    192.168.0.175    UGSc    en1
```

---

## Environment

- **Device:** Mac Mini
- **OS:** macOS Monterey+
- **Role:** GitHub local runner, development workstation
- **Network:** 192.168.0.x (home LAN) → routes to 10.0.0.0/8 (internal VLANs)

---

## Related Files

- `workstation/add-route.sh` - Route script
- `workstation/com.local.route10.plist` - LaunchDaemon
- `workstation/install-route.sh` - Installer
