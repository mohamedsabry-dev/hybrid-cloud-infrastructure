# Orange Business — UC & Cloud Support Engineer — Cairo (Hybrid)
Applied: May 12, 2026
Status: Applied, no response yet
Priority: #1

---

## Postings

- ID 586900 (detailed JD) — 100+ applicants → this is what we prep for
- ID 587249 (lighter JD) — 47 applicants → same role, less detail
- Two more repostings appeared May 13: one is 586900 refreshed (64 applicants), one is a separate Voice/UC L1 role (43 applicants, skip — too junior)

---

## Full requirements from JD (Posting 1) vs honest level

### Responsibilities

| # | What they want (exact from JD) | Honest level | Prep? |
|---|-------------------------------|--------------|-------|
| 1 | 24/7 technical support via email, chat, phone — cloud-related incidents and change requests | Strong — doing this daily at Huawei TAC | No |
| 2 | Troubleshooting cloud infrastructure, networking, security, SAAS & PAAS | Moderate — infra yes, networking theory shaky, SAAS/PAAS gap | YES |
| 3 | Collaborate with cross-functional teams to escalate complex issues | Strong — acting team lead, cross-team daily | No |
| 4 | Monitoring and optimizing cloud resources for performance and cost efficiency | Deployed, not deep — Prometheus/Grafana up, never done cloud cost optimization | YES |
| 5 | Contributing to KB articles, documentation, best practices | Very strong — 130+ articles | No |
| 6 | Assisting customers with cloud service onboarding, configuration, migration | Gap — never done cloud migration or customer onboarding | YES |
| 7 | Root cause analysis + recommendations to prevent recurrence | Very strong — 134+ RCAs, signature skill | No |
| 8 | Staying updated with latest cloud technologies and trends | Moderate — follow AWS/K8s, not multi-cloud | Light |
| 9 | On-call rotations 24/7 | Strong — doing it now | No |
| 10 | Maintaining high customer satisfaction with timely solutions | Strong — SLA-driven at Huawei | No |
| 11 | Management of proactive and reactive cases | Strong — proactive (DR tests, monitoring), reactive (TAC incidents) | No |

### Skills

| # | What they want (exact from JD) | Honest level | Prep? |
|---|-------------------------------|--------------|-------|
| 1 | Very good interpersonal and communication skills | Strong — team lead, trainer | No |
| 2 | IT background (Engineering, CS) | ✓ Bachelor Computer Engineering | No |
| 3 | Strong knowledge of AWS, Azure, or GCP | Moderate (AWS — SAA + project, no production). Aware (Azure Fundamentals). Gap (GCP) | YES |
| 4 | Proficiency in troubleshooting cloud infra, networking, security, app deployment | Moderate — cloud infra yes, networking theory shaky, app deployment limited | YES |
| 5 | Scripting: Python, PowerShell, Bash | Solid (Bash), Early (Python), Gap (PowerShell) | YES — need Python examples ready |
| 6 | Understanding of virtualization: VMware or OpenStack | Solid (VMware PoC 25 cases + FusionCompute). Gap (OpenStack) | Light — review VMware specifics |
| 7 | Strong problem-solving and analytical skills | Very strong | No |
| 8 | Excellent communication with customers and internal teams | Strong | No |
| 9 | Fast-paced environment, multiple tasks | Strong — TAC oncall proves this | No |
| 10 | Certs: AWS SAA, Azure Admin, GCP ACE beneficial | AWS SAA ✓, Azure Fundamentals ✓ (not Admin), KCNA ✓, GCP ACE ✗ | No — mention what you have |
| 11 | 0-2 years in similar scope | 3+ years Huawei — overqualified | No |

---

## Prep needed — summary

Items marked YES above:

1. **Cloud concepts + AWS services depth** — IaaS/PaaS/SaaS, shared responsibility, regions/AZs, migration patterns. AWS: IAM, VPC, EC2, S3, Route53, CloudWatch, security groups vs NACLs, cost basics
2. **Networking theory** — TCP/IP, DNS resolution, OSI model, HTTP/HTTPS, firewalls, security groups, direct routing, subnetting
3. **Cloud monitoring + cost optimization** — CloudWatch basics, Prometheus/Grafana articulation, alerting concepts, cost optimization concepts (reserved instances, right-sizing, billing alerts)
4. **SAAS/PAAS support patterns** — what does troubleshooting SAAS vs PAAS vs IaaS look like? Different layers, different tools
5. **Cloud migration concepts** — lift-and-shift, re-platform, re-architect. Customer onboarding patterns
6. **Python scripting examples** — have 2-3 scripts you can walk through
7. **Virtualization refresh** — VMware specifics from chunk 1, keep sharp
8. **Linux admin articulation** — core for any cloud support, need to say it not just do it
9. **Huawei incident stories** — customer-facing behavioral questions will be heavy

---

## 7-DAY PREP PLAN — Orange Business Priority 1 + Linux

### Day 1 — May 13 (Tue): Linux admin
- Processes (ps, top, kill, nice, signals, zombie/orphan processes)
- Systemd (systemctl, journalctl, unit files, targets, enable/disable/mask)
- Users and permissions (chmod, chown, umask, sudoers, passwd, /etc/shadow, /etc/passwd)
- File system (df, du, mount, fstab, LVM basics, inodes, ext4/xfs)
- Package management (dnf/yum/apt, repos, gpg keys)
- SSH (keys, config, tunneling, scp/rsync, authorized_keys, known_hosts)
- Logs (journalctl, /var/log/messages, /var/log/secure, log rotation)
- Cron jobs (crontab, /etc/cron.d, systemd timers)
- Extract 15-20 questions into chunk file

### Day 2 — May 14 (Wed): Virtualization + VMware
- Type 1 vs Type 2 hypervisors (review chunk 1 Q6)
- VMware ESXi architecture — what is vSphere, vCenter, ESXi, vMotion
- Your VMware PoC: what you built, what limits you hit, 25 documented cases
- FusionCompute at Huawei: what it is, how you troubleshot it, crash/performance scenarios
- VM lifecycle: create, snapshot, clone, template, migrate, delete
- Resource pools, DRS, HA concepts in VMware
- OpenStack: what it is at awareness level (compute=Nova, networking=Neutron, storage=Cinder, identity=Keystone) — enough for a redirect answer, not depth
- Proxmox vs VMware vs OpenStack — when would you use each
- Your LXC vs VM decision (review chunk 1 Q4)
- Backup vs snapshot (review chunk 1 Q11)
- Extract 15-20 questions into chunk file

### Day 3 — May 15 (Thu): Scripting — Bash + Python
- Bash:
  - Variables, loops, conditionals, functions
  - Your bootstrap.sh — walk through what it does and why
  - Your network-setup.sh — walk through the logic
  - IO storm watchdog script — what it detects, how it responds
  - Common interview scripts: parse a log file, find largest files, check disk usage, restart a service if down
  - sed, awk, grep, cut, sort, uniq — one-liners you should know
- Python:
  - Variables, f-strings, functions, lists, dicts, loops
  - subprocess module (how you call system commands)
  - File I/O (read/write files)
  - Your remediation pod rewrite — what you've done so far
  - requests/hvac library — for API calls to Proxmox/Vault
  - Common interview scripts: parse JSON, read a file line by line, API call
- PowerShell: awareness redirect only — "I script in Bash and Python on Linux. PowerShell concepts transfer, I'd pick it up if needed."
- Extract 10-15 questions into chunk file

### Day 4 — May 16 (Fri): Cloud concepts + AWS services
- Cloud basics:
  - What is cloud computing? (on-demand, pay-as-you-go, elasticity)
  - IaaS vs PaaS vs SaaS — what each means, examples, who manages what
  - Shared responsibility model (AWS version)
  - Regions, AZs, edge locations
  - What is cloud migration? Lift-and-shift vs re-platform vs re-architect
  - What does customer onboarding to cloud look like?
  - Troubleshooting SaaS vs PaaS vs IaaS — different layers, different access
- AWS services you've used (articulate each one):
  - IAM (users, roles, policies, assume-role, STS, MFA, permission boundaries)
  - VPC (subnets, route tables, internet gateway, NAT gateway, security groups vs NACLs)
  - EC2 (instance types, AMIs, EBS volumes, key pairs, user data)
  - S3 (buckets, policies, versioning, lifecycle, encryption, storage classes)
  - Route53 (hosted zones, record types: A/CNAME/MX/TXT, routing policies)
  - Secrets Manager + KMS (your Vault integration, how you use them)
  - CloudWatch (metrics, alarms, log groups, dashboards)
  - Cost basics (free tier, reserved vs on-demand vs spot, billing alerts, cost explorer)
  - OIDC federation (your GitHub Actions integration — articulate the full flow)
- Extract 15-20 questions into chunk file

### Day 5 — May 17 (Sat): Networking theory
- OSI model (7 layers — at least explain L2/L3/L4/L7 with examples)
- TCP vs UDP (3-way handshake, use cases, ports)
- DNS resolution (recursive vs iterative, record types: A, AAAA, CNAME, MX, TXT, SOA)
- HTTP vs HTTPS (TLS handshake basics, certificates)
- Subnetting (CIDR notation, /24 = 256 addresses, /16, /8, private ranges 10.x, 172.16-31.x, 192.168.x)
- Firewalls, security groups, NACLs — stateful vs stateless
- VPN (site-to-site, client, WireGuard — your project)
- NAT (SNAT, DNAT, why it exists, PAT)
- Direct routing — what it means in cloud/networking context
- VLAN (what, why, tagging 802.1Q — your 14 VLANs)
- Your project networking: WireGuard to AWS, MikroTik, 3 traffic planes, L2 storage isolation
- Common troubleshooting: ping, traceroute, dig/nslookup, ss/netstat, tcpdump, ip route
- Extract 15-20 questions into chunk file

### Day 6 — May 18 (Sun): Monitoring + cloud operations
- Prometheus: what it does, pull model, scrape interval, exporters, PromQL basics
- Grafana: visualization layer, data sources, dashboards
- Alertmanager: receives from Prometheus, routing, grouping, silencing, receivers
- Loki: log aggregation, LogQL basics, difference from ELK
- node-exporter: system metrics (CPU, RAM, disk, network)
- event-exporter: K8s events to Loki
- Your observability stack: walk through what you actually see and use daily
- AWS CloudWatch: metrics, alarms, log groups, dashboards — how it compares to Prometheus
- Cost optimization: right-sizing, reserved instances, spot instances, billing alerts, cost explorer
- Walk through: "a customer reports their cloud app is slow — what do you check?"
- Walk through: "a customer reports their VM is unreachable — what do you check?"
- Extract 10-15 questions into chunk file

### Day 7 — May 19 (Mon): Huawei stories + behavioral
- Write 4 structured incident stories (symptom → investigation → root cause → fix):
  1. FusionCompute crash or OOM scenario
  2. Performance degradation (CPU/memory/IO)
  3. Storage issue (LUN, pool, connectivity)
  4. Cross-team escalation that you drove to resolution
- Behavioral questions:
  - "Tell me about yourself" — 90-second version
  - "Why are you leaving your current role?"
  - "How do you handle multiple incidents at the same time?"
  - "Tell me about a time you had a difficult customer"
  - "How do you document and share knowledge?"
  - "Describe a time you had to learn something new quickly"
  - "What do you do when you can't solve an issue?"

### Day 8 — May 20 (Tue): Full Orange Business mock interview
- Mix of ALL topics from Days 1-7:
  - Linux admin (processes, systemd, permissions, logs)
  - Virtualization (VMware, Type 1/2, vMotion, snapshots, FusionCompute)
  - Scripting (Bash script walkthrough, Python example)
  - Cloud concepts (IaaS/PaaS/SaaS, shared responsibility, migration)
  - AWS services (IAM, VPC, S3, EC2, security groups, OIDC)
  - Networking (DNS, TCP, OSI, subnetting, VLANs, VPN)
  - Monitoring (Prometheus, Grafana, CloudWatch, alerting)
  - Behavioral (Huawei stories, customer scenarios, escalation)
- Timed: 60-90 seconds per answer
- Record yourself if possible

### Day 9 — May 21 (Wed): Weak spots + re-practice
- Review mock results from Day 8
- Re-practice any answers that were scattered or incomplete
- Re-read code for anything still fuzzy
- Final polish on "tell me about yourself" and project walkthrough

---

## After Day 9

Continue with Week 2-3 from TASKS schedule (K8s, Vault, Ansible, CI/CD, simulation) for broader coverage across Axis, Sumerge, and future applications.

If Orange calls — you're ready.
