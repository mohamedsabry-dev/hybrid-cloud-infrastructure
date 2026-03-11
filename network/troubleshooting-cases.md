# WireGuard Troubleshooting Cases

## Case 1: Wrong Tunnel Routing on ER605

### Date
2026-03-11

### Symptoms
- Prod internal hosts (10.0.5x.x) could not reach Prod AWS EC2 (172.17.x.x)
- Dev internal hosts could reach Dev AWS EC2 normally
- Prod EC2 could reach internal hosts, but internal could not initiate to Prod EC2

### Investigation

**Test from internal prod host (ansible on 10.0.53.x):**
```bash
[root@ansible ~]# ping 172.17.65.73
PING 172.17.65.73 (172.17.65.73) 56(84) bytes of data.
--- 172.17.65.73 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2030ms
```

**Traceroute revealed the issue:**
```bash
[root@ansible ~]# traceroute 172.17.65.73
traceroute to 172.17.65.73 (172.17.65.73), 30 hops max, 60 byte packets
 1  _gateway (10.0.53.1)  0.853 ms  0.914 ms  0.849 ms
 2  10.200.0.2 (10.200.0.2)  60.389 ms  60.371 ms  60.359 ms   <-- WRONG TUNNEL!
 3  * * *
 4  * * *
```

**Evidence:** Traffic to PROD AWS (172.17.x.x) was being routed through DEV tunnel (10.200.0.2) instead of PROD tunnel (10.200.1.2).

### Root Cause

ER605's WireGuard peer AllowedIPs field only accepts **ONE entry**.

Original tunnel IPs were in a separate range (10.200.x.x), requiring multiple AllowedIPs entries:
- Tunnel IP: 10.200.1.0/24
- VPC CIDR: 172.17.0.0/16

| AllowedIPs Setting | Result |
|--------------------|--------|
| `10.200.1.0/24` (tunnel only) | VPN→Internal works, Internal→VPN fails |
| `172.17.0.0/16` (VPC only) | Internal→VPN works, VPN→Internal fails |
| `0.0.0.0/0` (any) | ER605 picks ONE tunnel for ALL traffic |

With `0.0.0.0/0` on both peers, ER605 had no way to distinguish which tunnel to use for which destination, defaulting to dev_tunnel for everything.

### Solution

**Place tunnel IPs inside the AWS VPC CIDR range.**

| Environment | Old Tunnel IPs | New Tunnel IPs |
|-------------|----------------|----------------|
| Dev ER605 | 10.200.0.1 | 172.16.200.1 |
| Dev AWS | 10.200.0.2 | 172.16.200.2 |
| Prod ER605 | 10.200.1.1 | 172.17.200.1 |
| Prod AWS | 10.200.1.2 | 172.17.200.2 |

**New AllowedIPs (single entry covers everything):**
- dev_tunnel peer: `172.16.0.0/16` (covers tunnel 172.16.200.x + VPC 172.16.x.x)
- prod_tunnel peer: `172.17.0.0/16` (covers tunnel 172.17.200.x + VPC 172.17.x.x)

### Configuration Changes

**ER605 WireGuard Interface:**
```
dev_tunnel:  Local IP = 172.16.200.1
prod_tunnel: Local IP = 172.17.200.1
```

**ER605 WireGuard Peer:**
```
dev_tunnel peer:  AllowedIPs = 172.16.0.0/16
prod_tunnel peer: AllowedIPs = 172.17.0.0/16
```

**AWS EC2 WireGuard Config:**
```ini
# Dev
Address = 172.16.200.2/16

# Prod
Address = 172.17.200.2/16
```

### Verification

After fix, traceroute shows correct tunnel:
```bash
[root@ansible ~]# traceroute 172.17.65.73
traceroute to 172.17.65.73 (172.17.65.73), 30 hops max, 60 byte packets
 1  _gateway (10.0.53.1)  0.853 ms
 2  172.17.200.2  60.389 ms   <-- CORRECT! Prod tunnel
 3  172.17.65.73  61.234 ms
```

### Additional Benefit

This also solved **cross-tunnel reachability** - both tunnel endpoints can now ping each other since they're in routable VPC ranges.

---

## Case 2: ISP NAT Timeout Causing Tunnel Drops

### Date
2026-03-11

### Symptoms
- WireGuard tunnel worked initially
- After ~1 hour of idle time, tunnel stopped working
- No handshake, connection timeout
- Required manual restart on both sides

### Root Cause

ISP router was configured with **Port-Restricted Cone NAT** which:
1. Drops UDP mappings after inactivity timeout (~60 minutes)
2. Blocks incoming packets if no recent outgoing traffic
3. Causes WireGuard handshakes to fail after timeout

### Solution

**Part 1: Change ISP NAT Type**

Changed ISP router NAT type from "Port-restricted cone NAT" to **"Full Cone NAT"**

Full Cone NAT:
- Maintains UDP mappings longer
- Allows incoming packets from any source once mapping exists
- More permissive for VPN traffic

**Part 2: Keepalive Ping Service**

Created systemd service to send regular pings through tunnel, preventing NAT timeout:

```bash
sudo tee /etc/systemd/system/wg-keepalive.service << 'EOF'
[Unit]
Description=WireGuard Tunnel Keepalive Ping
After=network.target wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do ping -c 1 <TUNNEL_PEER_IP> > /dev/null 2>&1; sleep 5; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now wg-keepalive
```

**Keepalive Targets:**
- Dev EC2: ping `172.16.200.1` (ER605 dev tunnel IP)
- Prod EC2: ping `172.17.200.1` (ER605 prod tunnel IP)

**Ping Interval:** 5 seconds (aggressive to prevent any NAT timeout)

### ER605 Side Keepalive

ER605 also has **Persistent Keepalive = 25** seconds configured on each peer, which sends keepalive packets to AWS every 25 seconds.

### Service Parameters Explained

```ini
Restart=always     # Always restart service if it crashes
RestartSec=10      # Wait 10 seconds before restarting (prevents rapid restart loops)
sleep 5            # Ping interval - every 5 seconds
```

### Verification

```bash
# Check service status
sudo systemctl status wg-keepalive

# View keepalive logs
journalctl -u wg-keepalive -f

# Verify tunnel stays up
watch -n 60 'sudo wg show wg0 latest-handshakes'
```

### Result

Tunnel now survives:
- Extended idle periods
- EC2 reboots (service auto-starts)
- Network interruptions (service auto-restarts)

---

## Case 3: VLAN Interface Not Responding to Ping

### Date
2026-03-11

### Symptoms
- Prod EC2 could ping hosts in VLAN 55 (10.0.55.x)
- Prod EC2 could NOT ping VLAN 55 gateway (10.0.55.1)
- Dev EC2 could ping both hosts and gateway in VLAN 65

### Investigation

```bash
# Works
ping 10.0.55.10   # Host in VLAN

# Fails
ping 10.0.55.1    # VLAN gateway interface
```

### Root Cause

ER605 firewall rules control traffic TO router's own interfaces differently than traffic THROUGH the router.

The ACL rules only covered traffic passing through:
- `vpn_prod → DataCenter_Cairo` (Allow)

But traffic destined TO the router's own VLAN interface (10.0.55.1) may have different rules.

### Workaround

Changed keepalive target from VLAN interface to tunnel peer IP:

```bash
# Old (didn't work for prod)
KEEPALIVE_TARGET="10.0.55.1"

# New (works - tunnel IP is in VPC range)
KEEPALIVE_TARGET="172.17.200.1"
```

Since tunnel IPs are now in VPC range, pinging the ER605 tunnel IP (172.17.200.1) serves the same keepalive purpose and is guaranteed to work.

### Note

This issue became moot after moving tunnel IPs into VPC range, as the keepalive target changed to the tunnel IP anyway.
