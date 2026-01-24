================================================================================
CASE: SSH Disconnects from Static Route Loop
================================================================================
Category: Network - Routing Loops
Severity: High
Date: Network Configuration Phase
Environment: Windows Laptop, Physical Router, pfSense VM
Issue: Routing loop causes SSH disconnections and network instability

================================================================================
SYMPTOM
================================================================================
- SSH sessions to VMs disconnect randomly
- Network connectivity is intermittent
- Ping responses show erratic RTT (round-trip time)
- Some packets reach destination via unexpected paths
- traceroute shows circular routing patterns
- Services appear unreachable despite being online

Example Symptoms:
```
$ ssh root@10.0.0.100
Connection established...
[30 seconds later]
Connection to 10.0.0.100 closed by remote host.
Connection to 10.0.0.100 closed.
```

Ping showing loop symptoms:
```
ping 10.0.0.100
64 bytes from 10.0.0.100: icmp_seq=1 time=5ms
64 bytes from 10.0.0.100: icmp_seq=2 time=250ms  ← Loop delay
64 bytes from 10.0.0.100: icmp_seq=3 time=2ms
Request timeout for icmp_seq=4                   ← Dropped in loop
```

================================================================================
ROOT CAUSE
================================================================================
Configuring static routes on BOTH the physical router AND client laptop
creates a routing loop for traffic destined to the internal network.

Network Topology:
-----------------
```
Internet
  │
Physical Router (192.168.0.1)
  │
Windows Laptop (192.168.0.50) ── Wi-Fi/Ethernet ── ESXi Master
  │                                                      │
  └── Static Route: 10.0.0.0/24 via pfSense WAN          │
                                                         │
                                                    pfSense VM
                                                    WAN: 192.168.0.104
                                                    LAN: 10.0.0.1
                                                         │
                                                    Internal Network
                                                    10.0.0.0/24
                                                    (IPA, Ansible, etc.)
```

The Loop Flow:
--------------
1. Laptop wants to reach 10.0.0.100 (IPA server)
2. Laptop has static route: 10.0.0.0/24 → 192.168.0.104 (pfSense WAN)
3. Packet sent to pfSense WAN
4. pfSense routes packet to 10.0.0.100 on LAN
5. Response comes back from 10.0.0.100
6. pfSense sends response to laptop via WAN
7. BUT physical router ALSO has static route: 10.0.0.0/24 → 192.168.0.104
8. Router intercepts response, sends it back to pfSense
9. pfSense sees packet destined for 10.0.0.100, routes to LAN
10. Packet loops between router and pfSense
11. TTL expires, packet dropped
12. SSH connection times out

Why Both Routes Create Loop:
-----------------------------
- Laptop route: Outbound path works (laptop → pfSense → internal VM)
- Router route: Return path loops (VM → pfSense → router → pfSense → ...)
- Router sees response packets (10.0.0.x → 192.168.0.50)
- Router thinks "10.0.0.x should go to pfSense" (its static route)
- Router forwards response BACK to pfSense instead of to laptop
- pfSense receives response packet, thinks "this is for 10.0.0.x, route to LAN"
- Packet never reaches laptop, TCP connection times out

Technical Details:
------------------
Routing decision on physical router for return packet:
- Source: 10.0.0.100 (IPA)
- Destination: 192.168.0.50 (Laptop)

Router's routing table:
- 192.168.0.0/24 → Local network (directly connected)
- 10.0.0.0/24 → 192.168.0.104 (static route)

Router logic:
- "Destination 192.168.0.50 is in 192.168.0.0/24, should deliver locally"
- BUT source is 10.0.0.100, which matches 10.0.0.0/24 route
- Some routers do reverse path filtering (RPF) or source-based routing
- Router may forward packet to 192.168.0.104 (pfSense) instead of laptop
- Result: Routing loop

================================================================================
DIAGNOSTIC PROCEDURES
================================================================================

Diagnosis 1: Trace Packet Path with traceroute
-----------------------------------------------
From Windows laptop:
```
tracert 10.0.0.100
```

Problematic output showing loop:
```
  1    <1 ms    <1 ms    <1 ms  192.168.0.104  (pfSense WAN)
  2    <1 ms    <1 ms    <1 ms  192.168.0.1    (Router - WRONG!)
  3    <1 ms    <1 ms    <1 ms  192.168.0.104  (pfSense WAN - Loop!)
  4    <1 ms    <1 ms    <1 ms  192.168.0.1    (Router - Loop!)
  5    *        *        *     Request timed out
```

Correct output (no loop):
```
  1    <1 ms    <1 ms    <1 ms  192.168.0.104  (pfSense WAN)
  2    1 ms     1 ms     1 ms   10.0.0.100     (IPA Server - Direct!)
```

Diagnosis 2: Check Routing Tables
----------------------------------
On Windows Laptop:
```powershell
route print
```

Look for:
```
Network Destination    Netmask          Gateway       Interface
10.0.0.0               255.255.255.0    192.168.0.104  192.168.0.50
```

On Physical Router:
(Access router admin panel or CLI)

Look for:
```
Static Routes:
10.0.0.0/24 → 192.168.0.104
```

If BOTH exist → PROBLEM!

On pfSense:
Navigate to: Diagnostics > Routes

Look for:
```
10.0.0.0/24 → LAN interface (10.0.0.1)
192.168.0.0/24 → WAN interface (192.168.0.104)
default → 192.168.0.1 (router)
```

Diagnosis 3: Use tcpdump to Observe Loop
-----------------------------------------
On pfSense WAN interface:
```bash
tcpdump -i em0 -n icmp
```

On pfSense LAN interface:
```bash
tcpdump -i em1 -n icmp
```

Start ping from laptop:
```
ping 10.0.0.100
```

Observe packet flow:
- WAN interface sees: Same packet multiple times (incoming loop)
- LAN interface sees: Packet forwarded to 10.0.0.100
- WAN interface sees: Response comes back, forwarded to router
- WAN interface sees: Same response comes back AGAIN from router (loop!)

If you see packets going WAN → LAN → WAN → WAN (again), it's a loop.

Diagnosis 4: Check TTL Values
------------------------------
```bash
ping -t 10.0.0.100
```

Watch for TTL decrements:
- Normal: TTL starts at 64, returns at 62-63 (1-2 hops)
- Loop: TTL returns at 50-55 (10+ hops due to loop iterations)
- Severe loop: TTL expires, no response

Diagnosis 5: Wireshark Packet Capture
--------------------------------------
On Windows laptop, run Wireshark:
1. Capture on Wi-Fi/Ethernet adapter
2. Filter: ip.dst == 10.0.0.100 or ip.src == 10.0.0.100
3. Start ping to 10.0.0.100

Look for:
- Request packets sent once
- Response packets received multiple times (duplicates)
- TTL decreasing on duplicate responses
- Packets arriving out of order

This indicates routing loop.

================================================================================
SOLUTION
================================================================================

Rule: Configure Static Route on Client ONLY, NOT on Physical Router
--------------------------------------------------------------------

WHY:
- Laptop needs the route to know how to reach 10.0.0.0/24
- Router does NOT need the route (it's not trying to reach 10.0.0.0/24)
- Router's job is to forward packets between internet and local network
- Laptop's job is to route to pfSense for internal network access

CORRECT Configuration:
----------------------
✅ Windows Laptop: Static route 10.0.0.0/24 → 192.168.0.104
❌ Physical Router: NO static route for 10.0.0.0/24
✅ pfSense: Default route → 192.168.0.1, LAN route → 10.0.0.0/24

Solution Implementation
-----------------------

Step 1: Remove Static Route from Physical Router
-------------------------------------------------
Access router admin panel (typically http://192.168.0.1):

1. Navigate to: Advanced Settings > Static Routes
2. Find route: 10.0.0.0/24 → 192.168.0.104
3. Delete the route
4. Save configuration
5. Reboot router (if required)

Verify removal:
- Check routing table again
- Route for 10.0.0.0/24 should be gone

Step 2: Verify Static Route on Windows Laptop
----------------------------------------------
Check existing route:
```powershell
route print | findstr "10.0.0.0"
```

If route doesn't exist, add it:
```powershell
# Add persistent route
route -p ADD 10.0.0.0 MASK 255.255.255.0 192.168.0.104 METRIC 1
```

If route exists but incorrect, delete and re-add:
```powershell
# Delete old route
route DELETE 10.0.0.0 MASK 255.255.255.0

# Add correct route
route -p ADD 10.0.0.0 MASK 255.255.255.0 192.168.0.104 METRIC 1
```

Verify:
```powershell
route print | findstr "10.0.0.0"
```

Expected output:
```
Network Destination    Netmask          Gateway       Interface     Metric
10.0.0.0               255.255.255.0    192.168.0.104  192.168.0.50   1
```

Step 3: Verify pfSense Routing
-------------------------------
On pfSense web UI:
Navigate to: Diagnostics > Routes

Verify:
```
10.0.0.0/24 → link#2 (LAN interface)
192.168.0.0/24 → link#1 (WAN interface)
default → 192.168.0.1 (router)
```

On pfSense shell:
```bash
netstat -rn
```

Verify routes are correct.

Step 4: Clear ARP Cache (All Devices)
--------------------------------------
After route changes, clear ARP caches to prevent stale mappings.

On Windows Laptop:
```powershell
arp -d
ipconfig /flushdns
```

On pfSense:
```bash
arp -d -a
```

Physical router:
(Reboot or check for ARP cache clear option)

================================================================================
VERIFICATION
================================================================================

Test 1: Traceroute Should Show Direct Path
-------------------------------------------
From Windows laptop:
```
tracert 10.0.0.100
```

Expected output (2 hops, no loop):
```
  1    <1 ms    <1 ms    <1 ms  192.168.0.104  (pfSense WAN)
  2    1 ms     1 ms     1 ms   10.0.0.100     (IPA Server)
```

✓ Only 2 hops
✓ No router (192.168.0.1) in the path
✓ No repeated IPs (no loop)

Test 2: SSH Should Remain Stable
---------------------------------
```
ssh root@10.0.0.100
```

1. Establish connection
2. Run long-running command (e.g., `top`)
3. Wait 5+ minutes
4. Connection should remain active

✓ No disconnections
✓ No timeouts
✓ Stable RTT

Test 3: Continuous Ping (No Packet Loss)
-----------------------------------------
```
ping -t 10.0.0.100
```

Run for 5 minutes, observe:

✓ 0% packet loss
✓ Consistent RTT (~1-5ms)
✓ No timeouts
✓ TTL remains consistent (62-64)

Test 4: tcpdump Shows Clean Flow
---------------------------------
On pfSense WAN interface:
```bash
tcpdump -i em0 -n host 10.0.0.100
```

Start ping from laptop.

Expected: Each request sees ONE outbound, ONE inbound packet
No duplicates, no loops

================================================================================
PREVENTION
================================================================================

1. **Enterprise Rule: Never Shut Down Interfaces to Test**
   - Use packet tracing instead (tcpdump, Wireshark)
   - Shutdown testing breaks existing connections
   - Difficult to observe actual packet flow when down

2. **Document Routing Design**
   - Where static routes should be configured
   - Why routes are placed on specific devices
   - Rationale for routing decisions

Example:
```
Static Route Placement Policy:
- Client devices (laptops): Routes to internal networks via pfSense
- Physical router: NO routes to internal networks (not a client)
- pfSense: Default route to physical router, LAN routes to internal
```

3. **Routing Change Checklist**
   ```
   Before adding static route:
   [  ] Document why route is needed
   [  ] Identify which device needs the route
   [  ] Check if route already exists elsewhere
   [  ] Verify route doesn't create loop
   [  ] Test with traceroute before committing
   [  ] Monitor for 24h after change
   ```

4. **Test in Isolation**
   - Test routes on one device at a time
   - Verify connectivity before adding to other devices
   - Use traceroute to verify packet path

5. **Regular Route Audits**
   ```
   Quarterly review:
   [  ] Check laptop routing table
   [  ] Check physical router routes
   [  ] Check pfSense routes
   [  ] Verify no redundant/conflicting routes
   [  ] Document any changes
   ```

================================================================================
ARCHITECTURE DECISION: PFSENSE PLACEMENT
================================================================================

This case highlights an important architectural decision:

Decision: Place pfSense INSIDE Nested Cluster (Not on Physical Host)
--------------------------------------------------------------------

Benefits:
1. **Redundancy via HA**
   - If ESXi Host 1 fails, pfSense migrates to Host 2 (vMotion/HA)
   - Network remains operational during host failure
   - Infrastructure VMs maintain connectivity

2. **Portability (Lab Capsule)**
   - Entire lab is self-contained
   - Can move all VM files to different server
   - pfSense configuration migrates with VM
   - No physical hardware dependencies

3. **Simplified Routing**
   - Only clients need routes to internal network
   - Physical router doesn't need knowledge of internal topology
   - Reduces routing complexity
   - Easier troubleshooting

Trade-offs:
- pfSense depends on ESXi cluster being operational
- If entire cluster fails, lose routing to internal network
- Additional vMotion overhead during migrations

For home lab: Benefits outweigh trade-offs

================================================================================
RELATED ISSUES
================================================================================

Issue: Reverse Path Filtering (RPF)
------------------------------------
Some routers implement RPF to prevent IP spoofing:
- Router checks if return path matches forward path
- If source IP doesn't match expected interface, packet dropped
- Can cause similar symptoms to routing loops

Solution: Disable RPF on physical router (if causing issues)

Issue: Asymmetric Routing
--------------------------
Traffic taking different paths inbound vs outbound:
- Can confuse stateful firewalls
- TCP connections may fail
- Similar symptoms to routing loops

Solution: Ensure symmetric routing (same path both directions)

================================================================================
REFERENCES
================================================================================
Source: /DC-K8s/.archive/.../02-Cluster-Configuration/03-networking-security.md
Related Cases:
  - 07-Windows-Host-Network-Loops.txt (IP Forwarding loops)
  - Other network cases in cases/network/
Related Docs: Network Configuration, pfSense Setup

================================================================================
LESSONS LEARNED
================================================================================
- Not all devices in path need routes to all destinations
- Routers forward packets; clients need routes
- Duplicate routes create loops, not redundancy
- Packet tracing (tcpdump/Wireshark) reveals actual flow
- Never shut down interfaces for testing - trace instead
- Routing loops manifest as intermittent connectivity (hardest to debug)
- Document routing design BEFORE implementation
- Test routes with traceroute before assuming they work
- Enterprise network rules apply even in home labs
- Architecture decisions (pfSense placement) affect routing design
- Simple designs are easier to troubleshoot than complex ones
