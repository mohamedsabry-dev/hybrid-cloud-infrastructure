# Troubleshooting Cases

Issues encountered and resolved during hybrid cloud infrastructure operations (Proxmox iteration).

**99 cases + 14 reference guides across 10 categories** — [9 open](OPEN-TICKETS.md)

```
troubleshooting/
├── OPEN-TICKETS.md              # Non-resolved ticket tracker
├── TEMPLATE.txt                 # Case template
├── update-open-tickets.sh       # Regenerate OPEN-TICKETS.md + open HTML report
├── kubernetes/                  # 41 cases, 8 reference guides
├── proxmox/                     # 16 cases, 1 reference guide
├── terraform/                   # 10 cases, 1 reference guide
├── github/                      # 7 cases, 3 reference guides (security audits)
├── identity/                    # 9 cases (FreeIPA, Kerberos, SSSD)
├── vault/                       # 5 cases
├── network/                     # 5 cases
├── linux/                       # 4 cases
├── macos/                       # 1 case, 1 reference guide
└── aws/                         # 1 case
```

Each subfolder has its own README with a case index. Reference guides live in `reference/` subfolders.

---

## Critical Incidents (15)

Cascading failures, data loss risk, or full-service outages.

| Ticket | Category | What Happened |
|--------|----------|---------------|
| [TS-K8S-019](kubernetes/19-flux-kustomization-restructure-cascade-failure.md) | Kubernetes | Kustomization rename with prune:true deleted ALL HelmReleases including Vault — complete cluster deadlock |
| [TS-K8S-042](kubernetes/42-flux-retry-storm-cluster-outage.md) | Kubernetes | Grafana anti-affinity → Helm timeout → Flux retry loop → etcd leader election failure → API servers down |
| [TS-K8S-022](kubernetes/22-worker-node-failure-cascading-pod-failures.md) | Kubernetes | Worker2 failure cascaded into StatefulSet split-brain, Vault injector race, CSI mount failures |
| [TS-K8S-043](kubernetes/43-noexecute-taint-not-applied.md) | Kubernetes | Pods NOT evicted from unreachable nodes — PartialDisruption rate-limiting silently blocked NoExecute taints |
| [TS-K8S-044](kubernetes/44-coredns-ha-masters.md) | Kubernetes | Both CoreDNS pods on same failed nodes → complete DNS outage across cluster |
| [TS-K8S-015](kubernetes/15-csi-nfs-restart-stale-mount-mariadb-crash.md) | Kubernetes | CSI NFS DaemonSet restart made mounts stale → MariaDB CrashLoopBackOff |
| [TS-NET-003](network/3-svc-network-instability-investigation.md) | Network | 4-phase, 6-day investigation — USB-Ethernet driver binding wrong kernel module caused link flapping (445 events) |
| [TS-TF-002](terraform/2-aws-secrets-deletion-incident.md) | Terraform | Workflow nuked all AWS secrets, state file corrupted 14KB → 299 bytes |
| [TS-TF-010](terraform/10-cloud-init-ssh-host-key-regeneration.md) | Terraform | Cloud-init regenerated host keys on every apply — broke SSH known_hosts across all VMs |
| [TS-PVE-010](proxmox/10-vm-restore-hang-concurrent-nfs-operations.md) | Proxmox | 6 concurrent VM restores overwhelmed NFS — orphaned LVM volumes, hung processes |
| [TS-PVE-015](proxmox/15-proxmox-crash-during-backup-unknown-cause.md) | Proxmox | Host crashed silently during backup — hardware-level, no logs, unresolved |
| [TS-PVE-017](proxmox/17-proxmox-host-cpu-io-spike-vms-stuck.md) | Proxmox | CPU/IO spike during DR testing — all VMs hung at boot, qemu-ga unresponsive |
| [TS-VLT-003](vault/3-vault-kms-credentials-overwrite-empty-vars.md) | Vault | Manual playbook run rendered empty vars → AWS KMS credentials wiped → Vault can't unseal |
| [TS-VLT-005](vault/5-vault-node-recovery-stale-raft-data.md) | Vault | Stale raft data after Proxmox crash — node can't rejoin cluster |
| [TS-PVE-014](proxmox/14-worker-vm-crash-unknown-root-cause.md) | Proxmox | Worker VM crashed on autostart — 3-part investigation revealed remediation pod triggering reboot during boot |

---

## Kubernetes — 41 cases

[reference/](kubernetes/reference/) has 8 guides

| # | File | What Happened |
|---|------|---------------|
| 1 | [pod-eviction-race-condition](kubernetes/1-k8s-pod-eviction-race-condition-router-outage.md) | Millisecond race between node recovery and taint eviction |
| 2 | [calico-bgp-wrong-interface](kubernetes/2-calico-bgp-wrong-interface-multi-nic.md) | BGP peered on storage NIC instead of service NIC |
| 3 | [nfs-hard-mount](kubernetes/3-nfs-hard-mount-pod-unresponsiveness.md) | Hard NFS mount hung pods indefinitely |
| 4 | [nfs-pv-reclaimpolicy](kubernetes/4-nfs-pv-reclaimpolicy-delete-failed-no-provisioner.md) | Static PV entered Failed state — no provisioner to handle Delete |
| 5 | [nfs-csi-storageclass](kubernetes/5-nfs-csi-storageclass-invalid-parameter-flux-stuck.md) | Invalid StorageClass param blocked all PVC provisioning |
| 7 | [mariadb-innodb-nfs](kubernetes/7-mariadb-innodb-nfs-table-creation-failure.md) | InnoDB O_DIRECT incompatible with NFS |
| 10 | [wordpress-admin-password](kubernetes/10-wordpress-admin-password-hash-reset.md) | Admin login failed — password hash mismatch |
| 11 | [wordpress-plugin](kubernetes/11-wordpress-plugin-version-incompatibility-blank-page.md) | Plugin version mismatch → blank page |
| 12 | [flux-crd-dependency](kubernetes/12-flux-kustomization-crd-dependency-failure.md) | ServiceMonitor failed — CRD not yet installed |
| 13 | [master-resource-exhaustion](kubernetes/13-k8s-master-node-resource-exhaustion.md) | Master node unresponsive — 244MB available memory |
| 14 | [vault-k8s-auth](kubernetes/14-vault-k8s-auth-service-account-not-authorized.md) | Grafana stuck Init — wrong ServiceAccount in Vault config |
| 15 | [csi-nfs-stale-mount](kubernetes/15-csi-nfs-restart-stale-mount-mariadb-crash.md) | CSI NFS restart made mounts stale → MariaDB crash |
| 16 | [pod-priority-classes](kubernetes/16-pod-priority-classes-dr-readiness.md) | No priority classes — wrong eviction order during pressure |
| 17 | [vault-injection-namespace](kubernetes/17-vault-injection-system-namespace-denied.md) | Vault webhook blocked kube-system deployment |
| 18 | [csi-nfs-network-isolation](kubernetes/18-csi-nfs-controller-cannot-provision-pvc-network-isolation.md) | CSI controller on masters had no route to NFS |
| 19 | [flux-kustomization-cascade](kubernetes/19-flux-kustomization-restructure-cascade-failure.md) | Kustomization rename + prune:true deleted all HelmReleases |
| 20 | [grafana-loki-version](kubernetes/20-grafana-loki-version-incompatibility.md) | Grafana 12.x query syntax broke against Loki 2.x |
| 21 | [remediation-pod-stopped-vm](kubernetes/21-remediation-pod-stopped-vm-api-error.md) | Remediation crashed on already-stopped VM |
| 22 | [worker-node-cascade](kubernetes/22-worker-node-failure-cascading-pod-failures.md) | Worker2 failure → StatefulSet split-brain, Vault race, CSI failures |
| 23 | [kustomization-leftover](kubernetes/23-kustomization-resource-not-removed.md) | Test resource left in prod kustomization |
| 25 | [promtail-vault-logs](kubernetes/25-promtail-vault-namespace-logs.md) | Promtail not collecting Vault logs — inconclusive |
| 26 | [released-pvs](kubernetes/26-released-pvs-cleanup.md) | Orphaned PVs wasting storage |
| 27 | [wordpress-php-upload](kubernetes/27-wordpress-php-upload-limits.md) | 2MB upload limit — missing PHP config |
| 28 | [nginx-proxy-body-size](kubernetes/28-nginx-proxy-body-size-413-error.md) | 413 errors — external nginx missing body size config |
| 29 | [wordpress-readiness-probe](kubernetes/29-wordpress-readiness-probe-nfs-detection.md) | Readiness probe checked local FS not NFS → 33% request failures |
| 30 | [worker3-memory-exhaustion](kubernetes/30-worker3-memory-exhaustion-vm-crash.md) | Worker3 VM crashed twice — insufficient memory, no swap |
| 33 | [vault-agent-dns](kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md) | IPA DNS down → new pods can't start (Vault auth blocked) |
| 34 | [wordpress-external-dns](kubernetes/34-wordpress-external-dns-slowness.md) | IPA outage → 4-12s delays + Flux/Helm failures |
| 36 | [grafana-antiaffinity](kubernetes/36-grafana-antiaffinity-rollout-stuck.md) | Anti-affinity too strict → rolling update blocked |
| 37 | [grafana-sqlite-corruption](kubernetes/37-grafana-dashboards-missing-sqlite-corruption.md) | 3 Grafana replicas writing SQLite over NFS → corruption |
| 38 | [qemu-guest-agent](kubernetes/38-qemu-guest-agent-cpu-loop.md) | qemu-ga EAGAIN busy loop eating 98% CPU |
| 39 | [kube-system-targetdown](kubernetes/39-kube-system-targetdown-false-positives.md) | Prometheus false alerts — kubeadm localhost-only metrics |
| 40 | [hpa-memory-scaling](kubernetes/40-hpa-memory-scaling-behavior.md) | HPA triggered wrong — uses REQUEST not LIMIT for % |
| 41 | [prometheusrule-not-picked-up](kubernetes/41-prometheusrule-not-picked-up.md) | Custom alerts missing — wrong label selector |
| 42 | [flux-retry-storm](kubernetes/42-flux-retry-storm-cluster-outage.md) | Flux retry loop → etcd leader election failure → API down |
| 43 | [noexecute-taint](kubernetes/43-noexecute-taint-not-applied.md) | PartialDisruption silently blocked NoExecute taints |
| 44 | [coredns-ha](kubernetes/44-coredns-ha-masters.md) | Both CoreDNS pods on same failed nodes → DNS outage |
| 45 | [csi-nfs-port-conflict](kubernetes/45-csi-nfs-controller-port-conflict.md) | CSI controller CrashLoop — liveness probe port conflict |
| 46 | [kustomization-stale-ref](kubernetes/46-kustomization-stale-resource-reference.md) | Flux broke after file consolidation |
| 47 | [csi-nfs-podlabels](kubernetes/47-csi-nfs-podlabels-silent-accept.md) | Helm silently accepted unsupported chart values |
| 48 | [prometheus-pvc-nfs](kubernetes/48-prometheus-pvc-nfsv4-version-mismatch.md) | NFS version drift after StorageClass update |

---

## Proxmox — 16 cases

[reference/](proxmox/reference/) has 1 guide

| # | File | What Happened |
|---|------|---------------|
| 1 | [node-rename](proxmox/1-proxmox-node-rename.md) | Hostname change broke pmxcfs cluster filesystem |
| 2 | [ssl-certificate](proxmox/2-proxmox-ssl-certificate.md) | SSL SAN had wrong IP after network migration |
| 3 | [ssh-cloud-init](proxmox/3-vm-ssh-permission-denied-cloud-init.md) | Cloud-init disabled password auth — domain users locked out |
| 4 | [lxc-snapshot-nfs](proxmox/4-proxmox-lxc-snapshot-nfs-mount.md) | LXC snapshots failed — NFS doesn't support snapshots |
| 5 | [backup-missed](proxmox/5-proxmox-backup-missed-not-retried.md) | Backups skipped when node offline — missing repeat-missed flag |
| 6 | [lxc-mount-backup](proxmox/6-lxc-mount-point-backup-disabled.md) | Terraform defaulted backup=false — mount data silently unprotected |
| 7 | [crontab-overwrite](proxmox/7-crontab-overwrite-recovery.md) | Cron jobs wiped — `crontab -` replaced instead of appended |
| 8 | [lvm-thin-pool](proxmox/8-lvm-thin-pool-resize-overcommit.md) | Thin pool 97% assigned, no auto-extend |
| 9 | [nfs-shutdown-hang](proxmox/9-nfs-shutdown-hang-stor0-hotswap.md) | Hard NFS mount froze shutdown indefinitely |
| 10 | [vm-restore-hang](proxmox/10-vm-restore-hang-concurrent-nfs-operations.md) | 6 concurrent restores overwhelmed NFS — orphaned LVM volumes |
| 11 | [vmbr1-storage](proxmox/11-vmbr1-storage-network-for-k8s-workers.md) | Workers couldn't reach storage VLAN |
| 12 | [vm-autostart-nfs](proxmox/12-vm-autostart-timeout-nfs-disk-not-ready.md) | VM autostart failed — NFS not ready at boot |
| 13 | [ups-monitor](proxmox/13-ups-monitor-cronjob-misconfiguration.md) | UPS monitor running weekly instead of every 5min |
| 14 | [worker-vm-crash](proxmox/14-worker-vm-crash-unknown-root-cause.md) | Worker VM crashed on autostart — remediation pod triggered reboot during boot |
| 15 | [host-crash-backup](proxmox/15-proxmox-crash-during-backup-unknown-cause.md) | Host crashed silently during backup — unresolved |
| 17 | [host-cpu-io-spike](proxmox/17-proxmox-host-cpu-io-spike-vms-stuck.md) | CPU/IO spike during DR testing — all VMs hung |

---

## Terraform — 10 cases

[reference/](terraform/reference/) has 1 guide

| # | File | What Happened |
|---|------|---------------|
| 1 | [golden-image](terraform/1-proxmox-golden-image-terraform.md) | Provider failed to import QCOW2 images |
| 2 | [aws-secrets-deletion](terraform/2-aws-secrets-deletion-incident.md) | Workflow nuked AWS secrets, state corrupted 14KB → 299 bytes |
| 3 | [lxc-clone-ssh](terraform/3-terraform-proxmox-lxc-clone-ssh-keys.md) | LXC clones can't accept SSH keys via Proxmox API |
| 4 | [vm-disk-tracking](terraform/4-terraform-proxmox-cloned-vm-disk-tracking.md) | Cloned VM disk state empty in tfstate |
| 5 | [lxc-mount-bug](terraform/5-terraform-proxmox-lxc-mount-point-bug.md) | Mount point silently failed to create |
| 6 | [route-table-inline](terraform/6-route-table-inline-vs-resource.md) | Inline route blocks removed other module's routes |
| 7 | [sg-rename-stuck](terraform/7-terraform-security-group-rename-stuck.md) | SG rename stuck — can't delete while attached to ENI |
| 9 | [cloud-init-update](terraform/9-terraform-cloud-init-update-behavior.md) | Cloud-init update failed — ide2 can't hotplug |
| 10 | [cloud-init-host-keys](terraform/10-cloud-init-ssh-host-key-regeneration.md) | Cloud-init regenerated host keys — broke all SSH known_hosts |
| 11 | [orphaned-disks](terraform/11-terraform-orphaned-disks-after-removal.md) | Provider left 720GB+ orphaned on disk after state removal |

---

## GitHub — 7 cases

[reference/](github/reference/) has 3 security audit docs

| # | File | What Happened |
|---|------|---------------|
| 1 | [runner-stuck](github/1-github-runner-stuck-job.md) | Runner not persistent after reboot |
| 2 | [workflow-lock](github/2-workflow-lock-flag-pattern.md) | Push-triggered workflows destroy/recreate resources |
| 5 | [clock-skew](github/5-runner-clock-skew-auth-failure.md) | DNS broke → NTP broke → clock drifted 2h → OAuth rejected |
| 7 | [concurrent-workflow](github/7-concurrent-terraform-workflow-lxc-reboot.md) | Concurrent workflows rebooted containers mid-playbook |
| 8 | [branch-merge-conflicts](github/8-git-branch-merge-conflicts-flux-gitops.md) | Two-way merge between env branches → cascading conflicts |
| 9 | [wrong-user](github/9-commit-attributed-to-wrong-user.md) | Tablet had no git config — commits attributed to wrong user |
| 10 | [squash-merge](github/10-squash-merge-causes-recurring-conflicts.md) | Squash merge broke tracking on long-lived branches |

---

## Identity — 9 cases

| # | File | What Happened |
|---|------|---------------|
| 1 | [lxc-kerberos-keyring](identity/1-lxc-kerberos-keyring-auth-failure.md) | LXC UID namespace broke kernel keyring for Kerberos |
| 2 | [dns-forwarders](identity/2-freeipa-dns-configuration-issues.md) | Clients can't resolve external DNS — BIND recursion denied |
| 3 | [gssapi-hostname](identity/3-kerberos-gssapi-requires-hostnames.md) | GSSAPI requires FQDNs, not IPs |
| 4 | [password-policy](identity/4-freeipa-password-policy-cospriority.md) | Missing undocumented cospriority parameter |
| 5 | [server-sssd-sudo](identity/5-freeipa-server-sssd-sudo.md) | FreeIPA server doesn't apply its own SSSD rules |
| 6 | [lxc-uid-range](identity/6-freeipa-lxc-uid-range-investigation.md) | FreeIPA UID range outside LXC mapped range |
| 7 | [ntp-lxc-skip](identity/7-freeipa-client-ntp-lxc-skip.md) | chronyd can't run in unprivileged LXC |
| 8 | [keytab-preauth](identity/8-keytab-preauthentication-failed.md) | ipa-getkeytab without -r broke password auth |
| 9 | [sssd-knownhosts-timeout](identity/9-ansible-sssd-knownhosts-timeout.md) | 28-34s Ansible delays when IPA down |

---

## Vault — 5 cases

| # | File | What Happened |
|---|------|---------------|
| 1 | [cluster-setup](vault/1-vault-cluster-initial-setup-investigation.md) | 8 sequential deployment issues during initial setup |
| 2 | [vip-certificate](vault/2-freeipa-vip-certificate-san-managedby.md) | Certificate SAN rejected — missing managedby |
| 3 | [kms-credentials-overwrite](vault/3-vault-kms-credentials-overwrite-empty-vars.md) | Empty vars wiped AWS KMS credentials → Vault can't unseal |
| 4 | [agent-injector-tls](vault/4-vault-agent-injector-k8s-tls-ca-setup.md) | 7 TLS/template errors during agent injection setup |
| 5 | [node-recovery-stale-raft](vault/5-vault-node-recovery-stale-raft-data.md) | Stale raft data after crash — node can't rejoin cluster |

---

## Network — 5 cases

| # | File | What Happened |
|---|------|---------------|
| 1 | [static-route-ssh](network/1-static-route-ssh-disconnect.md) | SSH drops after 30s via ISP router |
| 2 | [asymmetric-routing](network/2-asymmetric-routing-ssh-wan-lan.md) | SSH hangs from WAN — return path asymmetry |
| 3 | [svc-network-instability](network/3-svc-network-instability-investigation.md) | 4-phase, 6-day investigation — USB-Ethernet wrong kernel driver |
| 4 | [wireguard-cgnat](network/4-wireguard-cgnat-port-blocking.md) | WireGuard tunnel down — ISP CGNAT blocking port |
| 5 | [wireguard-stability](network/5-wireguard-tunnel-stability-investigation.md) | ISP randomly blocks AWS Elastic IPs |

---

## Linux — 4 cases

| # | File | What Happened |
|---|------|---------------|
| 1 | [dnf-metadata](linux/1-rocky-linux-dnf-metadata-error.md) | Mirrorlist returning HTML instead of XML |
| 2 | [chronyd-lxc](linux/2-lxc-chronyd-adjtimex-failure.md) | chronyd permission denied in LXC |
| 3 | [dns-fallback](linux/3-linux-nodes-dns-fallback.md) | SSSD overwrites fallback DNS → Vault can't reach KMS on IPA outage |
| 4 | [cloud-init-hosts](linux/4-cloud-init-etc-hosts-ownership.md) | cloud-init wipes /etc/hosts on reboot |

---

## macOS — 1 case

[reference/](macos/reference/) has 1 guide

| # | File | What Happened |
|---|------|---------------|
| 1 | [local-network-permission](macos/1-macos-local-network-permission.md) | macOS privacy blocking local network access |

---

## AWS — 1 case

| # | File | What Happened |
|---|------|---------------|
| 1 | [cfn-iam-policy](aws/1-cloudformation-iam-policy-replacement-failure.md) | CFN can't replace named IAM policy — create-before-delete fails |

---

## Case Format

All cases use this structure:

```
# TS-XXX-NNN | YYYY-MM-DD | STATUS
_____________________________________________________________________

[Info]
Domain: ...
Sub-techs: ...
Environment: ...
Re-opened: ...
_____________________________________________________________________

[Issue Description]
_____________________________________________________________________

[Analysis]
_____________________________________________________________________

[Final Root Cause]
_____________________________________________________________________

[Final Solution]
_____________________________________________________________________

[Risk Level]
_____________________________________________________________________

[References]
```

**Status values:** RESOLVED, WORKAROUND APPLIED, UNRESOLVED, SUSPENDED, PENDING, IN PROGRESS

**Naming:** `N-short-description.md` — numbered chronologically within each subfolder.
