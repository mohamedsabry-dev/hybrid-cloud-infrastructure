# Orange Business — Application Support and Cloud Ops Engineer — Cairo
Applied: May 21, 2026
Status: Received Submission
Job ID: 585836
Priority: High — strong DevOps/K8s/Ansible match, Windows is the main gap

---

## Role Details

- Team: Managed Application Cloud Expertise (MAC), CIO Organization within CTIO
- Level: 2+ years IT experience
- Type: Full-time, Hybrid
- Scope: 2nd level (L2) application and infrastructure support, 24x7 on-call

---

## What The Team Does

MAC team handles the "middle tier" in the multilayered support chain.
Responsible for keeping application availability in line with business criticality.
Takes tickets from L1 (IT Helpdesk), OBSIT Monitoring, or Orange Cloud For Business Monitoring.
End-to-end ownership of all requests from L1.

---

## Responsibilities

### Technical
- Ensure application availability to meet SLA targets
- Handle, diagnose, and route incoming trouble tickets in real-time
- System administration for applications on Windows servers
- Execute changes and task orders on Windows servers
- 2nd level technical support and escalation
- Communicate planned/unplanned outages to end users
- Participate in UAT testing for bugs/new features
- Work in DevOps mode for all cloud-hosted applications:
  - Understand app functionality to help define QoS matrices
  - L2 support for cloud infrastructure
  - L2 application support for cloud-based applications

### Functional
- Managing known issues (application and infrastructure support)
- Team collaboration

---

## Technical Skills — ONE OR MORE mandatory

The JD explicitly says "basic knowledge in one or more of the below domains is mandatory":

| # | Domain | Honest Level | Match? |
|---|--------|-------------|--------|
| 1 | OS admin & scripting (Windows, Linux) | Linux: strong (3+ yrs daily, Rocky Linux, 26 VMs/LXCs). Windows: gap (PoC v1 has 6 PowerShell scripts but no Windows server admin) | PARTIAL |
| 2 | Database admin (Oracle, SQL Server, Postgres) | MariaDB in K8s (StatefulSet, InnoDB, NFS hard mount). No Oracle/SQL Server/Postgres | PARTIAL |
| 3 | Web Services (SOAP, REST) | REST: YES — Proxmox API, Vault API, K8s API, GitHub API throughout project. SOAP: no | YES |
| 4 | Development (Python, Java, ASP.NET, Node.js, C#, PHP, React.js) | Python: early (remediation pod, Docker images). Bash: strong. Rest: gap | PARTIAL |
| 5 | Big Data (Hadoop, MongoDB) | Gap | NO |
| 6 | Mobile development (Android, iOS) | Gap | NO |
| 7 | Continuous delivery (Docker, Kubernetes, Ansible) | Docker: 2 custom images + CI builds. K8s: HA cluster, 75 manifests, Flux GitOps. Ansible: 76 playbooks | YES |
| 8 | Security protocols (ethical hacking is a plus) | IAM, OIDC, TLS/PKI, Vault, Kerberos, HBAC. Not ethical hacking | PARTIAL |

Domains that match: #1 (Linux side), #3 (REST), #7 (Docker/K8s/Ansible) = 3 strong domains out of 8.
JD only requires ONE OR MORE — well above threshold.

---

## Other Skills

| # | Skill | Honest Level | Match? |
|---|-------|-------------|--------|
| 1 | Troubleshooting | 114 TS cases + 25 PoC v1 + 134 Huawei RCAs | YES |
| 2 | Teamwork | Team lead at Huawei, cross-team daily | YES |
| 3 | Communication (written + verbal) | 130+ articles, 15 deployment guides, English fluent | YES |
| 4 | Time management | SLA-driven at Huawei TAC | YES |
| 5 | Agile and DevOps (plus) | 31 CI/CD workflows, Flux GitOps, IaC everywhere | YES |
| 6 | Network protocols (CCNA plus) | VLANs, VPN, MikroTik, TCP/IP. No CCNA cert | YES (no cert) |
| 7 | ITIL foundation (plus) | Huawei TAC follows ITIL-like SLA/escalation. No cert | PARTIAL |
| 8 | BSc CS or equivalent | BSc Computer Engineering | YES |
| 9 | Fluent English | YES | YES |
| 10 | Fluent French (plus) | No | NO |
| 11 | 2+ years IT experience | 3+ years Huawei + 7 months project | YES |

---

## Notes

This is a DIFFERENT Orange role from the UC & Cloud Support one (Job IDs 586900/587249).
This one is MAC team — application support + cloud ops, more DevOps-oriented.

Key strengths: Docker/K8s/Ansible is one of the listed domains (and it's the strongest match area).
The JD only requires ONE domain — and Sabry matches 3 domains solidly.

Main concern: Windows server admin is listed as explicit responsibility (not just a domain option).
"Provide system administration for the applications implemented on Windows servers" and
"Execute changes and task orders on windows server" appear in the responsibilities section.
This means even though Linux/K8s/Ansible is the skill match, the day-to-day could involve Windows.

Strategy if interviewed: Lead with Docker/K8s/Ansible as the domain expertise.
Acknowledge Windows gap honestly but frame it as learnable given strong OS fundamentals.
The DevOps/cloud part of the role aligns perfectly with the project.
