# Troubleshooting Cases

Documentation of issues encountered and resolved during hybrid cloud infrastructure operations (Proxmox iteration).

Each subfolder contains troubleshooting cases numbered sequentially within that category. Reference guides and non-incident documentation live in `reference/` subfolders.

**Total: 97 issues + 14 reference guides across 10 categories**

---

## Critical Incidents

Issues with system-wide blast radius, cascading failures, or data integrity risk.

| Ticket | Category | What Happened | Blast Radius |
|--------|----------|---------------|-------------|
| [TS-K8S-019](kubernetes/19-flux-kustomization-restructure-cascade-failure.md) | Kubernetes | Kustomization rename with prune:true deleted ALL HelmReleases including Vault — complete cluster deadlock | Full cluster |
| [TS-K8S-042](kubernetes/42-flux-retry-storm-cluster-outage.md) | Kubernetes | Grafana anti-affinity → Helm timeout → Flux retry loop → etcd leader election failure → API servers down | Full cluster |
| [TS-K8S-022](kubernetes/22-worker-node-failure-cascading-pod-failures.md) | Kubernetes | Worker2 failure cascaded into StatefulSet split-brain, Vault injector race, CSI mount failures | Multi-component |
| [TS-K8S-043](kubernetes/43-noexecute-taint-not-applied.md) | Kubernetes | Pods NOT evicted from unreachable nodes — K8s PartialDisruption rate-limiting silently blocked NoExecute | Cluster reliability |
| [TS-K8S-044](kubernetes/44-coredns-ha-masters.md) | Kubernetes | Both CoreDNS pods scheduled on same nodes that failed → complete DNS outage | Full cluster DNS |
| [TS-K8S-015](kubernetes/15-csi-nfs-restart-stale-mount-mariadb-crash.md) | Kubernetes | CSI NFS DaemonSet restart made mounts stale → MariaDB CrashLoopBackOff | Storage + database |
| [TS-K8S-013](kubernetes/13-k8s-master-node-resource-exhaustion.md) | Kubernetes | Master node unresponsive — 244MB available memory | Control plane |
| [TS-K8S-030](kubernetes/30-worker3-memory-exhaustion-vm-crash.md) | Kubernetes | Worker3 VM crashed twice in 2 hours — insufficient memory, no swap | Cluster node |
| [TS-TF-002](terraform/2-aws-secrets-deletion-incident.md) | Terraform | Workflow nuked all AWS secrets, state file corrupted 14KB → 299 bytes | AWS credentials + state |
| [TS-PVE-014](proxmox/14-worker-vm-crash-unknown-root-cause.md) | Proxmox | Worker VM crashed on autostart — 3-part investigation revealed remediation pod triggering reboot during boot | Cluster node |
| [TS-PVE-015](proxmox/15-proxmox-crash-during-backup-unknown-cause.md) | Proxmox | Host crashed silently during backup — hardware-level crash, no logs, unresolved | Full host |
| [TS-PVE-017](proxmox/17-proxmox-host-cpu-io-spike-vms-stuck.md) | Proxmox | CPU/IO spike during DR testing — all VMs hung at boot screen | Full infrastructure |
| [TS-VLT-003](vault/3-vault-kms-credentials-overwrite-empty-vars.md) | Vault | Manual playbook run rendered empty vars → AWS KMS credentials wiped → Vault can't start | Secrets management |
| [TS-NET-004](network/4-wireguard-cgnat-port-blocking.md) | Network | WireGuard prod tunnel down 5 days — ISP CGNAT blocking port | Site-to-site connectivity |
| [TS-LNX-003](linux/3-linux-nodes-dns-fallback.md) | Linux | zzz-ipa.conf overwrites fallback DNS → Vault can't reach AWS KMS on IPA outage | DR capability |

---

## Cases by Category

### Kubernetes — 40 issues ([reference/](kubernetes/reference/) has 8 guides)

**High:**

| # | File | What Happened |
|---|------|---------------|
| 1 | [1-pod-eviction-race-condition](kubernetes/1-k8s-pod-eviction-race-condition-router-outage.md) | Millisecond race between node recovery and taint eviction |
| 3 | [3-nfs-hard-mount](kubernetes/3-nfs-hard-mount-pod-unresponsiveness.md) | Hard NFS mount hung pods indefinitely |
| 5 | [5-nfs-csi-storageclass](kubernetes/5-nfs-csi-storageclass-invalid-parameter-flux-stuck.md) | Invalid StorageClass param blocked all PVC provisioning |
| 7 | [7-mariadb-innodb-nfs](kubernetes/7-mariadb-innodb-nfs-table-creation-failure.md) | InnoDB O_DIRECT incompatible with NFS |
| 11 | [11-wordpress-plugin](kubernetes/11-wordpress-plugin-version-incompatibility-blank-page.md) | Plugin version mismatch → blank page |
| 14 | [14-vault-k8s-auth](kubernetes/14-vault-k8s-auth-service-account-not-authorized.md) | Grafana stuck Init — wrong ServiceAccount in Vault config |
| 18 | [18-csi-nfs-controller](kubernetes/18-csi-nfs-controller-cannot-provision-pvc-network-isolation.md) | CSI controller on masters had no route to NFS |
| 20 | [20-grafana-loki](kubernetes/20-grafana-loki-version-incompatibility.md) | Grafana 12.x query syntax broke against Loki 2.x |
| 28 | [28-nginx-proxy-body-size](kubernetes/28-nginx-proxy-body-size-413-error.md) | 413 errors — external nginx missing body size config |
| 29 | [29-wordpress-readiness-probe](kubernetes/29-wordpress-readiness-probe-nfs-detection.md) | Readiness probe checked local FS, not NFS → 33% request failures |
| 33 | [33-vault-agent-dns](kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md) | IPA DNS down → new pods can't start (Vault auth blocked) |
| 34 | [34-wordpress-external-dns](kubernetes/34-wordpress-external-dns-slowness.md) | IPA outage → 4-12s delays + Flux/Helm failures |
| 36b | [36-grafana-antiaffinity](kubernetes/36-grafana-antiaffinity-rollout-stuck.md) | Anti-affinity too strict → rolling update blocked |
| 37 | [37-grafana-dashboards-sqlite](kubernetes/37-grafana-dashboards-missing-sqlite-corruption.md) | 3 Grafana replicas writing SQLite over NFS → corruption |

**Medium:**

| # | File | What Happened |
|---|------|---------------|
| 2 | [2-calico-bgp-wrong-interface](kubernetes/2-calico-bgp-wrong-interface-multi-nic.md) | BGP peered on storage NIC |
| 4 | [4-nfs-pv-reclaimpolicy](kubernetes/4-nfs-pv-reclaimpolicy-delete-failed-no-provisioner.md) | Static PV entered Failed state |
| 10 | [10-wordpress-admin-password](kubernetes/10-wordpress-admin-password-hash-reset.md) | Admin login failed with correct password |
| 12 | [12-flux-crd-dependency](kubernetes/12-flux-kustomization-crd-dependency-failure.md) | ServiceMonitor failed — CRD not yet installed |
| 16 | [16-pod-priority-classes](kubernetes/16-pod-priority-classes-dr-readiness.md) | No priority classes = wrong eviction order |
| 17 | [17-vault-injection-namespace](kubernetes/17-vault-injection-system-namespace-denied.md) | Vault webhook blocked kube-system deployment |
| 21 | [21-remediation-pod](kubernetes/21-remediation-pod-stopped-vm-api-error.md) | Remediation crashed on already-stopped VM |
| 25 | [25-promtail-vault-logs](kubernetes/25-promtail-vault-namespace-logs.md) | Promtail not collecting Vault logs — inconclusive |
| 26 | [26-released-pvs](kubernetes/26-released-pvs-cleanup.md) | Orphaned PVs wasting storage |
| 27 | [27-wordpress-php-upload](kubernetes/27-wordpress-php-upload-limits.md) | 2MB upload limit — missing PHP config |
| 38 | [38-qemu-guest-agent](kubernetes/38-qemu-guest-agent-cpu-loop.md) | qemu-ga busy loop eating 98% CPU |
| 39 | [39-kube-system-targetdown](kubernetes/39-kube-system-targetdown-false-positives.md) | Prometheus false alerts — kubeadm localhost metrics |
| 40 | [40-hpa-memory-scaling](kubernetes/40-hpa-memory-scaling-behavior.md) | HPA triggered wrong — misunderstood % calculation |
| 41 | [41-prometheusrule](kubernetes/41-prometheusrule-not-picked-up.md) | Custom alerts missing — wrong label selector |
| 45 | [45-csi-nfs-port-conflict](kubernetes/45-csi-nfs-controller-port-conflict.md) | CSI controller CrashLoop — port conflict, no anti-affinity |
| 46 | [46-kustomization-stale-ref](kubernetes/46-kustomization-stale-resource-reference.md) | Flux broke after file consolidation |
| 47 | [47-csi-nfs-podlabels](kubernetes/47-csi-nfs-podlabels-silent-accept.md) | Helm silently accepted unsupported chart values |

**Low:**

| # | File | What Happened |
|---|------|---------------|
| 23 | [23-kustomization-resource](kubernetes/23-kustomization-resource-not-removed.md) | Test resource left in prod kustomization |
| 48 | [48-prometheus-pvc-nfs](kubernetes/48-prometheus-pvc-nfsv4-version-mismatch.md) | NFS version drift after StorageClass update |

---

### Proxmox — 15 issues ([reference/](proxmox/reference/) has 1 guide)

**High:**

| # | File | What Happened |
|---|------|---------------|
| 1 | [1-proxmox-node-rename](proxmox/1-proxmox-node-rename.md) | Hostname change broke pmxcfs cluster filesystem |
| 6 | [6-lxc-mount-backup](proxmox/6-lxc-mount-point-backup-disabled.md) | Terraform defaulted backup=false — mount data silently unprotected |
| 9 | [9-nfs-shutdown-hang](proxmox/9-nfs-shutdown-hang-stor0-hotswap.md) | Hard NFS mount froze shutdown indefinitely |
| 10 | [10-vm-restore-hang](proxmox/10-vm-restore-hang-concurrent-nfs-operations.md) | 6 concurrent restores overwhelmed NFS — orphaned LVM volumes |
| 13 | [13-ups-monitor](proxmox/13-ups-monitor-cronjob-misconfiguration.md) | UPS monitor running weekly instead of every 5min |

**Medium:**

| # | File | What Happened |
|---|------|---------------|
| 2 | [2-ssl-certificate](proxmox/2-proxmox-ssl-certificate.md) | SSL SAN had wrong IP after IP change |
| 3 | [3-vm-ssh-cloud-init](proxmox/3-vm-ssh-permission-denied-cloud-init.md) | Domain users couldn't SSH — password auth disabled |
| 4 | [4-lxc-snapshot-nfs](proxmox/4-proxmox-lxc-snapshot-nfs-mount.md) | LXC snapshots failed on NFS-backed storage |
| 5 | [5-backup-missed](proxmox/5-proxmox-backup-missed-not-retried.md) | Backups skipped when node offline — missing repeat-missed flag |
| 7 | [7-crontab-overwrite](proxmox/7-crontab-overwrite-recovery.md) | Cron jobs wiped — `crontab -` replaced instead of appended |
| 8 | [8-lvm-thin-pool](proxmox/8-lvm-thin-pool-resize-overcommit.md) | Thin pool 97% assigned, no auto-extend |
| 11 | [11-vmbr1-storage](proxmox/11-vmbr1-storage-network-for-k8s-workers.md) | Workers couldn't reach storage VLAN |
| 12 | [12-vm-autostart-nfs](proxmox/12-vm-autostart-timeout-nfs-disk-not-ready.md) | VM autostart failed — NFS not ready |

---

### Terraform — 10 issues ([reference/](terraform/reference/) has 1 guide)

**High:**

| # | File | What Happened |
|---|------|---------------|
| 1 | [1-golden-image](terraform/1-proxmox-golden-image-terraform.md) | Provider failed to import QCOW2 images |
| 3 | [3-lxc-clone-ssh](terraform/3-terraform-proxmox-lxc-clone-ssh-keys.md) | LXC clones can't accept SSH keys via Proxmox API |
| 10 | [10-cloud-init-host-keys](terraform/10-cloud-init-ssh-host-key-regeneration.md) | Cloud-init regenerated host keys — broke all SSH known_hosts |

**Medium:**

| # | File | What Happened |
|---|------|---------------|
| 4 | [4-vm-disk-tracking](terraform/4-terraform-proxmox-cloned-vm-disk-tracking.md) | Cloned VM disk state empty in tfstate |
| 5 | [5-lxc-mount-bug](terraform/5-terraform-proxmox-lxc-mount-point-bug.md) | Mount point silently failed to create |
| 6 | [6-route-table-inline](terraform/6-route-table-inline-vs-resource.md) | Inline route blocks removed other module's routes |
| 7 | [7-sg-rename-stuck](terraform/7-terraform-security-group-rename-stuck.md) | SG rename stuck — can't delete while attached to ENI |
| 9 | [9-cloud-init-update](terraform/9-terraform-cloud-init-update-behavior.md) | Cloud-init update failed — ide2 can't hotplug |
| 11 | [11-orphaned-disks](terraform/11-terraform-orphaned-disks-after-removal.md) | Provider removed from state but left 720GB+ orphaned on disk |

---

### GitHub — 7 issues ([reference/](github/reference/) has 3 security audit docs)

**High:**

| # | File | What Happened |
|---|------|---------------|
| 1 | [1-runner-stuck](github/1-github-runner-stuck-job.md) | Runner not persistent after reboot |
| 2 | [2-workflow-lock](github/2-workflow-lock-flag-pattern.md) | Push-triggered workflows destroy/recreate resources |
| 8 | [8-branch-merge-conflicts](github/8-git-branch-merge-conflicts-flux-gitops.md) | Two-way merge between env branches = cascading conflicts |

**Medium:**

| # | File | What Happened |
|---|------|---------------|
| 5 | [5-clock-skew](github/5-runner-clock-skew-auth-failure.md) | DNS broke → NTP broke → clock drifted 2h → OAuth rejected |
| 7 | [7-concurrent-workflow](github/7-concurrent-terraform-workflow-lxc-reboot.md) | Concurrent workflows rebooted containers mid-playbook |
| 10 | [10-squash-merge](github/10-squash-merge-causes-recurring-conflicts.md) | Squash merge broke tracking on long-lived branches |

**Low:**

| # | File | What Happened |
|---|------|---------------|
| 9 | [9-wrong-user](github/9-commit-attributed-to-wrong-user.md) | Tablet had no git config — commits attributed to random user |

---

### Identity — 9 issues

**High:**

| # | File | What Happened |
|---|------|---------------|
| 2 | [2-dns-forwarders](identity/2-freeipa-dns-configuration-issues.md) | Clients can't resolve external DNS — BIND recursion denied |
| 6 | [6-lxc-uid-range](identity/6-freeipa-lxc-uid-range-investigation.md) | FreeIPA UID range outside LXC mapped range |
| 8 | [8-keytab-preauth](identity/8-keytab-preauthentication-failed.md) | ipa-getkeytab without -r broke password auth |

**Medium:**

| # | File | What Happened |
|---|------|---------------|
| 1 | [1-lxc-kerberos-keyring](identity/1-lxc-kerberos-keyring-auth-failure.md) | LXC UID namespace broke kernel keyring for Kerberos |
| 3 | [3-gssapi-hostname](identity/3-kerberos-gssapi-requires-hostnames.md) | GSSAPI requires FQDNs, not IPs |
| 5 | [5-server-sssd-sudo](identity/5-freeipa-server-sssd-sudo.md) | FreeIPA server doesn't apply its own SSSD rules |
| 7 | [7-ntp-lxc-skip](identity/7-freeipa-client-ntp-lxc-skip.md) | chronyd can't run in unprivileged LXC |
| 9 | [9-sssd-knownhosts-timeout](identity/9-ansible-sssd-knownhosts-timeout.md) | 28-34s Ansible delays when IPA down |

**Low:**

| # | File | What Happened |
|---|------|---------------|
| 4 | [4-password-policy](identity/4-freeipa-password-policy-cospriority.md) | Missing undocumented cospriority parameter |

---

### Vault — 5 issues

**High:**

| # | File | What Happened |
|---|------|---------------|
| 5 | [5-node-recovery](vault/5-vault-node-recovery-stale-raft-data.md) | Stale raft data after Proxmox crash — node can't rejoin |

**Medium:**

| # | File | What Happened |
|---|------|---------------|
| 1 | [1-cluster-setup](vault/1-vault-cluster-initial-setup-investigation.md) | 8 sequential deployment issues |
| 2 | [2-vip-certificate](vault/2-freeipa-vip-certificate-san-managedby.md) | Certificate SAN rejected — missing managedby |
| 4 | [4-agent-injector-tls](vault/4-vault-agent-injector-k8s-tls-ca-setup.md) | 7 TLS/template errors during agent injection |

---

### Network — 5 issues

**High:**

| # | File | What Happened |
|---|------|---------------|
| 5 | [5-wireguard-stability](network/5-wireguard-tunnel-stability-investigation.md) | ISP randomly blocks AWS Elastic IPs |

**Medium:**

| # | File | What Happened |
|---|------|---------------|
| 1 | [1-static-route-ssh](network/1-static-route-ssh-disconnect.md) | SSH drops after 30s via ISP router |
| 2 | [2-asymmetric-routing](network/2-asymmetric-routing-ssh-wan-lan.md) | SSH hangs from WAN — return path asymmetry |
| 3 | [3-network-instability](network/3-svc-network-instability-investigation.md) | USB-Ethernet driver bound to wrong kernel module |

---

### Linux — 4 issues

**Medium:**

| # | File | What Happened |
|---|------|---------------|
| 1 | [1-dnf-metadata](linux/1-rocky-linux-dnf-metadata-error.md) | Mirrorlist returning HTML instead of XML |
| 2 | [2-chronyd-lxc](linux/2-lxc-chronyd-adjtimex-failure.md) | chronyd permission denied on LXC |

**Low:**

| # | File | What Happened |
|---|------|---------------|
| 4 | [4-cloud-init-hosts](linux/4-cloud-init-etc-hosts-ownership.md) | cloud-init wipes /etc/hosts on reboot |

---

### macOS — 1 issue ([reference/](macos/reference/) has 1 guide)

| # | File | What Happened |
|---|------|---------------|
| 1 | [1-local-network-permission](macos/1-macos-local-network-permission.md) | macOS privacy blocking local network access |

---

### AWS — 1 issue

| # | File | What Happened |
|---|------|---------------|
| 1 | [1-cfn-iam-policy](aws/1-cloudformation-iam-policy-replacement-failure.md) | CFN can't replace named IAM policy — create-before-delete fails |

---

## Template Structure

All cases follow a standardized 9-point template:

| Section | Description |
|---------|-------------|
| **1. Context** | System, environment, related components |
| **2. Issue** | Symptom, error messages, impact |
| **3. Analysis** | Investigation steps with commands/outputs |
| **4. Root Cause** | Why the issue occurred |
| **5. Solution** | Fix steps, files changed, prevention |
| **6. Solution Risk** | Risk level, potential impact |
| **7. Impact After Fix** | Observed results |
| **8. Notes** | Lessons learned, commands reference |
| **9. Workaround** | Temporary fixes if needed |

**Header Format:** `# TS-XXX-NNN | YYYY-MM-DD | STATUS`

---

## Status Definitions

| Status | Meaning |
|--------|---------|
| RESOLVED | Issue fixed, root cause identified |
| IN PROGRESS | Investigation or fix ongoing |
| MONITORING | Workaround applied, watching for recurrence |
| SUSPENDED | Partially investigated, paused for later |
| OPEN | Issue identified, not yet resolved |

---

## Naming Convention

Files follow the format: `N-short-description.md`

- `N` = sequential number within the subfolder
- Numbers assigned chronologically by incident date
- Each subfolder maintains its own sequence
