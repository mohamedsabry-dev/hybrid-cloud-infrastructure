# Case 7: VLAN Gateway Not Responding to Ping via WireGuard

## Status: RESOLVED (workaround)
## Date: 2026-03-11
## Environment: Prod EC2 to VLAN 55 gateway
## Related: Case 5 (CGNAT), Case 6 (NAT Timeout), Case 8 (Wrong Tunnel)

---

## Symptoms
- Prod EC2 could ping hosts in VLAN 55 (10.0.55.x)
- Prod EC2 could NOT ping VLAN 55 gateway (10.0.55.1)
- Dev EC2 could ping both hosts and gateway in VLAN 65

## Investigation

```bash
# Works
ping 10.0.55.10   # Host in VLAN

# Fails
ping 10.0.55.1    # VLAN gateway interface
```

## Root Cause

ER605 firewall rules control traffic TO router's own interfaces differently than traffic THROUGH the router.

The ACL rules only covered traffic passing through:
- `vpn_prod → DataCenter_Cairo` (Allow)

But traffic destined TO the router's own VLAN interface (10.0.55.1) may have different rules.

## Workaround

Changed keepalive target from VLAN interface to tunnel peer IP:

```bash
# Old (didn't work for prod)
KEEPALIVE_TARGET="10.0.55.1"

# New (works - tunnel IP is in VPC range)
KEEPALIVE_TARGET="172.17.200.1"
```

Since tunnel IPs are now in VPC range, pinging the ER605 tunnel IP (172.17.200.1) serves the same keepalive purpose and is guaranteed to work.

## Note

This issue became moot after moving tunnel IPs into VPC range, as the keepalive target changed to the tunnel IP anyway.

---

## Commands Reference

```bash
# Test connectivity to VLAN host vs gateway
ping 10.0.55.10   # Host in VLAN
ping 10.0.55.1    # VLAN gateway

# Check tunnel IP (use this for keepalive instead)
ping 172.17.200.1  # ER605 tunnel IP
```
