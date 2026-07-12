Interview Question Bank — 16 Skills + Vault Bonus
====================================================

Generated: 2026-06-01
Source: web research (Reddit, LinkedIn, GeeksforGeeks, DataCamp,
        LivingDevops, InterviewBit, Medium, DevOps Training Institute,
        GitHub repos 1100+ DevOps questions, ThinkCloudly) +
        full codebase scan of hybrid-cloud-infrastructure project.
Target roles: DevOps Engineer, Infrastructure Engineer, Cloud Support,
              Cloud Operations, Systems Engineer (container stack).

Question types:
  [G] = Generic/textbook — standard interview question, answer from knowledge
  [P] = Project-specific — backed by real code, configs, scripts, or incidents

---

## Skill-to-Job Weight Matrix

| Skill | VOIS | Orange UC | Orange MAC | Sumerge | Siemens | Axis | E-Payment |
|-------|------|-----------|------------|---------|---------|------|-----------|
| 1. Linux admin | H | H | H | H | H | H | H |
| 2. Troubleshooting | H | H | H | H | H | H | H |
| 3. Bash scripting | M | H | M | H | H | M | H |
| 4. AWS | H | H | M | L | H | M | L |
| 5. Kubernetes | H | M | H | L | H | M | H |
| 6. Ansible | H | L | H | M | H | M | H |
| 7. Terraform | M | L | L | L | H | M | L |
| 8. Docker | H | M | H | M | H | M | M |
| 9. CI/CD | M | M | H | M | H | M | H |
| 10. Monitoring | M | H | M | H | H | H | H |
| 11. Networking | M | H | M | H | H | H | H |
| 12. Virtualization/NAS | M | H | M | M | M | H | H |
| 13. Git | H | L | M | L | H | M | M |
| 14. Python | M | H | M | M | L | L | H |
| 15. Backup & DR | L | L | M | H | L | H | M |
| 16. Identity/Directory (FreeIPA) | L | M | M | L | M | L | L |
| BONUS: HashiCorp Vault | L | M | M | L | H | L | M |

H = required/heavy, M = mentioned/moderate, L = implied/light

---

## 1. Linux Admin (32 questions)

[G] 1. A server is running slow. Walk me through how you diagnose it.
[G] 2. What is the difference between a process and a thread?
[G] 3. Explain zombie and orphan processes. How do you find and clean them?
[G] 4. What happens when you run a command in Linux? (fork, exec, wait)
[G] 5. How does systemd work? What's the difference between enable, start, and mask?
[G] 6. How do you check why a service failed to start?
[G] 7. Explain file permissions. What does chmod 755 mean? What's umask?
[G] 8. What's the difference between soft link and hard link?
[G] 9. How do you find which process is using a specific port?
[G] 10. A disk is showing 100% usage but you can't find large files. What do you check?
[G] 11. What's the difference between /proc and /sys?
[G] 12. How does the Linux boot process work? (BIOS -> bootloader -> kernel -> init/systemd)
[G] 13. What is swap? When does Linux use it? How do you check swap usage?
[G] 14. What's the difference between df and du? Why might they show different values?
[G] 15. How do you troubleshoot a server you can't SSH into?
[G] 16. What is inode exhaustion and how do you diagnose it?
[G] 17. Explain /etc/fstab. What happens if you misconfigure it?
[G] 18. How do you check memory usage? What's the difference between free, available, and cached?
[G] 19. What are signals? Difference between SIGTERM, SIGKILL, SIGHUP?
[G] 20. How does log rotation work? What tool manages it?
[P] 21. Walk me through your Proxmox host bootstrap process from bare metal. What steps run, in what order, and why does order matter?
[P] 22. How do you create a Terraform automation user in Proxmox with API-only access? What does --privsep 0 --expire 0 mean?
[P] 23. How do you manage MAC-to-interface mapping when replacing USB-Ethernet adapters? What are systemd .link files?
[P] 24. A temperature monitor daemon was misconfigured as a */5 cron job, spawning 132 zombie processes. Walk me through the diagnosis.
[P] 25. What's the difference between cron output going to Postfix email vs being redirected with 2>&1? What happens without either?
[P] 26. How do you configure email alerts (postfix Gmail relay) at bootstrap time so all monitoring scripts can send alerts?
[P] 27. How do you build a golden VM template? What belongs in the template vs what Ansible handles post-deploy?
[P] 28. Walk me through the cloud-init SSH host key preservation fix (99-preserve-ssh.cfg). Why was it needed?
[P] 29. How does a launchd service on macOS add persistent routes to on-prem networks on boot? How do you handle the network startup race?
[P] 30. Your UPS monitor checks gateway, NAS, and 8.8.8.8 during battery discharge. What does each tell you about the outage type?
[P] 31. Why ship debugging tools (tcpdump, traceroute, nmap-ncat) in every golden image instead of installing them when needed?
[P] 32. What's your three-plane network architecture on Proxmox hosts? Why separate NICs instead of VLANs on one interface?

---

## 2. Troubleshooting / RCA (22 questions)

[G] 1. Describe your troubleshooting methodology when something breaks.
[G] 2. Tell me about the hardest issue you ever debugged.
[G] 3. A production service is down. Walk me through your first 5 minutes.
[G] 4. How do you perform root cause analysis? Give an example.
[G] 5. How do you document incidents? What goes into a post-mortem?
[G] 6. A change worked in staging but broke production. How do you investigate?
[G] 7. How do you distinguish between a network issue, a disk issue, and an application issue?
[P] 8. Your entire Kubernetes cluster is down — all pods Unknown, CoreDNS missing. The cluster was healthy 2 days ago. Walk me through diagnosis.
[P] 9. A Flux HelmRelease timeout triggers an exponential retry loop that crashes etcd. How would you break the cascade?
[P] 10. A USB-Ethernet adapter causes link flapping every 2-3 seconds. You try cable, adapter, switch port, forcing 100M — each fix works temporarily. How do you find the true root cause?
[P] 11. A Grafana database is corrupted after running 3 replicas on NFS with SQLite. What's the architectural flaw? What are your options?
[P] 12. Your Terraform state file shrinks from 14KB to 299 bytes after cancelling a workflow mid-execution. What happened and how do you prevent it?
[P] 13. Your Vault cluster fails to start because a manual Ansible run rendered empty variables and overwrote valid KMS credentials on disk. What safeguard prevents this?
[P] 14. Ansible ad-hoc commands take 28-34 seconds when FreeIPA is down, but direct SSH takes 1.2 seconds. What's calling into FreeIPA?
[P] 15. A single Flux Kustomization rename with prune=true accidentally deleted all resources. Walk me through the recovery.
[P] 16. During a 5-minute network outage, one of three identical bare nginx pods gets evicted while the other two survive. What race condition occurred?
[P] 17. Your scheduler and controller-manager metrics are invisible in Grafana. They're bound to localhost:10257 but Prometheus scrapes 0.0.0.0:10257. What's wrong?
[P] 18. A kernel driver binding issue causes wrong duplex negotiation on a USB adapter. Two kernel drivers claim the same hardware. How do you force the correct one?
[P] 19. A backup during recovery adds more IO load on an already degraded cluster. How do you schedule backups without breaking RPO/RTO?
[P] 20. Node-exporter evicts before the disk-full alert fires. The alert fails because the node that reports it is gone. How do you detect this monitoring blind spot?
[P] 21. Kerberos auth works with hostname but fails with IP. Your inventory uses IPs. Why does GSSAPI require FQDNs?
[P] 22. A Vault node can't rejoin the cluster after a Proxmox crash due to stale raft data. What files must you delete and why?

---

## 3. Bash Scripting (18 questions)

[G] 1. Write a script that checks if a service is running and restarts it if not.
[G] 2. What's the difference between $@ and $*?
[G] 3. How do you handle errors in a bash script? What is set -e?
[G] 4. Explain piping and redirection. What does 2>&1 mean?
[G] 5. What is the difference between single quotes, double quotes, and backticks?
[G] 6. How would you parse a log file to find the top 10 IP addresses?
[G] 7. What is an exit code? How do you check the exit code of the last command?
[G] 8. Walk me through a script you wrote and explain the logic.
[G] 9. What's the difference between source and ./script.sh?
[G] 10. How do you schedule a script? What's the difference between cron and systemd timers?
[P] 11. Walk me through your IO storm watchdog detection algorithm. Why does the source VM have LOW IO pressure, not high?
[P] 12. Your IO storm script has two rules. What does Rule 2 (CPU stuck > 300%) catch that Rule 1 misses?
[P] 13. Your temperature monitor reads /sys/class/thermal every 30 seconds but requires 10 consecutive checks above 90C before shutdown. Why?
[P] 14. The temperature monitor skips readings when vzdump is running. Why is that exception necessary?
[P] 15. Your UPS monitor has three battery tiers (78%, 55%, 35%). Walk me through what triggers at each threshold.
[P] 16. How do you implement a wait-for-SSH retry loop in CI/CD? Walk me through the 30-iteration loop with 10-second delays.
[P] 17. How does the IO storm watchdog track suspects in a state file across consecutive checks? Why require 4 consecutive hits (2 minutes)?
[P] 18. What does the post-reset flow look like? Why wait 3 minutes cooldown before checking recovery?

---

## 4. AWS (30 questions)

[G] 1. What is a VPC? Explain subnets, route tables, internet gateway, NAT gateway.
[G] 2. What's the difference between security groups and NACLs?
[G] 3. An EC2 instance can't reach the internet. How do you troubleshoot?
[G] 4. Explain IAM users, roles, and policies. What is assume role?
[G] 5. What is STS? How do temporary credentials work?
[G] 6. What is OIDC federation and when would you use it?
[G] 7. How does S3 bucket policy differ from IAM policy?
[G] 8. What are S3 storage classes and when would you use each?
[G] 9. Explain the difference between public and private subnets.
[G] 10. What is a VPC endpoint and why would you use one?
[G] 11. How do you securely store secrets in AWS?
[G] 12. What is KMS? How does envelope encryption work?
[G] 13. An EC2 instance is unreachable via SSH. What do you check?
[G] 14. What is EC2 instance metadata? What's IMDSv2 and why does it matter?
[G] 15. How do you monitor AWS resources? What is CloudWatch?
[P] 16. How do you bootstrap a Terraform backend when the backend itself (S3 bucket + DynamoDB) doesn't exist yet?
[P] 17. How does OIDC federation work between GitHub Actions and AWS? Walk me through the JWT, STS AssumeRoleWithWebIdentity, and the four validation checks.
[P] 18. What is a PermissionsBoundary? How does it prevent a Terraform role from modifying its own bootstrap resources?
[P] 19. Why split Terraform credentials into TerraformAdmin (admin, security-branch-only) vs Infrastructure (PowerUser, env-branch)?
[P] 20. How do you prevent dev from accidentally modifying prod state when both use S3 backends?
[P] 21. Why use a t3.micro EC2 with WireGuard instead of AWS Site-to-Site VPN? What's the cost difference?
[P] 22. How does disabling source_dest_check on the WireGuard EC2 make it function as a router?
[P] 23. Why use an Elastic IP for the WireGuard endpoint instead of an auto-assigned public IP?
[P] 24. How do you split KMS key permissions between key administrators and key users for Vault's unseal key?
[P] 25. Why does the vault-trust IAM user exist as a long-lived credential instead of IRSA?
[P] 26. How do you implement narrowed blast radius for an etcd-backup pod that needs S3 write access? (IAM chain: vault-trust -> assume role -> scoped S3)
[P] 27. How do you prevent concurrent Terraform applies using DynamoDB state locking?
[P] 28. Why store Terraform-created Secrets Manager entries with placeholder values instead of real secrets?
[P] 29. How does lifecycle { ignore_changes = [secret_string] } prevent Terraform from overwriting AWS Secrets Manager values?
[P] 30. A Terraform apply runs longer than 1 hour. What happens to the OIDC credentials? What happens to the state lock?

---

## 5. Kubernetes (45 questions)

[G] 1. What's the difference between a Deployment, StatefulSet, and DaemonSet?
[G] 2. A pod is stuck in CrashLoopBackOff. How do you debug it?
[G] 3. A pod is stuck in Pending state. What could cause this?
[G] 4. Explain the pod lifecycle. What happens from kubectl apply to running container?
[G] 5. What is a Service? Explain ClusterIP, NodePort, and LoadBalancer.
[G] 6. What is an Ingress and how does it differ from a Service?
[G] 7. How does the Kubernetes scheduler decide where to place a pod?
[G] 8. What are resource requests and limits? What happens when a container exceeds its memory limit?
[G] 9. Explain RBAC. What are Roles, ClusterRoles, RoleBindings?
[G] 10. What is a NetworkPolicy? How do you restrict pod-to-pod communication?
[G] 11. What are taints and tolerations? When would you use them?
[G] 12. What is a PersistentVolume and PersistentVolumeClaim? How do they work together?
[G] 13. How does DNS work inside a Kubernetes cluster?
[G] 14. What is etcd? Why is it critical? How do you back it up?
[G] 15. What are static pods? Where are they defined?
[G] 16. How does kubelet work? What does it do on each node?
[G] 17. What is a liveness probe vs readiness probe vs startup probe?
[G] 18. Explain the difference between kubectl exec, kubectl logs, and kubectl describe.
[G] 19. What is a Helm chart and why would you use it?
[G] 20. Tell me about a Kubernetes outage you handled.
[P] 21. How do you set up Flux GitOps to manage Helm releases with a dependency chain (infrastructure -> apps)?
[P] 22. How do you prevent CRD race conditions when Flux applies Helm charts and custom resources in the same cycle?
[P] 23. How does Vault agent injection work? Walk me through vault-agent-init, the mutating webhook, and template rendering.
[P] 24. Why do you use different NFS StorageClasses with different mount options for databases (hard mount) vs apps (soft mount)?
[P] 25. How do you configure Prometheus to scrape both in-cluster and external infrastructure metrics?
[P] 26. How would you design a VM-level self-healing system that doesn't interfere with Kubernetes pod-level healing?
[P] 27. Walk me through the complete pod creation flow from Deployment manifest to running container, including admission webhooks and vault-agent-injector.
[P] 28. How do you coordinate etcd backups with Vault for temporary AWS credentials without storing long-lived keys?
[P] 29. How do you configure HAProxy + Keepalived for Kubernetes API VIP in a way that survives master failures?
[P] 30. How do you implement safe Flux Kustomization restructuring without accidentally deleting reconciled resources?
[P] 31. How does CoreDNS hosts plugin short-circuit FreeIPA dependency? What still breaks when FreeIPA is down?
[P] 32. How does the remediation pod detect unhealthy nodes and escalate through reboot -> reset -> restore from backup?
[P] 33. How do you handle init container patterns (busybox netcat) to ensure MariaDB is ready before WordPress starts?
[P] 34. Why decouple Alertmanager from kube-prometheus-stack and run it standalone with Vault-injected SMTP credentials?
[P] 35. How do you use vault-inject-template with Golang templating to render entire config files from Vault secrets?
[P] 36. How does Kubernetes auth method work? What four pieces of information must Vault know about the cluster?
[P] 37. Walk me through the Kubernetes boot-to-operational sequence: etcd quorum -> CNI -> Flux -> vault-agent-injector -> apps.
[P] 38. How do you prevent Flux retry storms when unsatisfiable anti-affinity deadlocks cause continuous reconciliation failures?
[P] 39. What's the difference between Flux infrastructure-sync healthCheck and apps-sync dependsOn? Why both?
[P] 40. How do you handle ConfigMap updates on running Deployments without manual pod restarts? (config-version annotation pattern)
[P] 41. Why run self-healing and Alertmanager only on master nodes? What firewall ACL enforces this?
[P] 42. How do you design namespace strategy? Walk me through your namespaces and why each exists separately.
[P] 43. How do you safely promote configuration from dev to prod in Flux without git merge? Why is merge dangerous?
[P] 44. What happens when vault-agent-injector is down during pod creation? How do you prevent this silent failure?
[P] 45. Walk me through StatefulSet volumeClaimTemplates with NFS StorageClass. How does auto-PVC creation work?

---

## 6. Ansible (25 questions)

[G] 1. What is Ansible and how does it differ from Terraform?
[G] 2. What is idempotency? Why does it matter in Ansible?
[G] 3. Explain the difference between a playbook, a role, and a task.
[G] 4. What is Ansible Vault? How do you use it to manage secrets?
[G] 5. How does Ansible connect to remote hosts? What protocols does it use?
[G] 6. What is an inventory file? What's the difference between static and dynamic inventory?
[G] 7. How do you handle errors in a playbook? What is ignore_errors and block/rescue?
[G] 8. What are handlers and when do they trigger?
[G] 9. How do you test Ansible playbooks before running them in production?
[G] 10. What is ansible-pull vs ansible-push mode?
[P] 11. How do you automate FreeIPA client enrollment across VMs and unprivileged LXC containers?
[P] 12. How do you handle Kerberos authentication in LXC containers where UID mapping breaks the default keyring cache?
[P] 13. How do you automate Kubernetes cluster initialization (kubeadm init/join) with multi-master HA?
[P] 14. How do you use hostvars to pass kubeadm join tokens from master1 to other masters and workers?
[P] 15. How do you structure a dual-inventory pattern: bootstrap (IPs + root SSH) vs production (FQDNs + Kerberos)?
[P] 16. How do you keep Vault cluster initialization manual while automating everything else? Where's the split?
[P] 17. How do you use Ansible Vault encrypted vars alongside env var lookups for CI/CD credential rotation?
[P] 18. How do you integrate FreeIPA service principals with Vault TLS certificates via certmonger?
[P] 19. How do you achieve conditional execution based on host virtualization type (LXC-specific vs VM-specific)?
[P] 20. How do you use Jinja2 templates with loops to generate HAProxy backends and Keepalived configs that scale across cluster nodes?
[P] 21. How do you structure FreeIPA domain config (users, groups, HBAC, sudo rules) in a single playbook with proper variable isolation?
[P] 22. How do you use blockinfile with markers to manage Ansible-owned config sections alongside manual edits?
[P] 23. How do you handle DNS fallback so infrastructure survives if FreeIPA goes down? (dns_fallback.yml + k8s_hosts_fallback.yml)
[P] 24. How do you check certificate issuer (not just file existence) to prevent idempotency issues with certmonger cert requests?
[P] 25. How do you use vars_prompt to collect sensitive info at runtime while keeping playbooks non-interactive in CI/CD?

---

## 7. Terraform (24 questions)

[G] 1. What is Terraform state? Why is it important?
[G] 2. What happens if two people run terraform apply at the same time?
[G] 3. What is a remote backend? Why use S3 + DynamoDB for state?
[G] 4. How do you handle secrets in Terraform?
[G] 5. What is terraform import? When would you use it?
[G] 6. What is drift? How does Terraform detect it?
[G] 7. Explain modules. Why would you use them?
[G] 8. What's the difference between terraform plan and terraform apply?
[G] 9. How do you manage multiple environments (dev/prod) in Terraform?
[G] 10. What is the difference between count and for_each?
[G] 11. What happens if you delete a resource from your .tf file but it still exists in AWS?
[G] 12. How do you handle state file corruption or conflicts?
[P] 13. How do you prevent the golden VM template from being accidentally destroyed while letting Terraform manage the source VM?
[P] 14. Why keep dev and prod as two separate Terraform trees instead of using variables or workspaces?
[P] 15. How do you handle mixed-region prod (state backend in eu-west-2, compute in us-east-1)?
[P] 16. Why are K8s worker VMs given a second NIC on VLAN 40 for CSI-NFS instead of using the primary NIC?
[P] 17. How do you inject SSH keys into Proxmox VMs and LXCs at provisioning time via Terraform?
[P] 18. Why is the Route53 private zone (lab.local) necessary in a hybrid setup?
[P] 19. How does the bpg/proxmox LXC provider require template files (not clone-from-ID) for SSH key injection?
[P] 20. Why are prod testing VMs placed in VLAN 55 as throwaway resources for DR testing?
[P] 21. How do you structure secrets_config as a map variable instead of 11 separate variable blocks?
[P] 22. Why keep state backends per-module instead of one shared backend?
[P] 23. How do you handle Terraform state isolation using terraform_remote_state data sources between modules?
[P] 24. Why is Vault managed by Ansible instead of the Terraform vault provider?

---

## 8. Docker (16 questions)

[G] 1. What is a container? How does it differ from a VM?
[G] 2. What is a Dockerfile? Walk me through writing one.
[G] 3. What is a multi-stage build? Why would you use it?
[G] 4. How do Docker layers work? How do you optimize image size?
[G] 5. What is the difference between CMD and ENTRYPOINT?
[G] 6. How does Docker networking work? What's the difference between bridge, host, and none?
[G] 7. A container keeps restarting. How do you debug it?
[G] 8. What are Docker volumes? When would you use a volume vs a bind mount?
[G] 9. What is Docker Compose? When would you use it vs Kubernetes?
[G] 10. How do you scan Docker images for vulnerabilities?
[G] 11. What is a container registry? How do you push/pull images?
[P] 12. How do you tag Docker images differently based on branch (latest for prod, dev for dev)?
[P] 13. How do you automate cleanup of old container images from GHCR to manage storage?
[P] 14. How do you authenticate to GHCR in CI/CD using GITHUB_TOKEN?
[P] 15. How do you version and upgrade custom container images (remediation, etcd-backup) through the GitOps pipeline?
[P] 16. How do you scan and validate Docker images before deploying them via Flux?

---

## 9. CI/CD (27 questions)

[G] 1. Explain a CI/CD pipeline you've built end-to-end.
[G] 2. What's the difference between continuous integration, delivery, and deployment?
[G] 3. How do you handle secrets in a CI/CD pipeline?
[G] 4. What are deployment strategies? Explain rolling, blue-green, and canary.
[G] 5. How do you implement rollback in your pipeline?
[G] 6. What is GitOps? How does it differ from traditional CI/CD?
[G] 7. A deployment failed in production. How does your pipeline handle it?
[G] 8. How do you handle database migrations in a CI/CD pipeline?
[G] 9. What is pipeline as code? Why is it better than UI-configured pipelines?
[P] 10. How do you implement OIDC federation between GitHub Actions and AWS without storing any long-lived credentials?
[P] 11. How do you transfer a keytab from AWS Secrets Manager -> runner -> ansible node over SSH with immediate cleanup?
[P] 12. How do you implement concurrency locks in GitHub Actions using repository variables?
[P] 13. How do you chain GitHub Actions jobs with conditional execution so skipped jobs don't block downstream?
[P] 14. How do you implement a manual approval gate with a 3-minute sleep between terraform plan and apply?
[P] 15. How do you mask composite secrets in GitHub Actions before parsing with jq?
[P] 16. How do you generate SSH keys on a newly-created node and store the public key in Secrets Manager for downstream workflows?
[P] 17. How do you add a deploy key to a GitHub repo programmatically from CI/CD so Ansible can clone via SSH?
[P] 18. How do you pass sensitive environment variables to a remote SSH command while masking them in logs?
[P] 19. How do you guarantee cleanup steps (kdestroy) run even if earlier workflow steps fail? What's the always() + || true pattern?
[P] 20. How do you use path-based workflow triggers to ensure workflows only run when relevant files change?
[P] 21. How do you implement a wait-for-SSH retry loop after provisioning infrastructure in a workflow?
[P] 22. How do you use sshpass for initial SSH to newly-provisioned nodes that don't yet have SSH keys?
[P] 23. How do you use password-based SSH during provisioning, then switch to key-based after setup?
[P] 24. Why separate the GitHub Actions runner LXC from the Ansible control node LXC? What's the blast radius argument?
[P] 25. How do you register and auto-configure a self-hosted GitHub Actions runner via CI/CD?
[P] 26. What's the difference between running Terraform on a cloud runner (Mac Mini) vs internal runner (local-runner LXC)?
[P] 27. How do you share state between workflows using AWS Secrets Manager (SSH public key generated in one, fetched in next)?

---

## 10. Monitoring (21 questions)

[G] 1. What is Prometheus? How does its pull model work?
[G] 2. What is Grafana and how does it integrate with Prometheus?
[G] 3. What is Alertmanager? How do you configure alert routing?
[G] 4. What's the difference between monitoring and observability?
[G] 5. What are the three pillars of observability? (metrics, logs, traces)
[G] 6. How do you monitor a Kubernetes cluster?
[G] 7. What is a node exporter? What metrics does it provide?
[G] 8. An alert is firing but the service seems fine. How do you investigate?
[G] 9. How do you handle alert fatigue? What strategies reduce noise?
[G] 10. What is PromQL? Give an example of a useful query.
[G] 11. How do you monitor disk, CPU, and memory on Linux servers?
[P] 12. How do you decouple Alertmanager from the Prometheus chart to inject Vault-templated SMTP credentials?
[P] 13. How do you collect Kubernetes events as metrics without overloading logs? (event-exporter -> Loki)
[P] 14. How do you use Promtail to ship logs from /var/log/pods/ to Loki with label extraction?
[P] 15. Walk me through your three alert paths: Prometheus -> Alertmanager, remediation pod -> Alertmanager, host scripts -> postfix.
[P] 16. How does Alertmanager inhibition prevent alert storms? Walk me through your routing configuration.
[P] 17. Why run single-replica Grafana instead of HA? What breaks with SQLite on NFS with multiple writers?
[P] 18. How do you monitor a worker node going unhealthy? What signals does the remediation pod watch?
[P] 19. What's the IO storm watchdog evidence email? What data does it include and why?
[P] 20. How does the remediation pod distinguish between "Kubernetes can heal this" and "I need to act at the VM layer"?
[P] 21. How do you configure scrape targets for external infrastructure (Vault VMs, FreeIPA, nginx) outside the cluster?

---

## 11. Networking (27 questions)

[G] 1. Explain the OSI model. What happens at each layer?
[G] 2. What happens when you type a URL in the browser?
[G] 3. What is DNS? Walk me through a DNS resolution.
[G] 4. What's the difference between TCP and UDP?
[G] 5. Explain the TCP three-way handshake.
[G] 6. What is a VLAN? Why would you use it?
[G] 7. What is NAT? Explain SNAT and DNAT.
[G] 8. What is a VPN? How does WireGuard compare to IPSec?
[G] 9. What's the difference between a router and a switch?
[G] 10. How do you troubleshoot network connectivity? (ping, traceroute, dig, ss, tcpdump)
[G] 11. What is a firewall? Explain stateful vs stateless.
[G] 12. What is subnetting? Explain CIDR notation.
[G] 13. What's the difference between L4 and L7 load balancing?
[G] 14. What is ARP? How does MAC address resolution work?
[G] 15. A server can ping localhost but not external IPs. What do you check?
[P] 16. How do you place WireGuard tunnel IPs inside the VPC CIDR range? What routing problem does this solve?
[P] 17. Your prod WireGuard tunnel ran 5 days with zero handshake while dev worked fine. How did you diagnose ISP CGNAT blocking?
[P] 18. Why did you implement asymmetric keepalive (AWS pings on-prem, not reverse) for WireGuard NAT timeout prevention?
[P] 19. Walk me through your 13-VLAN design. Why VLANs even when router ACLs allow most to talk?
[P] 20. Why did you rewire service VLANs to bypass the FS308GP switch and go directly to MikroTik?
[P] 21. How do you keep storage VLAN 40 at L2 on the switch while routing service VLANs through the router?
[P] 22. Your consumer WiFi AP can't pass VLAN tags over 802.11. How do you compensate for losing management VLAN separation?
[P] 23. How do you enforce absolute dev <-> prod isolation at the router level regardless of intra-env ACL policy?
[P] 24. Why did you replace TP-Link ER605 with MikroTik? What diagnostic capability gap was the final decider?
[P] 25. Cross-subnet VPN routing failed because /16 on the WireGuard interface hijacked the entire VPC CIDR. What's the fix?
[P] 26. How do you use VLAN 99 as a dump VLAN for trunk port native traffic instead of VLAN 1?
[P] 27. How do you configure per-VLAN DHCP servers with per-environment DNS (dev VLANs -> dev FreeIPA, prod -> prod FreeIPA)?

---

## 12. Virtualization / NAS (20 questions)

[G] 1. What's the difference between Type 1 and Type 2 hypervisors?
[G] 2. How does a VM differ from a container?
[G] 3. What is live migration (vMotion)? How does it work?
[G] 4. What is a VM snapshot? How does it differ from a backup?
[G] 5. What is thin provisioning vs thick provisioning?
[G] 6. Explain NFS. How does it work at the network level?
[G] 7. What's the difference between NFSv3 and NFSv4?
[G] 8. What is NFS hard mount vs soft mount? When would you use each?
[G] 9. What is a golden image/template? How do you manage VM templates?
[G] 10. What is LVM? How does thin provisioning work at the storage level?
[P] 11. Why keep OS disks on local NVMe instead of NAS? What workload specifically needs local disk latency? (etcd)
[P] 12. Walk me through QEMU-mediated NFS vs direct NFS mount. The VM thinks it's local SCSI, but QEMU translates to NFS.
[P] 13. Why do k8s workers get a dedicated second VLAN 40 NIC instead of proxying NFS through Proxmox?
[P] 14. You're not running Proxmox Backup Server. Walk me through your two-part backup approach (config tarball + vzdump).
[P] 15. Your backup job has repeat-missed = 1. What problem does this solve for laptop-based Proxmox?
[P] 16. You changed backup retention from 2 to 5. What incident taught you that two wasn't enough?
[P] 17. Why exclude k8s nodes from dev backups but include them in prod? What's the hardware difference?
[P] 18. Walk me through a complete Proxmox host recovery from bare metal. What are the phases?
[P] 19. What's the observed compression ratio for different VM types? Why are k8s workers 97% sparse?
[P] 20. How do you set up IO throttle limits per VM on shared NVMe storage? Why don't throttles prevent storms?

---

## 13. Git (14 questions)

[G] 1. What is the difference between merge and rebase?
[G] 2. How do you resolve a merge conflict?
[G] 3. What is a detached HEAD state?
[G] 4. What's the difference between git reset, git revert, and git checkout?
[G] 5. Explain branching strategies. What is GitFlow? Trunk-based development?
[G] 6. What is git stash and when would you use it?
[G] 7. How do you undo the last commit without losing changes?
[G] 8. What is cherry-pick? When would you use it?
[G] 9. What is the difference between fetch and pull?
[P] 10. You force-pushed rewritten history to a Flux-tracked production branch from a checkout weeks behind origin. What happened?
[P] 11. After squash-merging a long-lived feature branch, every subsequent merge causes conflicts. Why does squash break Git's tracking?
[P] 12. How do you structure a one-way copy pattern for promoting configs between dev and prod without git merge?
[P] 13. Why does your project use no feature branches, no Linear board, and un-cleaned commits? What's the reasoning?
[P] 14. How did a git history rewrite (filter-repo) cause a full cluster outage? What pre-flight checks would prevent it?

---

## 14. Python (12 questions)

[G] 1. How do you run a shell command from Python?
[G] 2. What is a virtual environment? Why use one?
[G] 3. How do you read and parse a JSON file in Python?
[G] 4. What is the difference between a list and a dictionary?
[G] 5. How do you handle exceptions in Python?
[G] 6. How do you make an HTTP API call in Python?
[G] 7. Write a script that reads a log file and counts error occurrences.
[G] 8. What are f-strings? How do you format output?
[G] 9. How do you work with files in Python? (open, read, write, context managers)
[P] 10. You're rewriting the remediation pod logic from bash to Python. What advantages does Python give for Kubernetes API interaction?
[P] 11. How would you use the kubernetes Python client to watch node Ready status and call the Proxmox API for reboot/reset?
[P] 12. How do you handle exception management for API calls that may timeout (Vault, Proxmox, Kubernetes) in a self-healing loop?

---

## 15. Backup & DR (23 questions)

[G] 1. What is RPO and RTO? How do you determine them for a system?
[G] 2. What's the difference between a backup and a snapshot?
[G] 3. Explain your backup strategy for your infrastructure.
[G] 4. What is the 3-2-1 backup rule?
[G] 5. How do you test your disaster recovery plan?
[G] 6. What's the difference between hot, warm, and cold DR sites?
[G] 7. How do you handle backup retention policies?
[G] 8. A restore failed. How do you troubleshoot?
[P] 9. Walk me through the etcd backup pipeline: CronJob schedule -> vault-agent-init -> AWS temp creds -> etcdctl snapshot -> S3 upload.
[P] 10. When you lose quorum on a 3-node etcd cluster, what's the recovery path? Is it different from single-node failure?
[P] 11. How do you recover a Vault cluster that lost Raft quorum? What happens to pods requesting secrets during quorum loss?
[P] 12. What happens when a Vault node loses AWS KMS credentials? Does it stay sealed or fail to start?
[P] 13. What's your recovery order when DNS (FreeIPA) goes down? How do you restore Vault access without DNS?
[P] 14. When 2 of 3 masters go down, why does kubectl hang instead of giving an error? What's happening in etcd?
[P] 15. Your storage class uses soft mount for WordPress but hard mount for MariaDB. What happens when NAS goes offline for 10+ minutes?
[P] 16. When a worker's NFS interface goes down but the node stays up, how do you prevent broken pods from being routed traffic?
[P] 17. What's the race condition between vault-agent-injector and pod restarts? What happens when the webhook is down during pod creation?
[P] 18. When disk fills to 100% on a worker, what evicts first — the monitoring agent or the pods? Why is this a blind spot?
[P] 19. FreeIPA is down. KMS fails. Pods can't get secrets. Remediation needs Vault secrets. How do you break this circular dependency?
[P] 20. Describe the event flow: disk pressure -> kubelet image GC -> eviction manager -> critical pod protection.
[P] 21. Your remediation detects stopped VMs and auto-starts them in ~4 minutes. Is that faster or slower than K8s pod eviction timeout?
[P] 22. How do you validate etcd backups end-to-end before you ever need to restore? What did you verify?
[P] 23. Walk me through the complete failure chain: master loses connectivity -> API server -> etcd -> DNS -> Calico. What still works?

---

## 16. Identity Management / Directory Services — FreeIPA (26 questions)

[G] 1. What is a directory service? What problem does it solve?
[G] 2. What is the difference between authentication and authorization?
[G] 3. What is LDAP? How does it work?
[G] 4. What is Kerberos? Explain TGT and service tickets.
[G] 5. What is a keytab? How does it differ from a password?
[G] 6. What is SSO (Single Sign-On)? How does Kerberos enable it?
[G] 7. What is HBAC (Host-Based Access Control)? How do you restrict which users can access which hosts?
[G] 8. How do you manage sudo rules centrally?
[G] 9. What is SSSD? What does it do on the client side?
[G] 10. What happens when a user is deleted from the directory? How fast does it propagate?
[G] 11. How do you join a Linux machine to a domain?
[G] 12. What is DNS in the context of identity management? Why does FreeIPA run its own DNS?
[G] 13. What is a service principal? When would you create one?
[G] 14. How does certificate management work in FreeIPA? What is certmonger?
[G] 15. What is the difference between FreeIPA and Active Directory?
[G] 16. How would you migrate from AD to FreeIPA or integrate both?
[G] 17. A user can authenticate but can't SSH to a specific host. What do you check?
[G] 18. How do you handle service accounts? How are they different from user accounts?
[P] 19. Walk me through Vault's LDAP authentication. How does a human logging in trigger an LDAP bind to FreeIPA?
[P] 20. You have three separate PKIs: FreeIPA CA, Kubernetes internal CA, etcd CA. What does each sign and do they trust each other?
[P] 21. How did you fix vault-agent TLS when the cert didn't have the VIP hostname in its SAN? How do you get FreeIPA to sign a SAN that isn't the node's own hostname?
[P] 22. How do you prevent a circular dependency when FreeIPA is the identity provider but you need to manage FreeIPA itself?
[P] 23. How do you set up passwordless sudo for automation bots while maintaining password-based sudo for human admins?
[P] 24. SSSD caches sudo rules every ~15 minutes. How fast can you force immediate revocation when you remove a rule from FreeIPA?
[P] 25. LXC containers fail password auth for FreeIPA users but GSSAPI works. The kernel keyring UID is mismatched. What's the fix?
[P] 26. What happens when you delete a Kerberos keytab from Secrets Manager? Walk me through which pipeline step fails and why.

---

## BONUS: HashiCorp Vault (18 questions)

[G] 1. What is HashiCorp Vault? Why use it over storing secrets in env vars?
[G] 2. What is the unseal process? Why does Vault need to be unsealed?
[G] 3. What is auto-unseal with KMS? How does it work?
[G] 4. Explain Vault's layered encryption (master key -> encryption key -> secrets).
[G] 5. What auth methods does Vault support? How does LDAP auth work?
[G] 6. What are dynamic secrets? How do they differ from static secrets?
[G] 7. How do you inject Vault secrets into Kubernetes pods?
[G] 8. What is a Vault policy? How do you scope access?
[P] 9. Walk me through the complete Vault unseal chain: startup -> KMS call -> master key decryption -> encryption key -> secrets available.
[P] 10. Your vault.env file contains plaintext AWS credentials on each Vault node. What security controls make this acceptable?
[P] 11. How are the 5 recovery keys stored and used? When would you use them instead of KMS?
[P] 12. How do you use FreeIPA certificates (via certmonger) for Vault TLS with automatic renewal?
[P] 13. How do you set up Vault's AWS Secrets Engine for etcd-backup with the chain: K8s ServiceAccount -> Vault role -> AWS IAM AssumeRole?
[P] 14. How does Vault verify a Kubernetes pod is real? Walk me through the TokenReview API call.
[P] 15. How do you template entire config files using Vault secrets at pod startup (Golang template rendering)?
[P] 16. What's the vault-auth token you use for K8s TokenReview? Why is it long-lived (30,000 hours) and what's the blast radius if stolen?
[P] 17. How do you handle CA certificate trust between Kubernetes and an external Vault cluster? (vault-ca Secret pattern)
[P] 18. Walk me through the three layers of encryption: Vault master key by KMS, secrets by Vault encryption key, and TLS for network.

---

## Summary

| # | Skill | Generic | Project | Total |
|---|-------|---------|---------|-------|
| 1 | Linux Admin | 20 | 12 | 32 |
| 2 | Troubleshooting / RCA | 7 | 15 | 22 |
| 3 | Bash Scripting | 10 | 8 | 18 |
| 4 | AWS | 15 | 15 | 30 |
| 5 | Kubernetes | 20 | 25 | 45 |
| 6 | Ansible | 10 | 15 | 25 |
| 7 | Terraform | 12 | 12 | 24 |
| 8 | Docker | 11 | 5 | 16 |
| 9 | CI/CD | 9 | 18 | 27 |
| 10 | Monitoring | 11 | 10 | 21 |
| 11 | Networking | 15 | 12 | 27 |
| 12 | Virtualization / NAS | 10 | 10 | 20 |
| 13 | Git | 9 | 5 | 14 |
| 14 | Python | 9 | 3 | 12 |
| 15 | Backup & DR | 8 | 15 | 23 |
| 16 | Identity / Directory | 18 | 8 | 26 |
| B | HashiCorp Vault | 8 | 10 | 18 |
| | **TOTAL** | **202** | **198** | **400** |

Sources (generic):
  - GeeksforGeeks DevOps/K8s/Linux/AWS Interview Questions (2025)
  - DataCamp Kubernetes + Terraform Interview Questions (2026)
  - LivingDevops Scenario-Based K8s + Terraform Questions
  - DevOps Training Institute Linux/Vault/CI-CD Scenarios (2025)
  - Medium — Networking for DevOps, SRE Prometheus, AWS Scenarios
  - GitHub NotHarshhaa/DevOps-Interview-Questions (1100+)
  - InterviewBit Docker/Linux/Git Questions
  - ThinkCloudly CI/CD Real-World Scenarios

Sources (project-specific):
  - terraform/dev + terraform/prod — all .tf files, provider configs, modules
  - ansible/dev + ansible/prod — all playbooks, roles, templates, inventories, guides
  - proxmox/ — bootstrap, golden templates, storage, backup, disaster recovery scripts
  - kubernetes/ — all manifests, Flux configs, Helm values, DESIGN.md files
  - .github/workflows/ — all workflow YAML files, variables-secrets.md, runner docs
  - troubleshooting/ — 114+ resolved TS cases across all domains
  - network/ — router, switch, AP, VPN configs, DESIGN.md, ip-planning.txt
  - disaster-recovery/ — DR runbooks, chaos test scenarios, recovery guides
  - technical-papers/ — all chunk papers and signal flow traces
  - local-docs/massive-review/security/ — chapters 1-5, CA analysis
  - deployment-docs/ — all 11 setup guides, signal flows, workflow guides
  - workstation/ — SSH config, route-setup, VPN endpoint configs
