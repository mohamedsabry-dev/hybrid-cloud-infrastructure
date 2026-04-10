# TS-NET-004 | 2026-03 | RESOLVED

## 1. Context
- System: WireGuard VPN / CGNAT
- Environment: Prod WireGuard tunnel (ER605 → AWS)
- Related components: ER605, ISP Router, AWS EC2 Prod
- Duration: ~5 days downtime
- Related tickets: [TS-NET-005](5-wireguard-tunnel-stability-investigation.md) - WireGuard stability investigation

## 2. Issue
- Symptom: Prod WireGuard tunnel showing no handshake for ~5 days
- Dev tunnel working perfectly on same setup
- Error: TX bytes increasing but RX: 0 B (packets sent but nothing received back)

**WireGuard Status on ER605:**
```
| Interface    | Endpoint            | Port  | TX Bytes | RX Bytes | Last Handshake |
|--------------|---------------------|-------|----------|----------|----------------|
| prod_tunnel  | REDACTED_EIP_PROD   | 51820 | 3.0 KiB  | 0 B      | ---            |
| dev_tunnel   | REDACTED_EIP_DEV    | 51820 | 34.6 KiB | 34.4 KiB | 1 second ago   |
```

**Key observation:** TX bytes increasing but RX: 0 B = ER605 sending packets but receiving nothing back.

## 3. Analysis

**Check 1: Verified Keys Match**
```
Action: Compared public keys on both sides
```
Finding: Keys matching, no changes made ✓

---

**Check 2: Time Sync Verification**
```
Action: Checked NTP sync on both AWS EC2 and ER605
```
Finding: Times synchronized, ruled out handshake timing issues ✓

---

**Check 3: AWS EC2 tcpdump**
```bash
sudo tcpdump -i enX0 udp port 51820 -n
```
**Output showed bidirectional traffic:**
```
19:41:08.361300 IP 172.17.65.73.51820 > REDACTED_ISP_PUBLIC.51821: UDP, length 148
19:41:13.896634 IP 172.17.65.73.51820 > REDACTED_ISP_PUBLIC.51821: UDP, length 148
19:41:16.075610 IP REDACTED_ISP_PUBLIC.51821 > 172.17.65.73.51820: UDP, length 148
19:41:16.075915 IP 172.17.65.73.51820 > REDACTED_ISP_PUBLIC.51821: UDP, length 92
19:41:21.290233 IP REDACTED_ISP_PUBLIC.51821 > 172.17.65.73.51820: UDP, length 148
19:41:21.290575 IP 172.17.65.73.51820 > REDACTED_ISP_PUBLIC.51821: UDP, length 92
```

**Analysis:**
- `REDACTED_ISP_PUBLIC:51821 > 172.17.65.73:51820` = ER605 → AWS (148 bytes = handshake initiation)
- `172.17.65.73:51820 > REDACTED_ISP_PUBLIC:51821` = AWS → ER605 (92 bytes = handshake response)

Finding: AWS receiving packets AND sending responses. Responses NOT reaching ER605. ✓

---

**Check 4: ISP Router Port Forwarding**
```
Initial state: No port forwarding rules configured

Added port mapping:
- Mapping Name: WireGuard_Prod
- Protocol: UDP
- External Port: 51821
- Internal Host: 192.168.100.175 (ER605)
- Internal Port: 51821
```
Finding: Still not working ✗

---

**Check 5: DMZ Configuration**
```
Action: Set ER605 (192.168.100.175) as DMZ host to bypass all port restrictions
```
Finding: Still not working ✗

---

**Check 6: CGNAT Discovery**

Checked ISP router routing table:
```
| Number | Destination IP | Subnet Mask     | Gateway | Interface                  |
|--------|----------------|-----------------|---------|----------------------------|
| 4      | 100.122.0.1    | 255.255.255.255 | 0.0.0.0 | 1_TR069_INTERNET_R_VID_10  |
```

Finding: **`100.122.0.1` is in CGNAT range (100.64.0.0/10)** - Confirms ISP uses Carrier-Grade NAT. ✓

## 4. Root Cause
> ISP blocks specific UDP ports at CGNAT level. Port forwarding/DMZ on local ISP router doesn't help because the real NAT happens at ISP level before traffic reaches user's router. ISP was blocking port 51821 specifically while port 51820 (dev tunnel) was not blocked.

**Why dev worked:** Both tunnels rely on ER605 initiating outbound to create NAT mapping. Dev's port 51820 wasn't blocked at CGNAT, so its NAT mapping worked.

## 5. Solution
> Change ER605 prod_tunnel Listen Port to avoid blocked port.

**Port Change:**
```
Before: 51821
After:  51830

ER605 → VPN → WireGuard → prod_tunnel → Edit → Listen Port: 51830
```

**Result:** Handshake established immediately after change.

**AWS side:** No changes required - AWS responds to whatever source port packets arrive from.

**Post-Resolution Cleanup:**
```
1. Disabled DMZ on ISP router
2. Deleted WireGuard_Prod port mapping rule
```
These are not needed when behind CGNAT since ER605 initiates outbound and PersistentKeepalive (25 sec) maintains the NAT mapping.

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - just using different port number

## 7. Impact After Fix
- Observed: Prod tunnel handshake established immediately
- Tunnel stable after port change
- No additional configuration needed on AWS side

**Post-Fix Retest:**
After switching to 51830 and confirming it worked, tested reverting to 51821:
- Result: Port 51821 worked smoothly with no issues

**Possible explanations:**
1. Temporary ISP CGNAT issue that cleared during troubleshooting
2. Stale state on ER605 router (cannot confirm - ER605 CLI is very limited)
3. DMZ/port forwarding changes triggered something at ISP level

**Decision:** Keep port 51830 as a precaution in case 51821 gets blocked again.

## 8. Notes

**Updated Configuration:**
| Environment | ER605 Port | AWS Port |
|-------------|------------|----------|
| Dev         | 51820      | 51820    |
| Prod        | 51830      | 51820    |

**CGNAT Detection Method:**
Check ISP router routing table for addresses in 100.64.0.0/10 range.

**Key Takeaways:**
1. Port forwarding/DMZ useless with CGNAT - real NAT is at ISP level
2. tcpdump is essential - showed AWS was responding but packets not reaching ER605
3. Port changes can help clear stale state even if not permanently blocked
4. ER605 limitations - poor CLI makes it hard to diagnose internal router state issues

**References:**
- `network/vpn/wireguard-setup.md` - Full VPN setup documentation
- `network/vpn/wireguard-config.txt` - Quick reference configuration

## 9. Workaround (if any)
> Change to a different UDP port (51830) to bypass ISP port blocking at CGNAT level.

