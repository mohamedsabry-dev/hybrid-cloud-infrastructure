# TS: Wrong Tunnel Routing on ER605

## Date
2026-03-11

## Symptoms
- Prod internal hosts (10.0.5x.x) could not reach Prod AWS EC2 (172.17.x.x)
- Dev internal hosts could reach Dev AWS EC2 normally
- Prod EC2 could reach internal hosts, but internal could not initiate to Prod EC2

## Investigation

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

## Root Cause

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

## Solution

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

## Configuration Changes

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

## Verification

After fix, traceroute shows correct tunnel:
```bash
[root@ansible ~]# traceroute 172.17.65.73
traceroute to 172.17.65.73 (172.17.65.73), 30 hops max, 60 byte packets
 1  _gateway (10.0.53.1)  0.853 ms
 2  172.17.200.2  60.389 ms   <-- CORRECT! Prod tunnel
 3  172.17.65.73  61.234 ms
```

## Additional Benefit

This also solved **cross-tunnel reachability** - both tunnel endpoints can now ping each other since they're in routable VPC ranges.

## Status
RESOLVED
