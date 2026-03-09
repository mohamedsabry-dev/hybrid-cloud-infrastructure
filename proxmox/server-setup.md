# Proxmox Server Configuration

Reference for DEV and PROD Proxmox server setup and configuration.

---

## Scripts Reference

| Path | Purpose |
|------|---------|
| `proxmox/scripts/bootstrap-dev.sh` | DEV post-install bootstrap |
| `proxmox/scripts/bootstrap-prod.sh` | PROD post-install bootstrap |
| `proxmox/scripts/network-setup-dev.sh` | DEV network/VLAN configuration |
| `proxmox/scripts/network-setup-prod.sh` | PROD network/VLAN configuration |
| `proxmox/scripts/golden-vm-setup.sh` | Golden VM image setup (run inside VM) |
| `proxmox/scripts/golden-lxc-setup.sh` | Golden LXC template setup (run inside CT) |

---

## Initial Server Setup

### Phase 1: Proxmox Installation

During ISO installation, name network interfaces:

| Interface | Name | Purpose |
|-----------|------|---------|
| Main Ethernet | svc0 | Trunk port (all VLANs) |
| WiFi Adapter | (keep) | Record original name for scripts |
| USB-to-Ethernet | stor0 | Storage network (NAS access) |

> **Note:** DEV laptop has no internal Ethernet - use USB-C adapter as svc0.

### Phase 2: Bootstrap

After Proxmox install, connect to network and run:

```bash
scp proxmox/scripts/bootstrap-{env}.sh root@<proxmox-ip>:/tmp/
ssh root@<proxmox-ip>
chmod +x /tmp/bootstrap-{env}.sh
/tmp/bootstrap-{env}.sh
```

### Phase 3: Network Configuration

After bootstrap completes:

```bash
scp proxmox/scripts/network-setup-{env}.sh root@<proxmox-ip>:/tmp/
ssh root@<proxmox-ip>
chmod +x /tmp/network-setup-{env}.sh
/tmp/network-setup-{env}.sh
```

> **Note:** Update WiFi SSID/password in script if different from defaults.

---

## Golden Templates

### VM Golden Image (ID: 9000)

- **Created via:** `terraform/dev/proxmox/vms/golden-image/`
- **Setup script:** `proxmox/scripts/golden-vm-setup.sh` (run inside VM after OS install)
- **Convert to template:** `qm template 9000`

### LXC Golden Template (ID: 9001)

- **Created via:** `terraform/dev/proxmox/lxc/golden-template/`
- **Setup script:** `proxmox/scripts/golden-lxc-setup.sh` (run inside container)
- **Convert to template:** `pct template 9001`

---

## Server Details

| Environment | Hostname | Management IP | API URL |
|-------------|----------|---------------|---------|
| PROD | pve-prod.lab.local | 10.0.5.100 | https://pve-prod.lab.local:8006 |
| DEV | pve-dev.lab.local | 10.0.5.110 | https://pve-dev.lab.local:8006 |

