# Troubleshooting: macOS Local Network Permission

## Case: Apps Unable to Reach Proxmox Server on Local Network

**Date:** 2026-02-04
**Status:** RESOLVED

---

## Environment

- Client: Mac Mini (192.168.0.##) connected via Ethernet to home router
- Server: Proxmox (192.168.0.## / pve.lab.local) on same LAN
- Mac used as: GitHub local runner, internal network config, development

---

## Symptoms

| Application | Behavior |
|-------------|----------|
| Native Terminal.app | ping to 192.168.0.## works |
| Safari | Proxmox web UI (port 8006) loads fine |
| Google Chrome | "unreachable address" |
| VS Code terminal | "no route to host" |
| GitHub Actions runner | "unreachable" |

---

## Root Cause

macOS "Local Network" privacy permission (introduced in macOS Monterey).

Third-party apps require explicit permission to access local network devices.
Native system apps (Terminal.app, Safari) are automatically allowed, but
apps like Chrome, VS Code, and Node.js (GitHub runner) are not.

---

## Resolution

1. Open **System Settings > Privacy & Security > Local Network**
2. Enable (toggle ON) the following apps:
   - Google Chrome
   - Visual Studio Code
   - Node.js (covers GitHub Actions runner)
3. Restart affected apps/services to pick up the new permissions

---

## Key Takeaway

When some apps can reach a local device but others cannot on macOS,
check Local Network permissions first before investigating firewall
or routing issues.
