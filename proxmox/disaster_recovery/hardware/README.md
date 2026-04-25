# Hardware DR

Runbooks for replacing physical hardware on the Proxmox hosts without losing
interface-to-role mapping.

On laptop-Proxmox hosts, the service VLAN trunk and storage VLAN both live
on USB-Ethernet adapters. Replacing an adapter changes its MAC → the
systemd `.link` files that map MAC to interface name (`svc0`, `stor0`) need
updating in the right order so the bridges come back up correctly.

## Files

| File | Purpose |
|------|---------|
| `usb-ethernet-adapter-replacement-guide.txt` | Full replacement runbook: MAC mapping model, which files to edit, safe order to replace dev vs prod, verification |

## Related

- [`../README.md`](../README.md) — parent DR scope
- [`../../bootstrap_proxmox/vmbr1-vlan40-setup.txt`](../../bootstrap_proxmox/vmbr1-vlan40-setup.txt) — storage-VLAN bridge setup (reference for stor0 mapping)
- `../../../troubleshooting/network/3-svc-network-instability-investigation.md` — the TS case that motivated writing this runbook
