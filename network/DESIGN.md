# Network layer — design notes and reasoning

How the on-prem network stack evolved over time and the decision trail behind the current setup. Reads as a narrative, not a runbook — for the live topology, IP plan, device tables, and VLAN reference see [`README.md`](README.md), [`ip-planning.txt`](ip-planning.txt), and [`topology.txt`](topology.txt).

---

## Why the network stack evolved (ER605 → MikroTik)

The network didn't start where it is now. Originally I ran everything through a TP-Link **ER605** router, a Festa **FS308GP** switch, and a TP-Link **AC750** AP. The switch and AP stayed; the ER605 got replaced. Here's why.

The trigger was an accumulation of three painful incidents, all documented in [`../troubleshooting/network/`](../troubleshooting/network/):

- **TS-NET-003** — Dev VMs cyclically losing gateway connectivity with link flapping every 2–30 seconds on the trunk to the Dev Proxmox server. Six days of investigation across four phases. I initially blamed a Port 4 gigabit-negotiation defect on the ER605 — and that's also where the replacement plan started forming. **But later in the investigation I found out the port was not actually defective.** The real root cause was elsewhere, and the "faulty port" framing was a false trail. The ER605 decision was already in motion by then though, and it stayed, because TS-NET-003 had already shown me how hard the ER605 was to debug with its limited CLI.

- **TS-NET-004** — Prod WireGuard tunnel ran for five days with no handshake while dev's tunnel on the same setup worked perfectly. Turned out the ISP's CGNAT was silently blocking the return UDP port for prod's tunnel. Dev's port happened to be un-blocked. The kind of bug where `tcpdump` showed AWS replying but the replies never reached my router.

- **TS-NET-005** — A four-phase WireGuard tunnel stability investigation. Ruled out NAT timeout, keepalive settings, CGNAT again, and several other theories before landing on the conclusion that the cleanest fix was to move prod's VPN endpoint off the London IP entirely (same incident that drove the prod-region drift — see [`../aws/DESIGN.md`](../aws/DESIGN.md)). The full resolution involved **both** moving prod compute/network to `us-east-1` and replacing the ER605 with MikroTik.

### What actually pushed me to MikroTik

Stacking those three cases, the real reasons were:

1. **Confidence.** Too many VPN-layer and link-layer issues in a row eroded my trust in the ER605 as the edge of a "hybrid cloud" story. Even after the issues were resolved, I didn't want the same device sitting at the critical path.
2. **CLI and scripting.** The ER605's CLI is thin — most configuration is GUI-driven and not scriptable in a way I'd want for infrastructure-as-code. Every debugging session felt like fighting the tool. MikroTik gives me a real CLI, `.rsc` scripts I can keep in this repo (`router/mikrotik/phase1-mgmt-access.rsc`, `phase2-dev-services.rsc`), and exportable configs that are human-readable and diff-able.
3. **A cleaner slate for the tunnels.** After TS-NET-004 and TS-NET-005 both involved the ER605's WireGuard implementation in one way or another, starting fresh on MikroTik let me rebuild the tunnel setup without inheriting any of the mystery debt.
4. **Troubleshooting / diagnostic capability.** This was a core driver in its own right. The ER605 had almost no diagnostic surface — no packet sniff, no `tcpdump`-equivalent, no port-level traffic inspection, no granular per-interface stats. I was debugging blind the whole time during the TS cases above, inferring what was happening from external tools (`tcpdump` on AWS EC2, `dmesg` on Proxmox, handshake counters on WireGuard). MikroTik flips this completely — `/tool sniffer`, `/interface ethernet monitor`, port-level statistics, real rotatable logs. For me this is a win that goes beyond solving the immediate problem: every future network issue becomes a chance to actually see what's happening and learn from it, instead of a wall to run into. For a project that is also a learning exercise, that capability gap was the decider.

### What stayed

- **FS308GP switch** — worked fine throughout. Had two port-flapping incidents of its own (logs in [`switch/fs308gp/logs/`](switch/fs308gp/logs/)) but both were investigated and the switch itself was never the root cause.
- **AC750 AP** — untouched. Management WiFi only; no issues.

### Current state

- **MikroTik L009UiGS-RM** is now the router / firewall / VPN endpoint. Configs in [`router/mikrotik/`](router/mikrotik/) as RouterOS `.rsc` scripts + backup files.
- **ER605** is kept under [`router/er605/`](router/er605/) as a historical archive — the folder records the previous state for completeness, not as something to deploy against.

---

## Why service VLANs bypass the switch

Originally, all traffic — storage and service VLANs — ran through the FS308GP switch on the way to the router. After TS-NET-003 found the real root cause of the Dev network flapping (USB-ethernet adapter instability on the Proxmox host, not the switch or router), I rewired the service trunks to go directly from each Proxmox server's `svc0` into a dedicated MikroTik port.

The switch itself was never the problem — but the investigation showed me the path had too many hops and too many suspects. Every trunk port, every cable, every VLAN tag along the way was a variable I had to rule out during six days of debugging. Simplifying the path removed variables I'd never need to debug again.

What changed:
- **Service VLANs (50-55, 60-65):** Proxmox `svc0` → direct to MikroTik port (one hop, one cable)
- **Storage VLAN (40):** Still on the switch — intentionally. Storage is L2-isolated and never routes through the router. The switch is the right place for it: NAS, Proxmox `stor0`, and k8s worker NICs all talk directly over L2 on VLAN 40 with no router hop.
- **Switch role now:** Storage VLAN only. Ports 2-5 unused. VLANs 50-65 still defined for consistency but no traffic flows through them.

The trade-off is more cables (one per Proxmox host into the router instead of one trunk into the switch), but the simplification was worth it — fewer variables to debug, cleaner failure isolation, and each environment's trunk is physically separate.

See [`topology.txt`](topology.txt) for the current wiring diagram and [`switch/fs308gp/config.txt`](switch/fs308gp/config.txt) for the before/after port layout.

---

## Why VLANs and 802.1Q tagging everywhere, even though most of them can talk to each other

A reviewer looking at my VLAN plan will spot something fast: I split the lab across 13 VLANs (mgmt, storage, and 6 service VLANs per env) — but the router's default routing lets most of them talk to each other anyway. The ACLs I actually enforce are fairly light (covered below). So at first glance the VLAN layer looks like over-engineering.

I did it on purpose for five reasons:

1. **Structure as documentation.** Each workload type has its own subnet and its own VLAN tag. When I see traffic at `10.0.62.x` I know immediately it's a Vault node; `10.0.64.x` is a k8s worker; `10.0.40.x` is storage. The VLAN layer is doubling as a self-documenting IP plan — the IP itself tells you what you're looking at.

2. **Broadcast domain isolation.** Keeping broadcast and multicast traffic scoped per VLAN means one misbehaving host (rogue ARP, mDNS storm from a misconfigured container, a loopback of some sort) can't pollute the whole network. Even without L3 ACLs between them, the L2 isolation is real.

3. **Ready for tightening.** The boundary is already in place as plumbing. Dropping in a new firewall rule on the MikroTik like "vault_cluster → k8s_masters allowed, everything else denied" is a single-line config change against a structure that's already right. If I had kept it flat and decided later to tighten, I'd be restructuring the whole network *and* writing rules at the same time. Doing the VLAN work up front means any future hardening step is purely a router-config problem.

4. **Learning.** Part of the point of this whole project is to actually practice VLAN tagging, trunk ports, 802.1Q on bridges, inter-VLAN routing. Merging everything into one subnet would have skipped all of that.

5. **Environment isolation stays strict regardless of what's open inside each env.** The one line the router never crosses is `dev ↔ prod`. That boundary is absolute and has nothing to do with how permissive or tight the intra-env ACLs happen to be today.

### What the ACLs actually enforce today

The real policy I run is deliberately minimal, focused on the things that matter, and open where the application layer already gates:

- **Dev ↔ Prod: blocked.** Hard boundary on the router, no exceptions. Dev services cannot reach any prod service and vice versa.
- **svc ↔ mgmt, svc ↔ storage, mgmt ↔ storage: blocked** (within each env). The three planes stay decoupled. Service workloads cannot go poking at the storage plane; management traffic cannot leak into service VLANs.
- **Within each env, service VLANs can talk to each other.** A k8s worker can reach a Vault node directly over the service plane — that's intentional. The gating there is application-layer (Vault token, k8s service account, Kerberos principal), not L3 firewall.
- **One explicit exception:** k8s masters (service plane) → mgmt plane, *specifically* to the Proxmox API endpoints. This is for the remediation / self-healing path — a k8s-side agent that can call the Proxmox API to recover a broken worker node. Everything else from the service plane into mgmt is still denied.

Shape of the policy:

```
dev  ──────X──────  prod                                   (cross-env: BLOCKED)
svc  ──────X──────  mgmt   ──────X──────  storage          (three planes: BLOCKED between)
k8s_masters (svc)  ─────►  mgmt (Proxmox API only)         (remediation exception, per env)
service-VLAN  ↔  service-VLAN  (within env)                (OPEN — application layer gates)
```

This is a **phased position**, not the final hardening target. The tight VLAN scaffolding is already in place so that when I later add stricter per-pair rules (vault ↔ specific k8s workers only, etc.), I'm writing firewall rules against a structure that's already right — not rebuilding the network and writing rules at the same time.
