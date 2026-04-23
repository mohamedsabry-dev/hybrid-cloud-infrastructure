# MikroTik L009UiGS-RM — Current primary router

Current router / firewall / WireGuard VPN endpoint for the lab. Replaced the TP-Link ER605 after TS-NET-003 / 004 / 005 exposed stability and maintainability issues, and after deciding the ER605's lack of diagnostic tooling was no longer acceptable for a project that is also a learning exercise. See [`../../README.md`](../../README.md) → "Why the network stack evolved" for the full story.

---

## Device info

| Property | Value |
|----------|-------|
| Model | MikroTik L009UiGS-RM |
| Role | Router / Firewall / WireGuard VPN endpoint |
| Management IP | 10.0.5.1 (moved from ER605, same address kept intentionally) |

---

## Configuration scripts

Configs are captured as RouterOS `.rsc` scripts so they live in this repo as text (diff-able, reviewable).

| File | Purpose |
|------|---------|
| `phase1-mgmt-access.rsc` | Initial management access via the ISP network (`192.168.100.195/24`). Run on a fresh or factory-reset device so I can reach it from my workstation before cutting the real config in. |
| `phase2-dev-services.rsc` | Dev services trunk on `ether6` (connects to FS308GP where the Dev Proxmox server terminates). Creates the `br-dev` bridge, VLANs 60-65, per-VLAN gateway IPs (`10.0.6x.1/24`). |

Further phases (prod services trunk on the other uplink, WireGuard tunnels, firewall ACLs) live in the device's running config and in `backups/`. Those will be split into additional numbered `.rsc` scripts as the setup is fully formalised — the two scripts above cover the core "get to management, then bring up the Dev fleet" path.

---

## Backups

| File | Description |
|------|-------------|
| `backups/backup-config-stable.backup` | Binary RouterOS backup (preserves everything including passwords and certs) |
| `backups/backup-config-stable.rsc` | Exportable text config — preferred for review since it is human-readable and diff-able |
| `backups/backup-after-acl-api-rules.backup` | Snapshot after adding ACL + API firewall rules |

> **`backups/` is gitignored.** The folder exists locally but is excluded from git (see `.gitignore` — `network/router/mikrotik/backups/**` and `*.bin`). RouterOS backups, even the text exports, can contain credentials, pre-shared keys, and WireGuard private keys. Keep both binary and text exports locally: binary is the reliable restore path, text is the readable review path — neither is safe to commit publicly.

---

## Related

- [`../../DESIGN.md`](../../DESIGN.md) — why MikroTik replaced the ER605
- [`../er605/`](../er605/) — retired router, kept as historical archive
- [`../../vpn/`](../../vpn/) — WireGuard setup (tunnels terminate on this MikroTik)
- [`../../../troubleshooting/network/`](../../../troubleshooting/network/) — TS-NET-003 / 004 / 005 (the incidents that drove this migration)
