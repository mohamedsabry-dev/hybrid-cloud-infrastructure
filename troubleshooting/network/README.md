# Network Troubleshooting Cases

Documentation of network-level issues encountered in the hybrid cloud infrastructure.

---

## Cases

| # | File | Issue | Root Cause |
|---|------|-------|------------|
| 1 | [static-route-ssh-disconnect](1-static-route-ssh-disconnect.md) | SSH disconnects after ~30s via ISP router static route | ISP router routing loop, use local client route |
| 2 | [asymmetric-routing-ssh-wan-lan](2-asymmetric-routing-ssh-wan-lan.md) | SSH hangs from WAN to Proxmox (ping works) | Asymmetric routing - old IP on vmbr0 |
| 3 | [svc-network-instability-investigation](3-svc-network-instability-investigation.md) | SVC random hangs, network instability | USB-Ethernet driver binding (cdc_ncm vs ax88179_178a) |
| 4 | [wireguard-cgnat-port-blocking](4-wireguard-cgnat-port-blocking.md) | WireGuard prod tunnel down for 5 days | ISP CGNAT blocking port 51821 |
| 5 | [wireguard-tunnel-stability-investigation](5-wireguard-tunnel-stability-investigation.md) | WireGuard intermittent drops | ISP blocks AWS EIPs randomly - recreate EIP |

---

## Quick Reference

### Static Routing (Case 1)
- **Problem:** ISP router static route causes SSH disconnects
- **Fix:** Configure route locally on client: `sudo route add -net 10.0.0.0/8 192.168.0.175`

### Asymmetric Routing (Case 2)
- **Problem:** Ping works but SSH/TCP hangs from WAN
- **Fix:** Remove old IP from vmbr0, ensure single network path

### SVC Network Instability (Case 3)
- **Problem:** Random service hangs, link flapping
- **Fix:** Force correct USB-Ethernet driver: `ax88179_178a` not `cdc_ncm`
- **Detection:** `dmesg | grep -E "cdc_ncm|ax88179"`

### WireGuard CGNAT (Case 4)
- **Problem:** Tunnel TX but no RX behind CGNAT
- **Fix:** Change listen port to bypass ISP blocking

### WireGuard Stability (Case 5)
- **Problem:** Intermittent tunnel drops (ER605 and MikroTik)
- **TRUE Root Cause:** ISP blocks AWS EIPs randomly
- **Fix:**
  1. Try port change first
  2. If persists, recreate AWS Elastic IP
- **Prevention:** Keep AWS keepalive ping service running

---

## Environment

- **Routers:** ER605, MikroTik, ISP router behind CGNAT
- **VPN:** WireGuard site-to-site to AWS
- **AWS:** Dev and Prod EC2 instances with Elastic IPs

---

## Related Documentation

- `network/vpn/wireguard-setup-guide.txt` - Full VPN setup guide
- `network/vpn/wireguard-config.txt` - Quick reference config

