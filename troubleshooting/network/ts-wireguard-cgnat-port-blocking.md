# Troubleshooting: CGNAT Port Blocking - Prod Tunnel Down

**Date**: March 2026
**Duration**: ~5 days downtime
**Affected**: prod_tunnel only (dev_tunnel working fine)
**Resolution**: Changed ER605 Listen Port from 51821 to 51830

---

## Symptoms

- prod_tunnel showing no handshake for ~5 days
- dev_tunnel working perfectly on port 51820
- ER605 WireGuard status:

```
| Interface    | Endpoint        | Port  | TX Bytes | RX Bytes | Last Handshake |
|--------------|-----------------|-------|----------|----------|----------------|
| prod_tunnel  | 18.169.91.239   | 51820 | 3.0 KiB  | 0 B      | ---            |
| dev_tunnel   | 98.91.157.127   | 51820 | 34.6 KiB | 34.4 KiB | 1 second ago   |
```

**Key observation**: TX bytes increasing but RX: 0 B = ER605 sending packets but receiving nothing back.

---

## Investigation Steps

### 1. Verified Keys Match

Compared public keys on both sides - confirmed matching, no changes made.

### 2. Checked Time Sync

Both AWS EC2 and ER605 times synchronized - ruled out handshake timing issues.

### 3. AWS EC2 tcpdump

```bash
sudo tcpdump -i enX0 udp port 51820 -n
```

**Output showed bidirectional traffic:**
```
19:41:08.361300 IP 172.17.65.73.51820 > 196.202.8.109.51821: UDP, length 148
19:41:13.896634 IP 172.17.65.73.51820 > 196.202.8.109.51821: UDP, length 148
19:41:16.075610 IP 196.202.8.109.51821 > 172.17.65.73.51820: UDP, length 148
19:41:16.075915 IP 172.17.65.73.51820 > 196.202.8.109.51821: UDP, length 92
19:41:21.290233 IP 196.202.8.109.51821 > 172.17.65.73.51820: UDP, length 148
19:41:21.290575 IP 172.17.65.73.51820 > 196.202.8.109.51821: UDP, length 92
...
```

**Analysis:**
- `196.202.8.109:51821 > 172.17.65.73:51820` = ER605 → AWS (148 bytes = handshake initiation)
- `172.17.65.73:51820 > 196.202.8.109:51821` = AWS → ER605 (92 bytes = handshake response)

**Conclusion**: AWS receiving packets AND sending responses. Problem is responses not reaching ER605.

### 4. Checked ISP Router Port Forwarding

Initial state: No port forwarding rules configured.

**Added port mapping:**
- Mapping Name: WireGuard_Prod
- Protocol: UDP
- External Port: 51821
- Internal Host: 192.168.100.175 (ER605)
- Internal Port: 51821

**Result**: Still not working.

### 5. Enabled DMZ

Set ER605 (192.168.100.175) as DMZ host to bypass all port restrictions.

**Result**: Still not working.

### 6. Discovered CGNAT

Checked ISP router routing table:

```
| Number | Destination IP | Subnet Mask     | Gateway        | Interface              |
|--------|----------------|-----------------|----------------|------------------------|
| 4      | 100.122.0.1    | 255.255.255.255 | 0.0.0.0        | 1_TR069_INTERNET_R_VID_10 |
```

**`100.122.0.1` is in CGNAT range (100.64.0.0/10)** - Confirms ISP uses Carrier-Grade NAT.

---

## Root Cause

**ISP blocks specific UDP ports at CGNAT level.**

- Port forwarding/DMZ on local ISP router doesn't help
- The real NAT happens at ISP level before traffic reaches user's router
- ISP was blocking port 51821 specifically
- Port 51820 (dev tunnel) was not blocked

**Why dev worked**: Both tunnels rely on ER605 initiating outbound to create NAT mapping. Dev's port 51820 wasn't blocked, so its NAT mapping worked.

---

## Solution

Changed ER605 prod_tunnel Listen Port:

**Before**: 51821
**After**: 51830

```
ER605 → VPN → WireGuard → prod_tunnel → Edit → Listen Port: 51830
```

**Handshake established immediately after change.**

AWS side required NO changes - it responds to whatever source port packets arrive from.

---

## Post-Resolution Cleanup

Removed unnecessary ISP router configurations (were only for testing):

1. Disabled DMZ
2. Deleted WireGuard_Prod port mapping rule

These are not needed when behind CGNAT since ER605 initiates outbound and PersistentKeepalive (25 sec) maintains the NAT mapping.

---

## Post-Fix Retest

After switching to 51830 and confirming it worked, tested reverting to 51821:

**Result**: Port 51821 worked smoothly with no issues.

**Possible explanations:**
1. Temporary ISP CGNAT issue that cleared during troubleshooting
2. Stale state on ER605 router (cannot confirm - ER605 CLI is very limited)
3. DMZ/port forwarding changes triggered something at ISP level

**Decision**: Keep port 51830 as a precaution in case 51821 gets blocked again.

---

## Lessons Learned

1. **CGNAT detection**: Check ISP router routing table for 100.64.0.0/10 addresses
2. **Port forwarding useless with CGNAT**: The real NAT is at ISP level
3. **tcpdump is essential**: Showed AWS was responding but packets not reaching ER605
4. **Port changes can help**: Even if not permanently blocked, changing ports can clear stale state
5. **ER605 limitations**: Poor CLI makes it hard to diagnose internal router state issues

---

## Updated Configuration

| Environment | ER605 Port | AWS Port |
|-------------|------------|----------|
| Dev         | 51820      | 51820    |
| Prod        | 51830      | 51820    |

---

## Files Updated

- `network/05-vpn-wireguard-config.txt` - Port and troubleshooting section
- `network/vpn-setup/wireguard-setup.md` - Port references and ISP router section
