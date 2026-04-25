# TP-Link ER605 — Historical archive

> **Status:** Retired. Replaced by the MikroTik L009UiGS-RM.
> See [`../../README.md`](../../README.md) → "Why the network stack evolved" for the full story.

This folder records the previous router state — kept as reference, not as something to deploy against. Useful if you are reading the TS cases that reference the ER605 (TS-NET-003 / 004 / 005) and want to see the configuration that was in place at the time.

---

## Contents

| Path | Description | In git? |
|------|-------------|---------|
| `config.txt` | ER605 configuration as it was at retirement | Yes |
| `backups/*.bin` | Binary config backups from the ER605 era | No — gitignored (`.bin` pattern catches them; they contain credentials and VPN keys) |
| `docs/*.pdf` | Official TP-Link manuals | No — gitignored (vendor material) |

> `backups/` and `docs/` exist on disk locally but are excluded from git via `.gitignore`. Backups are retained in case I ever need to restore the device for TS reference; they are not safe to commit publicly because TP-Link `.bin` exports embed administrator credentials and PSKs.

---

## Device info (historical)

| Property | Value |
|----------|-------|
| Model | ER605 v2 |
| Firmware | 2.2.0 |
| Former Management IP | 10.0.5.1 (now used by the MikroTik replacement) |
| Former role | Router / Firewall / WireGuard VPN Gateway |

---

## Port assignments (historical)

| Port | Connection | Purpose |
|------|------------|---------|
| WAN | ISP ONT | Internet uplink |
| Port 3 | AC750 AP | WiFi Management (VLAN 5) |
| Port 2 | FS308GP | Dev Services Trunk — cable moved here from Port 4 under the suspected "Port 4 defect" theory, which later turned out to be a false trail (see TS-NET-003) |
| Port 4 | UNUSED | Originally the Dev trunk, left vacant after the cable move; not actually defective |
| Port 5 | FS308GP | Prod Services Trunk |

---

This folder is kept because TS-NET-003/004/005 reference the ER605 by
name — readers checking those incidents need the device context.
See [`../../DESIGN.md`](../../DESIGN.md) for the full migration story.
