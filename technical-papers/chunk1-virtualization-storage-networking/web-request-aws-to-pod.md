Web Request — AWS to On-Prem Pod and Back (Summary Trace)
==========================================================

EC2 (172.17.63.30) resolves wordpress-prod.lab.local
  → VPC DNS → Route 53 private hosted zone → 10.0.55.10 (nginx external proxy on-prem)

→ EC2 route table: no match for 10.x → default route → VPC route table:
  10.0.0.0/16 → wg-prod ENI (source_dest_check=false)
    → wg-prod kernel: ip_forward=1 → route table: 10.0.55.0/24 dev wg0

→ WireGuard encrypts original packet → wraps in UDP (src private IP, dst HOME_PUBLIC_IP:51820)
  → kernel default route → VPC → IGW 1:1 NAT (private → Elastic IP) → public internet

→ ISP router: NAT state entry from MikroTik's outbound initiation
  → de-NATs → 192.168.100.195:51830 → MikroTik WireGuard decrypts
    → original packet restored: src 172.17.63.30, dst 10.0.55.10

→ MikroTik: firewall ACL passes AWS source → route table: 10.0.55.0/24 via vlan55
  → ARP for 10.0.55.10 → builds L2 frame VLAN 55 → ether5 trunk → Proxmox svc0

→ vmbr0: VLAN 55 filter → MAC lookup in FDB → tap interface → nginx VM receives

→ nginx (L7 proxy): Host header matches → upstream 10.0.54.x:30080 (NodePort)
  → new TCP connection: src 10.0.55.10, dst 10.0.54.11:30080

→ hairpin: nginx → vmbr0 VLAN 55 → svc0 → MikroTik inter-VLAN routing (55→54)
  → svc0 → vmbr0 VLAN 54 → worker VM (same cable, 3 traversals)

→ worker1: iptables PREROUTING → KUBE-NODEPORTS → KUBE-SVC (probability chains)
  → DNAT: 10.0.54.10:30080 → 10.245.207.124:80 (ingress pod) + masquerade
    → Calico route: pod on different node → IPIP tunnel encapsulation
      → outer: worker1 → worker2 (L2 direct, same VLAN 54, no router)
        → worker2 strips IPIP → /32 route → cali veth → ingress pod

→ ingress controller (L7 proxy): reads Host header → matches Ingress resource
  → Lua upstream list → picks WordPress pod IP → new TCP connection
    → same node: direct via local cali veth
    → different node: IPIP tunnel again

→ WordPress pod: processes request → queries MariaDB (ClusterIP → DNAT → pod)
  → renders page → HTTP response

→ return path unwinds 3 TCP connections:
  WordPress → ingress (IPIP if cross-node) → worker1 (masquerade de-NAT)
    → vmbr0 VLAN 54 → MikroTik (54→55) → vmbr0 VLAN 55 → nginx VM
      → nginx responds on original connection → MikroTik WireGuard encrypts
        → ISP NAT → internet → AWS IGW de-NAT → VPC SG (stateful, auto-allows)
          → VPN EC2 WireGuard decrypts → VPC routes to mgmt subnet
            → EC2 TCP stack matches 4-tuple → browser renders page
