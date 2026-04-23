# Network Infrastructure - Setup Guide

Note: If you face issues during deployment, check the troubleshooting/ folder
for the related technology section. Most common issues have been documented there.
Relevant folder: troubleshooting/network/

For more details, see: network/README.md, network/ip-planning.txt, network/topology.txt

---

## Overview

This guide covers the physical network infrastructure connecting on-premises
lab servers to support isolated Dev and Prod environments with shared storage.

Domain: lab.local
DNS: FreeIPA (per environment)

---

### A note for anyone implementing this

Some of the specifics in this guide are choices that were forced on me by my
own hardware and ISP, not architectural requirements. If you are implementing
this yourself you do not need to copy them unless you also hit the same
issues. The specifics worth calling out:

- **Service VLANs going directly from each Proxmox server's svc0 to the
  router**, bypassing the switch. This was NOT the original plan. I pushed
  service VLANs through the switch initially and only switched to direct-
  to-router after the instability documented in TS-NET-003 — the USB-
  ethernet adapters on my Proxmox servers would not hold a stable link
  through the switch at gigabit. If your physical NICs / cables are stable,
  you can keep service VLANs on the switch like a normal deployment.
- **SVC ports forced to 100M** (not gigabit). Same root cause as above —
  dropping to 100M stabilised the link on my USB adapters. A native PCIe
  NIC doesn't need this.
- **ER605 → MikroTik router migration** — this happened in my setup for
  reasons captured in network/README.md. A greenfield deployment can start
  directly on whichever router you prefer; no migration needed.
- **Per-tunnel listen port split (prod on 51830 instead of 51820)** — driven
  by TS-NET-004 (CGNAT port blocking at my specific ISP). Not a general
  requirement; pick one port unless you hit the same block.

These are accepted drifts from the "clean" design, documented so my future
self knows why, and so any implementer knows what is optional baggage vs.
what is part of the actual architecture.

---

## Network Components

| Component        | Model              | Purpose                          |
|------------------|--------------------|----------------------------------|
| Router           | MikroTik L009UiGS-RM | Firewall, Gateway, VLAN routing |
| Switch           | Festa FS308GP      | Storage VLAN only (L2)           |
| Access Point     | TP-Link AC750      | WiFi management network          |
| NAS              | ASUSTOR FS6706T    | NFS storage server               |

---

## Physical Topology

```
ISP ONT
    │
    └── MikroTik Router
        │
        ├── Port 1 ─── ISP Direct Connection (WAN)
        │
        ├── Port 5 ─── Prod Server svc0 (DIRECT) ─── VLANs 50-55 trunk
        │
        ├── Port 6 ─── Dev Server svc0 (DIRECT) ─── VLANs 60-65 trunk
        │
        └── Port 7 ─── AC750 Access Point (VLAN 5 untagged)
                           │
                           ├── NAS Management Port (downlink, VLAN 5)
                           │
                           └── WiFi SSID: unified_mgmt
                               ├── Prod Server WiFi (10.0.5.100)
                               └── Dev Server WiFi (10.0.5.110)

FS308GP Switch (Storage Network ONLY - Isolated L2)
    │
    ├── Port 1 ─── ISP (for Festa Cloud management)
    ├── Port 6 ─── NAS LAN 1 (10.0.40.120) ─── VLAN 40 tagged
    ├── Port 7 ─── Dev Server stor0 (10.0.40.110) ─── VLAN 40 tagged
    └── Port 8 ─── Prod Server stor0 (10.0.40.100) ─── VLAN 40 tagged

Note: Switch ports 2-5 are NOT used. Service VLANs bypass the switch
      and connect directly from servers to router.
```

---

## Why I bypass the switch for service VLANs

The "clean" topology would push both service VLAN trunks (dev and prod)
through the switch like any normal deployment. I started there. I moved
away from it because of a long and painful instability I hit on the Dev
side — dev VMs cyclically losing gateway connectivity, with the link
flapping every 2-30 seconds on the trunk between the switch and the Dev
Proxmox server.

Full investigation is in
troubleshooting/network/3-svc-network-instability-investigation.md
(TS-NET-003) — six days, four phases. Initially I blamed a Port 4 gigabit-
negotiation defect on the ER605 router, then a port issue on the switch.
Neither turned out to be the actual root cause. The real problem was in
the USB-ethernet adapters on the Proxmox host; their negotiation behaviour
at gigabit through the switch was unreliable for me.

What I settled on:

- Each Proxmox server's svc0 interface goes DIRECTLY to a dedicated router
  port, not through the switch. This kept the adapter happy against a known
  stable peer (the router).
- The switch is kept in service but only for the isolated storage network
  (VLAN 40).
- Fewer switch hops in the critical path = fewer places the instability
  could reassert itself.

Trade-off: router ports become the scaling limit for new Proxmox servers.
Fine for a two-server lab; a bigger fleet would need a more reliable NIC
stack on the server side and the switch put back in the middle.

---

## Router Port Assignments (MikroTik)

| Port   | Connection              | VLAN Config           | Speed     |
|--------|-------------------------|-----------------------|-----------|
| Port 1 | ISP ONT                 | WAN                   | Auto      |
| Port 5 | Prod Server svc0        | Tagged 50-55          | 100M      |
| Port 6 | Dev Server svc0         | Tagged 60-65          | 100M      |
| Port 7 | AC750 AP                | Untagged VLAN 5       | Auto      |

Note: SVC ports forced to 100M, not gigabit. This is not a general
recommendation — it is specific to the USB-ethernet adapter behaviour I
hit on my Proxmox servers during TS-NET-003. Forcing 100M was the final
piece that stabilised the link after the direct-to-router wiring change.
A native PCIe NIC would not need this.

For router configuration, see: network/router/mikrotik/

---

## Switch Port Assignments (FS308GP)

The switch is ONLY used for storage network (VLAN 40):

| Port   | Profile   | Connection              | VLANs      |
|--------|-----------|-------------------------|------------|
| Port 1 | LAN       | ISP (Festa Cloud Mgmt)  | VLAN 1     |
| Port 6 | Storage   | NAS (LAN 1)             | Tagged 40  |
| Port 7 | Storage   | Dev Server (stor0)      | Tagged 40  |
| Port 8 | Storage   | Prod Server (stor0)     | Tagged 40  |

Ports 2-5: NOT USED (previously for service VLANs, now bypassed)

For switch configuration, see: network/switch/fs308gp/config.txt

---

## Access Point Configuration

| Setting         | Value                  |
|-----------------|------------------------|
| Device          | TP-Link AC750          |
| Mode            | Access Point (Bridge)  |
| IP Address      | 10.0.5.10              |
| SSID            | unified_mgmt           |
| Security        | WPA2-PSK [AES]         |
| AP Isolation    | ENABLED                |
| Uplink          | Router Port 7 (VLAN 5) |

Connections:
- Uplink to MikroTik router Port 7 (VLAN 5 untagged)
- Downlink from NAS management port (VLAN 5 untagged)
- Both servers connect via WiFi for management

AP Isolation blocks direct WiFi client-to-client traffic for security.

For AP configuration, see: network/ap/ac750/config.txt

---

## VLAN Summary

| VLAN | Subnet        | Purpose                  | Environment |
|------|---------------|--------------------------|-------------|
| 5    | 10.0.5.0/24   | Management (WiFi)        | Shared      |
| 40   | 10.0.40.0/24  | Storage (NFS)            | Shared      |
| 50   | 10.0.50.0/24  | Identity (FreeIPA)       | Prod        |
| 51   | 10.0.51.0/24  | K8s Control Plane        | Prod        |
| 52   | 10.0.52.0/24  | Vault Cluster            | Prod        |
| 53   | 10.0.53.0/24  | Management (Ansible)     | Prod        |
| 54   | 10.0.54.0/24  | K8s Data Plane           | Prod        |
| 55   | 10.0.55.0/24  | DMZ (NGINX)              | Prod        |
| 60   | 10.0.60.0/24  | Identity (FreeIPA)       | Dev         |
| 61   | 10.0.61.0/24  | K8s Control Plane        | Dev         |
| 62   | 10.0.62.0/24  | Vault Cluster            | Dev         |
| 63   | 10.0.63.0/24  | Management (Ansible)     | Dev         |
| 64   | 10.0.64.0/24  | K8s Data Plane           | Dev         |
| 65   | 10.0.65.0/24  | DMZ (NGINX)              | Dev         |

---

## Environment Isolation

### Network Isolation

- Prod VLANs (50-55) and Dev VLANs (60-65) are completely separated
- Cross-environment traffic blocked at router firewall
- Each environment has its own FreeIPA DNS server

### Storage Isolation

- VLAN 40 is L2-isolated on the switch (no router routing)
- NAS, Prod stor0, and Dev stor0 communicate directly
- Storage traffic never touches the router

### WiFi Isolation

- AP Isolation enabled - WiFi clients cannot reach each other
- Prod (10.0.5.100) and Dev (10.0.5.110) cannot communicate directly via WiFi
- All inter-server traffic must go through router

---

## Server Network Interfaces (Proxmox)

Each server has 3 network paths:

| Interface | IP (Dev)     | IP (Prod)    | Connection           | Purpose              |
|-----------|--------------|--------------|----------------------|----------------------|
| WiFi      | 10.0.5.110   | 10.0.5.100   | AP via router port 7 | Management           |
| svc0      | -            | -            | Direct to router     | VM service trunk     |
| stor0     | 10.0.40.110  | 10.0.40.100  | Switch VLAN 40       | NAS storage access   |

---

## Management Access

| Device       | IP Address      | Access Method          |
|--------------|-----------------|------------------------|
| Router       | 10.0.5.1        | Web UI, SSH            |
| Switch       | 192.168.100.185 | Festa Cloud Controller |
| AP           | 10.0.5.10       | Web UI                 |
| Prod Proxmox | 10.0.5.100      | Web UI :8006, SSH      |
| Dev Proxmox  | 10.0.5.110      | Web UI :8006, SSH      |
| NAS          | 10.0.5.120      | Web UI :8001           |

---

## Key Infrastructure IPs

| Component      | Prod IP       | Dev IP        |
|----------------|---------------|---------------|
| FreeIPA        | 10.0.50.10    | 10.0.60.10    |
| Ansible        | 10.0.53.10    | 10.0.63.10    |
| Local Runner   | 10.0.53.20    | 10.0.63.20    |
| Vault Cluster  | 10.0.52.10-12 | 10.0.62.10-12 |
| K8s Masters    | 10.0.51.10-12 | 10.0.61.10-12 |
| K8s Workers    | 10.0.54.10-12 | 10.0.64.10-12 |
| K8s API VIP    | 10.0.51.100   | 10.0.61.100   |
| Vault VIP      | 10.0.52.100   | 10.0.62.100   |
| NGINX          | 10.0.55.10    | 10.0.65.10    |

---

## VPN Setup

WireGuard VPN connects on-premises to AWS VPCs. Tunnels terminate on the
MikroTik router.

| Tunnel       | Local Endpoint | AWS Endpoint    | Purpose            |
|--------------|----------------|-----------------|---------------------|
| dev_tunnel   | 172.16.200.1   | 172.16.200.2    | On-prem ↔ AWS Dev   |
| prod_tunnel  | 172.17.200.1   | 172.17.200.2    | On-prem ↔ AWS Prod  |

Full setup (AWS EC2 side config, on-prem peer config, keepalive service,
CGNAT workaround, AllowedIPs reasoning, TS references) is documented in:

    network/vpn/wireguard-setup-guide.txt

The per-device configs live in:

    network/vpn/                   (AWS side + setup-wireguard.sh)
    network/router/mikrotik/       (on-prem side config + backups)

---

## Summary - File Reference

| Component                | Path                                    |
|--------------------------|-----------------------------------------|
| Network README           | network/README.md                       |
| IP Planning              | network/ip-planning.txt                 |
| Topology                 | network/topology.txt                    |
| Router Config            | network/router/mikrotik/                |
| Switch Config            | network/switch/fs308gp/config.txt       |
| AP Config                | network/ap/ac750/config.txt             |
| VPN Setup                | network/vpn/                            |
| Router Backups           | network/router/mikrotik/backups/        |
| Switch Backups           | network/switch/fs308gp/backups/         |

---

## Troubleshooting Reference

Key network troubleshooting cases, all under troubleshooting/network/:

| TS case | File | Summary |
|---------|------|---------|
| TS-NET-001 | 1-static-route-ssh-disconnect.md | SSH disconnect triggered by static route change |
| TS-NET-002 | 2-asymmetric-routing-ssh-wan-lan.md | Asymmetric routing on SSH between WAN and LAN |
| TS-NET-003 | 3-svc-network-instability-investigation.md | Service VLAN link flapping investigation — 4 phases, ended in "direct svc0 → router" wiring and 100M forced speed. Also contains the ER605 "Port 4 defect" false lead. |
| TS-NET-004 | 4-wireguard-cgnat-port-blocking.md | Prod WireGuard tunnel blocked by ISP CGNAT on UDP 51820; resolved by moving on-prem listen port to 51830. |
| TS-NET-005 | 5-wireguard-tunnel-stability-investigation.md | Four-phase WireGuard tunnel stability investigation; ended with prod compute/network migration to us-east-1 and ER605 → MikroTik router replacement. |

The ER605 → MikroTik migration story is in network/README.md.

---

## Deployment Order

Network setup is typically done first, before any other infrastructure:

0. Network Setup (this guide) - Physical network configuration
1. Proxmox Setup (see proxmox-setup-guide.txt)
2. AWS Bootstrap (see aws-bootstrap-setup-guide.txt)
3. GitHub Setup (see github-setup-guide.txt)
4. AWS Secrets (see aws-secrets-setup-guide.txt)
5. Ansible + Local Runner (see ansible-runner-setup-guide.txt)
6. FreeIPA (see freeipa-initial-setup-guide.txt)
7. Vault (see vault-initial-setup-guide.txt)
8. Kubernetes (see k8s-initial-setup-guide.txt)

---
