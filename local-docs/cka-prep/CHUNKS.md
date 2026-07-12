# Interview Prep — Master Chunk List
10 chunks, organized by domain. Each chunk = one focused prep session.

---

## Chunk 1: Linux Administration
- Processes (ps, top, kill, nice, signals, zombie/orphan)
- Systemd (systemctl, journalctl, unit files, targets, enable/disable/mask)
- Users and permissions (chmod, chown, umask, sudoers, /etc/shadow, /etc/passwd)
- File system (df, du, mount, fstab, LVM basics, inodes, ext4/xfs)
- Package management (dnf/yum/apt, repos, gpg keys)
- SSH (keys, config, tunneling, scp/rsync, authorized_keys, known_hosts)
- Logs (journalctl, /var/log/messages, /var/log/secure, log rotation)
- Cron jobs (crontab, /etc/cron.d, systemd timers)
- SELinux / AppArmor (awareness level)
- Your daily Linux at Huawei: SUSE, CentOS, Rocky in project

## Chunk 2: Virtualization
- Type 1 vs Type 2 hypervisors
- KVM architecture (QEMU, libvirt)
- Proxmox: why chosen, bootstrap scripts, golden templates, LXC vs VM decisions
- VMware: ESXi, vCenter, vSphere, vMotion, DRS, HA, resource pools
- FusionCompute at Huawei: what it is, crash/performance scenarios, 25 PoC cases
- VM lifecycle: create, snapshot, clone, template, migrate, delete
- Overcommitment (CPU, memory, balloon driver)
- OpenStack: awareness level (Nova, Neutron, Cinder, Keystone)
- Proxmox vs VMware vs OpenStack — when to use each
- Backup vs snapshot (difference, use cases)

## Chunk 3: Networking + Reverse Proxy + Load Balancing
- OSI model (L2/L3/L4/L7 with examples)
- TCP vs UDP (3-way handshake, use cases, ports)
- DNS resolution (recursive vs iterative, record types: A, AAAA, CNAME, MX, TXT, SOA)
- HTTP vs HTTPS (TLS handshake basics, certificates)
- Subnetting (CIDR notation, /24, /16, /8, private ranges)
- Firewalls, security groups, NACLs — stateful vs stateless
- VPN (site-to-site, client, WireGuard — your project)
- NAT (SNAT, DNAT, PAT)
- VLAN (802.1Q tagging, your 14 VLANs)
- Your project networking: WireGuard to AWS, MikroTik, 3 traffic planes, L2 storage isolation
- Nginx: reverse proxy, upstream blocks, Lua routing logic, SSL termination, your external Nginx LXC
- Load balancing concepts: L4 vs L7, round robin, health checks, sticky sessions, active-passive vs active-active
- HAProxy: your K8s API load balancer (3 masters → VIP), config, health checks
- Keepalived: VRRP, virtual IP failover, your K8s VIP + Vault VIP
- Troubleshooting tools: ping, traceroute, dig/nslookup, ss/netstat, tcpdump, ip route

## Chunk 4: Cloud Concepts + AWS
- Cloud computing fundamentals (on-demand, pay-as-you-go, elasticity)
- IaaS vs PaaS vs SaaS — who manages what, examples
- Shared responsibility model
- Regions, AZs, edge locations
- Cloud migration: lift-and-shift, re-platform, re-architect
- AWS IAM (users, roles, policies, assume-role, STS, MFA)
- AWS VPC (subnets, route tables, IGW, NAT GW, security groups vs NACLs)
- AWS EC2 (instance types, AMIs, EBS, key pairs, user data)
- AWS S3 (buckets, policies, versioning, lifecycle, encryption, storage classes)
- AWS Route53 (hosted zones, record types, routing policies)
- AWS Secrets Manager + KMS (your Vault integration)
- AWS CloudWatch (metrics, alarms, log groups, dashboards)
- OIDC federation (your GitHub Actions integration)
- Cost basics (reserved vs on-demand vs spot, billing alerts, cost explorer)

## Chunk 5: Scripting — Bash + Python
- Bash: variables, loops, conditionals, functions
- Your scripts: bootstrap.sh, network-setup.sh, IO storm watchdog
- Common interview scripts: parse log, find largest files, check disk, restart service
- sed, awk, grep, cut, sort, uniq — one-liners
- Python: variables, f-strings, functions, lists, dicts, loops
- subprocess module (calling system commands)
- File I/O (read/write files)
- requests/hvac library (API calls to Proxmox/Vault)
- Your remediation pod Python rewrite
- Common Python scripts: parse JSON, read file, API call
- PowerShell: awareness redirect only

## Chunk 6: Monitoring + Logging Stack
- Prometheus: pull model, scrape interval, exporters, PromQL basics
- Grafana: visualization, data sources, dashboards
- Alertmanager: routing, grouping, silencing, receivers
- Loki: log aggregation, LogQL basics, difference from ELK
- node-exporter: system metrics (CPU, RAM, disk, network)
- event-exporter: K8s events to Loki
- Your observability stack: what you actually see and use daily
- AWS CloudWatch: how it compares to Prometheus
- Troubleshooting scenarios: "app is slow", "VM unreachable" — what do you check?
- Alerting strategies: thresholds, SLOs, paging vs warning

## Chunk 7: CI/CD Pipeline (Git, GitHub Actions, Terraform, Ansible)
- Git: branching, merge, rebase, conflict resolution, your commit patterns
- GitHub Actions: your 31 workflows, OIDC federation, plan gates, job locking
- Self-hosted runners: why, how, where they run
- Terraform: state management, S3+DynamoDB locking, 2-tier IAM, modules, import, lifecycle
- Ansible: 76 playbooks, inventory pattern, idempotency, two-phase bootstrap
- The full pipeline: TF provisions → Ansible configures → Flux deploys
- General CI/CD: stages, artifacts, rollback, blue-green, canary
- Infrastructure as Code concepts

## Chunk 8: Containerization (Docker, K8s, Flux, Helm)
- Docker: Dockerfile, image layers, multi-stage builds, docker-compose
- Docker networking: bridge, host, overlay
- Docker volumes and storage
- K8s architecture: control plane, kubelet, etcd, scheduler, controller-manager
- Pods, Deployments, Services, Ingress, ConfigMaps, Secrets
- kubectl troubleshooting (logs, describe, exec, get events)
- Your cluster: kubeadm HA, HAProxy/Keepalived VIP, Calico CNI
- Flux CD GitOps: what it does, how it reconciles, dependency split
- Helm: charts, values, releases, rollback
- ingress-nginx: NodePort → external Nginx, Ingress resources, path routing
- Remediation pod (self-healing via Proxmox API)
- NFS CSI storage (PV/PVC, why not local disk)
- Your DR test stories (etcd quorum loss, worker eviction, disk pressure)
- Honest level: 2 months deep, not 2 years

## Chunk 9: Project Integrations (Vault + FreeIPA)
**Vault:**
- HA cluster (3-node, Raft consensus)
- KMS auto-unseal (why not Shamir — operational necessity)
- LDAP auth back to FreeIPA
- K8s auth method (ServiceAccount → policy → secret path)
- AWS secrets engine (STS short-lived creds, no static keys)
- Vault agent injector in K8s
- Certificate chain: FreeIPA CA → certmonger → Vault TLS

**FreeIPA:**
- Identity management (users, groups, host groups)
- HBAC rules (who can SSH where)
- Sudo policies (passwordless for bots, with-password for admins)
- Password policies (4yr automation, 1yr admin)
- UID ranges (60001-65500 for LXC compatibility)
- DNS + NTP integration

**How they connect:** FreeIPA issues certs → Vault uses them for TLS → Vault authenticates users via FreeIPA LDAP → K8s gets secrets from Vault

## Chunk 10: Storage + Backup/DR
- Block vs file vs object storage (when to use each)
- SAN vs NAS (iSCSI, FC, NFS, SMB — protocols and use cases)
- LUN provisioning (pool → LUN → filesystem → host connectivity)
- Thin vs thick provisioning (LVM-thin, overcommit risks)
- RAID levels (0, 1, 5, 6, 10 — trade-offs)
- Your NAS: RAID 1 NVMe, VLAN 40 L2-isolated, per-environment ACLs
- NFS in K8s: CSI driver, PV/PVC, StorageClass (retain vs delete), soft vs hard mounts
- Backup strategies: full, incremental, differential
- Your Proxmox backup jobs (vzdump, zstd, retention, thermal throttling)
- Backup vs snapshot (difference, use cases, LVM snapshots)
- RTO vs RPO (definitions, how you'd estimate for your components)
- DR test articulation: walk through 3-4 of your 17 DR tests as stories
- Known SPOFs and mitigations (FreeIPA, NAS, Nginx, MariaDB)
- Data integrity: hard mounts for databases, soft for apps (why)

---

## Redirect Knowledge — Quick Comparisons
Not full chunks. Just enough to answer "do you know X?" with an honest redirect.

### AWS vs Azure (know the name mapping)
| AWS | Azure equivalent |
|-----|-----------------|
| EC2 | Virtual Machines |
| S3 | Blob Storage |
| VPC | Virtual Network (VNet) |
| IAM | Azure AD (Entra ID) + RBAC |
| Route53 | Azure DNS |
| CloudWatch | Azure Monitor |
| KMS | Azure Key Vault |
| Secrets Manager | Azure Key Vault |
| ELB/ALB | Azure Load Balancer / App Gateway |
| CloudFormation | ARM Templates / Bicep |
| EKS | AKS |

Redirect: "I work with AWS daily in my project — IAM, VPC, S3, KMS, OIDC federation. I haven't used Azure hands-on, but the concepts map directly. I'd ramp up fast."

### GitHub Actions vs Jenkins
| GitHub Actions | Jenkins |
|---------------|---------|
| YAML workflows in repo | Jenkinsfile (Groovy) or UI pipeline |
| Runs on: GitHub-hosted or self-hosted runners | Runs on: Jenkins master + agents |
| Triggered by: push, PR, dispatch, schedule | Triggered by: webhook, poll SCM, cron |
| Secrets: GitHub Secrets + OIDC | Secrets: Jenkins Credentials store |
| Marketplace actions | Plugins (1800+) |
| No server to maintain (SaaS) | You manage the Jenkins server |

Redirect: "I use GitHub Actions — 31 workflows, OIDC federation, self-hosted runners, plan gates. Jenkins is the same CI/CD concept with a different execution model. The pipeline thinking transfers."

### Flux vs ArgoCD
| Flux | ArgoCD |
|------|--------|
| Pull-based GitOps, runs in-cluster | Pull-based GitOps, runs in-cluster |
| No UI (CLI + CRDs) | Has a dashboard UI |
| Kustomize + Helm native | Kustomize + Helm + Jsonnet |
| GitRepository + Kustomization CRDs | Application CRD |
| Multi-source via multiple GitRepository | Multi-source via ApplicationSet |
| CNCF graduated | CNCF graduated |

Both do the same thing: watch a git repo, reconcile desired state to cluster. Flux is lighter, ArgoCD has better visibility.
Redirect: "I run Flux in my cluster — GitOps reconciliation, Helm releases, dependency ordering, health checks. ArgoCD solves the same problem with a UI on top. The GitOps pattern is what matters."

### Loki vs ELK Stack
| Loki | ELK (Elasticsearch + Logstash + Kibana) |
|------|----------------------------------------|
| Index-free, labels only | Full-text index (inverted index) |
| Lightweight, low storage cost | Heavy, needs dedicated cluster |
| LogQL (like PromQL for logs) | KQL / Lucene query syntax |
| Pairs with Promtail (shipper) | Pairs with Logstash or Filebeat (shipper) |
| Good for: label-based filtering, small-medium scale | Good for: full-text search, large-scale, complex queries |
| Grafana as UI | Kibana as UI |

Redirect: "I run Loki + Promtail + Grafana for log aggregation. ELK does the same job with full-text indexing — heavier but more powerful for search. I chose Loki because it integrates natively with my Prometheus/Grafana stack and keeps resource usage low."
