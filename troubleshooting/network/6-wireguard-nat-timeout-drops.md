# TS: ISP NAT Timeout Causing Tunnel Drops

## Date
2026-03-11

## Symptoms
- WireGuard tunnel worked initially
- After ~1 hour of idle time, tunnel stopped working
- No handshake, connection timeout
- Required manual restart on both sides

## Root Cause

ISP router was configured with **Port-Restricted Cone NAT** which:
1. Drops UDP mappings after inactivity timeout (~60 minutes)
2. Blocks incoming packets if no recent outgoing traffic
3. Causes WireGuard handshakes to fail after timeout

## Solution

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

## ER605 Side Keepalive

ER605 also has **Persistent Keepalive = 25** seconds configured on each peer, which sends keepalive packets to AWS every 25 seconds.

## Service Parameters Explained

```ini
Restart=always     # Always restart service if it crashes
RestartSec=10      # Wait 10 seconds before restarting (prevents rapid restart loops)
sleep 5            # Ping interval - every 5 seconds
```

## Verification

```bash
# Check service status
sudo systemctl status wg-keepalive

# View keepalive logs
journalctl -u wg-keepalive -f

# Verify tunnel stays up
watch -n 60 'sudo wg show wg0 latest-handshakes'
```

## Result

Tunnel now survives:
- Extended idle periods
- EC2 reboots (service auto-starts)
- Network interruptions (service auto-restarts)

## Status
RESOLVED
