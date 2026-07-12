Web Request — AWS to On-Prem Pod and Back
==========================================

Full trace from browser on AWS to WordPress pod on-prem, crossing every layer
in the hybrid setup. 15 steps forward, then the return path.

Environment:
  EC2 (172.17.63.30, mgmt subnet) → WireGuard VPN → MikroTik → Proxmox → K8s → WordPress pod
  Request: http://wordpress-prod.lab.local


### Step 1 — DNS Resolution

    EC2 sends DNS query for wordpress-prod.lab.local
      |
      +-- EC2 has no local DNS records
      |     resolver is VPC DNS at 172.17.0.2 (always .2 of VPC CIDR)
      |
      +-- VPC DNS forwards to Route 53
      |     checks private hosted zones associated with this VPC
      |     finds lab.local zone (associated via Terraform)
      |
      +-- R53 resolves wordpress-prod.lab.local → 10.0.55.10
            VPC DNS returns answer to EC2

    10.0.55.10 is the nginx external proxy LXC on-prem.
    not a public IP — only reachable through the VPN tunnel.


### Step 2 — AWS Internal Routing (EC2 to VPN Node)

    EC2 (172.17.63.30) wants to reach 10.0.55.10
      |
      +-- OS route table: no match for 10.x
      |     falls back to default route → sends to subnet gateway 172.17.63.1
      |
      +-- packet leaves ENI into VPC networking
      |     VPC checks route table attached to this subnet (rt_public)
      |     finds: 10.0.0.0/16 → eni of wg-prod EC2 in subnet 172.17.65.0/24
      |
      +-- VPC delivers packet to wg-prod ENI
            packet crosses subnets within the VPC

    the wg-prod security group must allow inbound from 172.17.63.0/24.
    source_dest_check=false on the ENI lets it accept packets not addressed
    to its own IP, but the security group still evaluates independently.


### Step 3 — VPN Node (Kernel Forwarding + WireGuard Encryption)

    wg-prod EC2 (172.17.65.35) receives packet on ens5
      |
      +-- kernel checks: destination 10.0.55.10 is not mine → this is forwarding
      |     ip_forward=1 (required, otherwise kernel drops it)
      |
      +-- kernel checks route table:
      |     10.0.55.0/24 dev wg0 (installed by wg-quick from AllowedIPs)
      |     sends packet to wg0 interface
      |
      +-- WireGuard on wg0 receives packet (src 172.17.63.30, dst 10.0.55.10)
            checks AllowedIPs config → destination matches on-prem peer
            encrypts the ENTIRE original packet using peer's public key
            wraps in a new UDP packet:

              outer: src 172.17.65.35 (private IP), dst <HOME_PUBLIC_IP>, UDP port 51820
              inner: [encrypted original packet, IPs completely preserved]

    source IP in the outer packet is the EC2's private IP (172.17.65.35),
    not the Elastic IP. the IGW handles the NAT in the next step.


### Step 4 — AWS Outbound (VPC to Internet)

    new UDP packet needs to reach <HOME_PUBLIC_IP>
      |
      +-- kernel route table: no match → default route → ens5 → subnet gateway
      |
      +-- packet enters VPC networking → route table: no match → 0.0.0.0/0 → IGW
      |
      +-- IGW performs 1:1 NAT:
            rewrites src from 172.17.65.35 to EC2's Elastic IP
            packet goes to public internet as a normal UDP packet


### Step 5 — Public Internet → ISP → MikroTik

    UDP packet arrives at ISP router on home static public IP, port 51830.

    how it reaches MikroTik: MikroTik initiates the tunnel outbound
    (192.168.100.195:51830 → AWS EIP:51820). when it does, the ISP router
    creates a NAT state entry mapping:

        192.168.100.195:51830 ↔ public_ip:mapped_port

    the keepalive from AWS (pings every 5s) keeps this mapping alive.

    when AWS sends a UDP packet back to public_ip:mapped_port, the ISP
    router matches it against the NAT state table, de-NATs destination
    back to 192.168.100.195:51830, and forwards to MikroTik.

    no port forwarding needed — the outbound-initiated NAT mapping
    handles it. this works because ISP is Full Cone NAT: maintains the
    mapping as long as traffic keeps flowing in either direction.


### Step 6 — MikroTik (WireGuard Decryption)

    UDP packet hits MikroTik on port 51830
      |
      +-- WireGuard service listening there receives it
      |     decrypts payload using MikroTik's private key
      |
      +-- out comes the original packet:
            src 172.17.63.30, dst 10.0.55.10

    source and destination IPs are completely untouched.
    WireGuard is transparent encapsulation — it wraps and unwraps,
    never modifies the inner packet's addresses.


### Step 7 — MikroTik Internal Routing

    MikroTik has the decrypted packet: src 172.17.63.30, dst 10.0.55.10, port 80
      |
      +-- firewall ACL: source 172.17.x.x is allowed to reach prod VLANs → passes
      |
      +-- route table: 10.0.55.0/24 reachable via VLAN interface vlan55 (10.0.55.1)
      |
      +-- before sending, MikroTik needs the destination MAC
      |     ARPs on VLAN 55: "who has 10.0.55.10?"
      |     nginx VM responds with its MAC address
      |
      +-- builds L2 frame:
            dst MAC = nginx VM's MAC (from ARP reply)
            src MAC = MikroTik's vlan55 interface MAC
            VLAN tag = 55
            sends out ether5 (trunk port connected to Proxmox svc0)


### Step 8 — Proxmox Bridge (L2 Delivery to nginx VM)

    tagged frame (VLAN 55) arrives on svc0
    (physical NIC, enslaved to vmbr0 — it's a port on the virtual switch)
      |
      +-- vmbr0 is pure L2 — no IP address, no routing
      |     two-step decision:
      |
      +-- VLAN filter:
      |     narrows to ports configured for VLAN 55
      |     eliminates all VLAN 54 VMs, VLAN 60 VMs, etc.
      |
      +-- MAC lookup:
      |     checks FDB (forwarding database, the bridge's MAC address table)
      |     for the destination MAC that MikroTik wrote into the frame
      |     finds it behind tap1001i0 (nginx VM)
      |
      +-- forwards ONLY to that port
            strips the VLAN tag → delivers untagged frame to tap1001i0
            VM sees a normal packet on its eth0

    even if 5 VMs share VLAN 55, only the one matching the destination
    MAC receives the frame — the bridge is a switch, not a hub.

    for LXC containers (200x series), Proxmox inserts an extra per-container
    firewall bridge (fwbr) between the container and vmbr0. LXCs share the
    host kernel and need additional isolation. KVM VMs (100x/10xx) connect
    directly via tap interfaces.


### Step 9 — nginx External Proxy (INPUT, Not Forward)

    packet arrives at nginx VM (10.0.55.10) on port 80
      |
      +-- kernel checks: destination is my own IP
      |     this is INPUT chain, not FORWARD
      |     different from the VPN node in step 3 where the packet
      |     was transiting through — here the packet is FOR this machine
      |
      +-- kernel delivers to nginx process listening on port 80
      |
      +-- nginx checks config:
      |     Host header matches *.lab.local
      |     upstream block says forward to 10.0.54.10, .11, or .12
      |     on port 30080 (NodePort), selection via least_conn
      |
      +-- nginx picks a worker (say 10.0.54.11:30080)
            creates a NEW connection — this is a new packet originating
            from nginx, OUTPUT chain
            src becomes 10.0.55.10, dst 10.0.54.11, port 30080

    this is an L7 proxy. nginx reads the HTTP request and creates a
    brand new TCP connection to the backend. the original client's
    connection terminates here.


### Step 10 — Hairpin (nginx to Worker Node via MikroTik)

    nginx (10.0.55.10) sends new packet to 10.0.54.11
      |
      +-- OS route table: no match for 10.0.54.x
      |     falls to default route → sends to gateway 10.0.55.1 (MikroTik) out eth0
      |
      +-- frame leaves VM untagged → vmbr0 bridge adds VLAN 55 tag
      |     (based on port config) → sends out svc0 to MikroTik ether5
      |     this is the hairpin — traffic goes out the SAME physical cable it came in on
      |
      +-- MikroTik receives VLAN 55 tagged frame
      |     L3 routing: dst 10.0.54.11 is on VLAN 54 interface (10.0.54.1)
      |     inter-VLAN routing — MikroTik re-tags the frame as VLAN 54
      |     sends it back out ether5 to Proxmox svc0
      |     same cable, second time
      |
      +-- vmbr0 receives VLAN 54 tagged frame
            VLAN filter: worker VM's tap interface is configured for VLAN 54
            strips tag → delivers untagged frame to worker VM

    the packet travels through the same physical cable three times total:
    first into Proxmox (step 8), then out to MikroTik for routing (VLAN 55),
    then back in routed to the worker (VLAN 54). this is the cost of having
    the router on a stick — all inter-VLAN traffic hairpins through one link.


### Step 11 — Worker Node (iptables DNAT — NodePort to Ingress Pod)

    packet arrives at worker1 (10.0.54.10) on port 30080
      |
      +-- kernel receives on eth0
      |     before routing decision, packet passes through PREROUTING chain
      |     in the iptables nat table
      |
      +-- iptables processing — chain of decisions kube-proxy pre-installed:
      |
      |     KUBE-NODEPORTS: match tcp dpt:30080 → jump to KUBE-EXT-...
      |       |
      |       +-- KUBE-EXT-...: mark packet for masquerade → jump to KUBE-SVC-...
      |             |
      |             +-- KUBE-SVC-...: load balance across 3 ingress controller pods:
      |                   probability 0.333 → DNAT to 10.245.62.3:80
      |                   probability 0.500 (of remaining) → DNAT to 10.245.207.124:80
      |                   remainder → DNAT to 10.245.62.31:80
      |
      +-- each chain is a subfolder of rules — the packet drills down until
      |     it hits the actual DNAT action
      |     kube-proxy wrote all of this automatically by watching the K8s API
      |     for Service and Endpoints changes
      |     when a pod dies → kube-proxy removes its entry
      |     when a pod starts → adds one
      |
      +-- DNAT rewrites destination:
      |     10.0.54.10:30080 → 10.245.207.124:80
      |     masquerade rewrites source to the node's IP
      |     so the reply comes back through this node
      |
      +-- kernel re-evaluates routing with new destination (10.245.207.124)
            checks route table:
              10.245.207.64/26 via 10.0.54.11 dev tunl0
            this route was installed by Calico
            pods in that /26 range live on node 10.0.54.11
            destination is on a different node → FORWARD


### Step 12 — Calico IPIP Tunnel (Cross-Node Pod Delivery)

    tunl0 is Calico's IPIP tunnel — same concept as WireGuard encapsulation
      |
      +-- wraps the pod-network packet inside a new IP packet:
      |
      |     outer: src 10.0.54.10 (worker1), dst 10.0.54.11 (worker2), protocol IPIP
      |     inner: dst 10.245.207.124:80 (ingress controller pod)
      |
      +-- both workers are on VLAN 54 (same subnet)
      |     the outer packet does NOT go through MikroTik
      |     worker1 ARPs for 10.0.54.11, gets worker2's MAC
      |     sends the frame directly through vmbr0 — L2-local, no router hop
      |
      +-- worker2 receives the outer packet
      |     kernel strips IPIP header — no credentials needed
      |     IPIP is plain wrapping (not encrypted like WireGuard)
      |     safe because this stays on the private VLAN 54 network
      |
      +-- kernel checks inner packet: dst 10.245.207.124:80
            route table: 10.245.207.124/32 dev cali839ffdc68cc scope link
            a /32 route pointing to a Calico veth interface
            this is a virtual cable — one end (cali839ffdc68cc) is on the host,
            the other end appears as eth0 inside the ingress controller pod's
            network namespace
            kernel forwards packet down this veth into the pod

    Calico has no bridge. unlike Proxmox (svc0 → vmbr0 bridge → tap),
    Calico connects pods directly to the host kernel's routing stack
    via veth pairs. eth0 (the node's physical NIC) is the external door.
    each cali-xxx is a direct internal door to a pod. the kernel routes
    between them using the route table — pure L3, no L2 switching.


### Step 13 — Ingress Controller (L7 Proxy to WordPress Pod)

    ingress controller pod receives packet on port 80
      |
      +-- kernel inside pod's namespace delivers to nginx process (INPUT)
      |
      +-- this is where L3/L4 (kernel) ends and L7 (application) begins
      |     kernel only cared about IPs and ports
      |     nginx reads the actual HTTP content — Host header says
      |     "wordpress-prod.lab.local"
      |
      +-- nginx checks loaded Ingress rules (synced from K8s API)
      |     finds WordPress Ingress resource matching that host
      |     Lua module holds in-memory upstream list of current WordPress pod IPs
      |     kept in sync with K8s Endpoints — when a pod dies or starts,
      |     the Lua module updates dynamically without reloading nginx config
      |
      +-- Lua picks a WordPress pod (say 10.245.62.60:80)
      |     nginx creates a NEW TCP connection — a new packet originating
      |     from the ingress pod. this is NOT iptables DNAT — the ingress
      |     controller is an L7 proxy, it reads HTTP and makes a new connection
      |
      +-- new packet:
      |     src = ingress pod IP (10.245.207.124)
      |     dst = WordPress pod IP (10.245.62.60), port 80
      |
      +-- packet exits pod via veth → pops out at cali839ffdc68cc on host kernel
            kernel checks route table: 10.245.62.60 — local or remote?

            if WordPress pod is on THIS same node:
              route matches a local cali-xxx /32
              kernel forwards directly down that veth to the WordPress pod
              no tunnel needed

            if WordPress pod is on a DIFFERENT node (say worker3, 10.0.54.12):
              route matches 10.245.62.0/26 via 10.0.54.12 dev tunl0
              same IPIP tunnel path — encapsulate, send out eth0,
              vmbr0 delivers on VLAN 54 to worker3,
              worker3 strips IPIP header, routes to local cali-xxx veth,
              delivers to WordPress pod


### Step 14 — Pod Landing (WordPress Container)

    WordPress pod receives HTTP request on port 80
      |
      +-- application processes it
      |     queries MariaDB (10.245.62.1:3306, another ClusterIP
      |     → DNAT → MariaDB pod)
      |
      +-- renders the page
      +-- sends HTTP response back through the same chain in reverse


### Step 15 — Return Path (Full Reverse)

    every hop in the forward path opened a TCP connection with a unique
    4-tuple (src IP, src port, dst IP, dst port). the response follows
    each connection back. no hop needs to "remember" the full chain —
    each just responds on the connection it received.

    three connections were opened on the forward path:
      1. EC2 browser:   172.17.63.30:48372 → 10.0.55.10:80
      2. nginx proxy:   10.0.55.10:39201 → 10.0.54.11:30080
      3. ingress ctrl:  10.245.207.124:41055 → 10.245.62.60:80
      (port numbers are random per-connection — that's how TCP works)

    the response unwinds:

    WordPress pod responds on connection 3:
      src 10.245.62.60:80, dst 10.245.207.124:41055
      if ingress pod is on a different node → IPIP tunnel back
      if same node → direct via local cali veth

    ingress controller receives the response, matches to connection 3:
      sends HTTP response back on connection 2
      masquerade on worker1 (from step 11) de-NATs the destination
      back to 10.0.55.10:39201
      packet routes: Calico veth → host kernel → IPIP if cross-node
      → vmbr0 VLAN 54 → MikroTik inter-VLAN routing (54→55)
      → vmbr0 VLAN 55 → nginx VM

    nginx proxy receives the response, matches to connection 1:
      creates HTTP response back to original client
      src 10.0.55.10:80, dst 172.17.63.30:48372

    packet leaves nginx VM → vmbr0 tags VLAN 55 → svc0 → MikroTik:
      route table: 172.17.63.30 is in 172.17.0.0/16
      matches WireGuard peer's AllowedIPs
      encrypts with AWS peer's public key
      wraps in UDP: src 192.168.100.195:51830, dst AWS-EIP:51820

    ISP router NATs src to public IP → internet → arrives at AWS IGW:
      IGW de-NATs EIP to VPN EC2 private IP (172.17.65.35)
      packet enters VPC

    AWS inbound path:
      NACL evaluates (stateless, but typically allow-all in this setup)
      → SG evaluates (stateful — remembers the outbound packet, auto-allows return)
      → delivers to VPN EC2 ENI

    VPN EC2 kernel:
      WireGuard on wg0 decrypts → original packet: src 10.0.55.10, dst 172.17.63.30
      kernel checks route: 172.17.63.0/24 not local (EC2 is on 172.17.65.0/24)
      default route via ens5 → packet goes to VPC
      VPC route table: 172.17.63.0/24 is part of 172.17.0.0/16 → local
      VPC delivers to mgmt subnet EC2

    EC2 kernel receives the packet:
      TCP stack matches 4-tuple: "this is a response to connection
      172.17.63.30:48372 → 10.0.55.10:80"
      delivers HTTP response to browser process
      page renders

    if 2 users open the same URL simultaneously from different terminals,
    they have different random source ports (48372 vs 51893). every hop
    tracks connections by the 4-tuple, not by content. two requests,
    two connections, never confused.

    if the ingress pod dies before the response comes back, the response
    is dropped. the TCP connection is lost — no other ingress pod can
    pick it up because TCP state (sequence numbers, connection tracking)
    is per-pod. the browser retries, gets a new connection routed to a
    different ingress pod, and the request starts fresh.
