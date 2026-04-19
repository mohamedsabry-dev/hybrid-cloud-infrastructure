# Route Setup — 10.0.0.0/8 persistent route on Mac Mini

Local launchd-driven persistent route that lets the Mac Mini reach on-prem
10.x subnets via the gateway. Fallback path — normally the 10.0.0.0/8 route
lives on the MikroTik router; this folder holds the Mac-Mini-local version
for cases where the router can't hold it.

## Files

| File | Description |
|------|-------------|
| `route-setup-guide.txt` | Install / verify / uninstall commands |
| `add-route.sh` | Script to add the 10.0.0.0/8 route (called by launchd) |
| `install-route.sh` | Installer that registers the launchd service |
| `com.local.route10.plist` | launchd service definition (runs add-route.sh on boot) |

## How it fits together

`install-route.sh` copies `add-route.sh` to `/usr/local/bin/` and registers
`com.local.route10.plist` with launchd. On boot, launchd invokes the script,
which adds the 10.0.0.0/8 route through the configured gateway.

## Related

- [`route-setup-guide.txt`](route-setup-guide.txt) — commands
- [`../README.md`](../README.md) — workstation scope
- [`../../deployment-docs/network-setup-guide.txt`](../../deployment-docs/network-setup-guide.txt) — router-level routing
- [`../../network/DESIGN.md`](../../network/DESIGN.md) — MikroTik / ER605 migration reasoning
