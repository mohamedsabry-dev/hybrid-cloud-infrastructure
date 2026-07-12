Skill 11 — Networking (8 questions)
=====================================

Format: Standard questions only. Project examples are ammunition.
Your 13-VLAN design, WireGuard hybrid tunnel, MikroTik migration,
asymmetric keepalive, CGNAT debugging, storage VLAN L2 isolation,
dev/prod router-level separation, three traffic planes — inject when earned.

---

1. Explain the OSI model. What happens when you type a URL in the browser?

   Coverage check:
   - 7 layers with real protocols at each
   - L2 (Ethernet, MAC, ARP), L3 (IP, routing), L4 (TCP/UDP, ports), L7 (HTTP)
   - URL flow: DNS resolution → TCP 3-way handshake → TLS handshake →
     HTTP request → response → rendering
   - TLS handshake (ClientHello, ServerHello, certificate, key exchange)
   - SNI (Server Name Indication)
   - HTTP status codes (2xx, 3xx, 4xx, 5xx — common ones)
   - where caching happens (browser, CDN, reverse proxy)

2. How does DNS work? Walk me through a resolution.

   Coverage check:
   - recursive vs iterative resolution
   - resolver → root → TLD → authoritative
   - record types (A, AAAA, CNAME, MX, TXT, SRV, PTR, SOA)
   - TTL and caching
   - /etc/resolv.conf, /etc/hosts, nsswitch.conf (resolution order)
   - dig, nslookup for debugging
   - split-horizon DNS (internal vs external)
   - DNS in identity systems (FreeIPA runs its own DNS — why)

3. Explain TCP vs UDP — and walk me through the TCP three-way handshake.

   Coverage check:
   - TCP — reliable, ordered, connection-oriented
   - UDP — unreliable, fast, connectionless
   - three-way handshake: SYN → SYN-ACK → ACK
   - teardown: FIN → ACK → FIN → ACK
   - TCP states (LISTEN, ESTABLISHED, TIME_WAIT, CLOSE_WAIT)
   - when TIME_WAIT accumulation is a problem
   - DNS uses both (UDP for queries, TCP for zone transfers and large responses)
   - common protocols per transport (HTTP/SSH/FTP over TCP, DNS/DHCP/WireGuard over UDP)

4. What are VLANs and how does subnetting work?

   Coverage check:
   - VLAN purpose (L2 segmentation without physical separation)
   - tagged vs untagged, 802.1Q
   - trunk ports vs access ports
   - inter-VLAN routing (router-on-a-stick, L3 switch)
   - native VLAN (why change from VLAN 1)
   - subnetting: CIDR notation, calculating hosts/subnets
   - private ranges (RFC 1918: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
   - router vs switch (L3 routing vs L2 forwarding)

5. Explain NAT — SNAT, DNAT, PAT.

   Coverage check:
   - SNAT (source NAT — outbound, hides internal IPs)
   - DNAT (destination NAT — inbound, port forwarding to internal hosts)
   - PAT (port address translation — many-to-one, port tracking)
   - connection tracking table (how return traffic finds its way back)
   - why NAT breaks some protocols (FTP active mode, SIP)
   - NAT and firewall interaction
   - CGNAT (carrier-grade NAT — ISP level, double NAT)

6. What is a VPN and how do you choose between protocols?

   Coverage check:
   - site-to-site vs client VPN
   - WireGuard (UDP, simple, fast, modern cryptography)
   - IPSec (IKEv2, ESP, tunnel vs transport mode, widely supported)
   - OpenVPN (TLS-based, flexible, slower)
   - tradeoffs: simplicity vs compatibility vs performance
   - PersistentKeepalive for NAT traversal
   - split tunneling vs full tunnel

7. How do you troubleshoot network connectivity?

   Coverage check:
   - methodology: layer by layer, bottom up
   - ping (L3 reachability, ICMP)
   - traceroute / mtr (path analysis, where it dies)
   - dig / nslookup (DNS resolution)
   - ss / netstat (what's listening, connection states)
   - tcpdump (packet capture — see what's actually on the wire)
   - curl (L7 — HTTP response, TLS errors)
   - ip route (local routing table)
   - arp -a (L2 — MAC resolution)
   - MTU issues (fragmentation, path MTU discovery)

8. What is a firewall — stateful vs stateless?

   Coverage check:
   - packet filtering based on rules (src/dst IP, port, protocol)
   - stateful: tracks connection state, return traffic auto-allowed
   - stateless: each packet evaluated independently, both directions need rules
   - iptables chains (INPUT, OUTPUT, FORWARD)
   - iptables tables (filter, nat, mangle)
   - nftables (modern replacement)
   - L4 vs L7 firewalls
   - where firewalls sit in cloud (SG = stateful, NACL = stateless)
