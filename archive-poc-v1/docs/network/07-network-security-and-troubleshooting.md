# Network Security and Troubleshooting

> **Security best practices and common network issue resolution**

---

## Network Security Best Practices

### Segmentation

**Current Implementation:**
- WAN network isolated from internal network (pfSense gateway)
- vMotion traffic on dedicated network (no VM access)
- Management traffic separated from production traffic

**Benefits:**
- Limits blast radius of security breaches
- Prevents lateral movement between network tiers
- Isolates critical operations (vMotion) from user traffic

### Firewall Rules

**Current Rules:**
- Web UI access restricted to authorized IPs
- Default deny on WAN interface
- Granular rules for LAN egress (future)

**Best Practices:**
- Start with default deny
- Add specific allow rules as needed
- Document each firewall rule purpose
- Review rules quarterly

### Access Control

**Current Controls:**
- pfSense accessible only from Mac PC on WAN
- Windows Host uses LAN interface (10.0.20.170)
- Internal VMs cannot directly access WAN network

**Future Enhancements:**
- Multi-factor authentication for pfSense web UI
- Certificate-based access for management interfaces
- Separate admin network for infrastructure management

---

## Nested Virtualization Security

### Promiscuous Mode Requirements

**ESXi Master vSwitch_Internal:**
- Promiscuous Mode: **ON**
- Forged Transmits: **ON**
- MAC Address Changes: **ON**

**ESXi Nested (Production/DR):**
- Promiscuous Mode: **OFF** (not needed inside nested)
- Forged Transmits: **OFF**
- MAC Address Changes: **OFF**

### Why These Settings Are Required

**Promiscuous Mode:**
- Allows vSwitch to forward ALL packets to VMs
- Nested ESXi needs to receive traffic for nested VMs with different MACs
- **Without this**: Nested VMs completely isolated (no network connectivity)

**Forged Transmits:**
- Allows VMs to send packets with different source MAC addresses
- Nested ESXi forwards traffic on behalf of nested VMs
- Uses nested VM MAC, not ESXi host MAC
- **Without this**: Outbound traffic from nested VMs blocked

**MAC Address Changes:**
- Allows VMs to change MAC at runtime
- Required for vMotion and network failover
- **Without this**: VM migration fails

### Security Considerations

**Risk of Promiscuous Mode:**
- VMs can potentially see ALL traffic on vSwitch
- Mitigated by: Nested VMs run on isolated internal network (10.0.20.x)
- No sensitive traffic from external sources on this network

**Acceptable for Home Lab:**
- Trusted environment (no untrusted VMs)
- Required for nested virtualization
- Isolated from external networks

**Not Acceptable for Production (External Hosting):**
- Security risk in multi-tenant environments
- Consider bare-metal hypervisors instead of nested

---

## Troubleshooting Common Network Issues

### Issue 1: Nested VMs Have No Network Connectivity

**Symptoms:**
- Nested ESXi VMs completely isolated
- Cannot ping gateway (10.0.20.170)
- No internet access
- ESXi management accessible, but VMs are not

**Cause:**
Promiscuous mode, forged transmits, or MAC changes disabled on ESXi Master vSwitch.

**Solution:**
Enable all three security policies on ESXi Master vSwitch_Internal.

**Step-by-Step Fix:**
1. Connect to ESXi Master web UI
2. Navigate to: Networking > Virtual switches > vSwitch_Internal
3. Edit Settings > Security
4. Set all to "Accept":
   - Promiscuous mode: Accept
   - Forged transmits: Accept
   - MAC address changes: Accept
5. Save changes
6. Test connectivity from nested VM

**Reference**: [04-promiscuous-mode-nested.md](../../troubleshooting/network/04-promiscuous-mode-nested.md)

---

### Issue 2: Duplicate Packets / Network Loop

**Symptoms:**
- Ping shows 3 duplicate responses per request
- High network latency
- Cross-host traffic looping

**Cause:**
Active/Standby uplink redundancy with promiscuous mode creates loop.

**Solution:**
Enable Reverse Path Forwarding (RPF) check on ESXi Master.

```bash
# SSH to ESXi Master
esxcli system settings advanced set -o /Net/ReversePathFwdCheckPromisc -i 1

# Verify setting
esxcli system settings advanced list -o /Net/ReversePathFwdCheckPromisc
```

**Expected Output:**
```
Path: /Net/ReversePathFwdCheckPromisc
Type: integer
Int Value: 1
```

**Reference**: [05-duplicate-packets-loop.md](../../troubleshooting/network/05-duplicate-packets-loop.md)

---

### Issue 3: SSH Disconnects Randomly

**Symptoms:**
- SSH sessions disconnect after 30-60 seconds
- Intermittent connectivity
- traceroute shows routing loop

**Cause:**
Static route configured on BOTH physical router AND client laptop.

**Incorrect Configuration:**
```
Physical Router: Route to 10.0.20.0/24 via 192.x.x.## (pfSense)
Client Laptop: Route to 10.0.20.0/24 via 192.x.x.## (pfSense)

Result: Routing loop, packets bouncing between router and client
```

**Solution:**
Configure static route on client ONLY, NOT on physical router.

**Correct Configuration:**
```
Physical Router: No static route (let client handle it)
Client Laptop (Mac): Route to 10.0.20.0/24 via 192.x.x.## (pfSense)
```

**Mac OS Static Route:**
```bash
# Add route
sudo route add -net 10.0.20.0/24 192.x.x.##

# Make persistent (add to /etc/rc.local or use launch daemon)
```

**Reference**: [08-static-route-loop-ssh-disconnect.md](../../troubleshooting/network/08-static-route-loop-ssh-disconnect.md)

---

### Issue 4: VMs Cannot Reach Internet

**Symptoms:**
- VMs on 10.0.20.x can ping pfSense (10.0.20.170)
- VMs cannot ping 8.8.8.8 or reach internet
- pfSense itself can reach internet

**Cause**: NAT not configured or outbound firewall rule missing

**Diagnosis:**
```bash
# On affected VM
ping 10.0.20.170  # Should work
ping 8.8.8.8      # Fails

# On pfSense (SSH, Option 8)
ping 8.8.8.8      # Should work
```

**Solution:**
1. Check NAT: Firewall → NAT → Outbound
2. Verify automatic outbound NAT enabled OR manual rule exists for 10.0.20.0/24
3. Check LAN firewall rules allow outbound traffic

---

### Issue 5: DNS Resolution Fails for Internal Domains

**Symptoms:**
- Can resolve external domains (google.com)
- Cannot resolve internal domains (ansible.home.lab)
- Direct query to IPA works: `nslookup ansible.home.lab 10.0.20.184`

**Cause**: pfSense not forwarding internal queries to IPA

**Solution:**
1. Verify domain override configured: Services → DNS Resolver → Domain Overrides
2. Ensure entry exists:
   - Domain: `home.lab`
   - IP: `10.0.20.184`
3. Restart DNS resolver: Services → DNS Resolver → Restart

---

### Issue 6: vMotion Fails with Network Error

**Symptoms:**
- vMotion fails immediately
- Error: "Network unreachable" or "vMotion timeout"

**Cause**: vMotion network not properly configured

**Diagnosis:**
```bash
# On ESXi Master
vim-cmd hostsvc/vmotion/vnic_info

# On ESXi Production
vim-cmd hostsvc/vmotion/vnic_info

# Verify both show vMotion enabled on 10.0.30.x
```

**Solution:**
1. Verify VMkernel adapter on vMotion network (10.0.30.x)
2. Enable vMotion on correct adapter
3. Disable vMotion on management adapter
4. Test connectivity: `vmkping -I vmk2 10.0.30.101`

---

## Network Diagnostic Commands

### ESXi Network Troubleshooting

```bash
# List all VMkernel adapters
esxcli network ip interface list

# Show vSwitch configuration
esxcli network vswitch standard list

# Show port group configuration
esxcli network vswitch standard portgroup list

# Ping from specific VMkernel interface
vmkping -I vmk1 10.0.20.90

# Show active network connections
esxcli network ip connection list
```

### VM Network Troubleshooting

```bash
# Basic connectivity
ping 10.0.20.170  # Gateway
ping 8.8.8.8       # Internet

# DNS resolution
nslookup ansible.home.lab
nslookup google.com

# Trace route
traceroute 10.0.20.184  # IPA
traceroute 8.8.8.8       # Internet

# Check routing table
ip route show

# Check firewall rules (Rocky Linux)
sudo firewall-cmd --list-all
```

### pfSense Diagnostics

```bash
# Ping test (pfSense web UI)
Diagnostics → Ping
  Host: 8.8.8.8
  Source: LAN

# Packet capture
Diagnostics → Packet Capture
  Interface: LAN
  Protocol: ICMP

# View states
Diagnostics → States
  Filter by source IP to see active connections
```

---

## Future Security Enhancements

### Planned Improvements

**Network Intrusion Detection:**
- Deploy Suricata on pfSense
- Monitor for suspicious traffic patterns
- Alert on potential security incidents

**Firewall Granularity:**
- Implement per-application firewall rules
- Restrict Kubernetes pod egress
- Allow-list approach for internet access

**Zero-Trust Network Policies:**
- Implement micro-segmentation
- VM-to-VM firewall rules
- Default deny between application tiers

**VPN for Remote Access:**
- Deploy OpenVPN on pfSense
- Certificate-based authentication
- MFA for administrative access

---

## Related Documentation

- [Network Overview](01-Network-Overview.md)
- [Internal Network](03-Internal-Network.md)
- [pfSense Configuration](05-pfSense-Configuration.md)
- [Troubleshooting Cases](../../troubleshooting/network/)
