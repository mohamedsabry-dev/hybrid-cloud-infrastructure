# Troubleshooting Cases Index

Documentation of issues encountered and resolved during infrastructure setup.

---

## Categories

| Category | Description | Count |
|----------|-------------|-------|
| [aws/](aws/) | AWS CloudFormation, IAM issues | 1 |
| [github/](github/) | GitHub Actions, runners, workflows | 2 |
| [identity/](identity/) | FreeIPA, Kerberos, authentication | 7 |
| [linux/](linux/) | OS-level issues (Rocky Linux, NTP, UID) | 4 |
| [macos/](macos/) | macOS client configuration | 2 |
| [network/](network/) | Routing, connectivity issues | 2 |
| [proxmox/](proxmox/) | Proxmox VE platform issues | 4 |
| [security/](security/) | Secrets management, incidents | 1 |
| [terraform/](terraform/) | Terraform IaC issues | 4 |
| [vault/](vault/) | HashiCorp Vault deployment issues | 8 |

---

## AWS

| # | Title | Summary |
|---|-------|---------|
| [01](aws/01-cloudformation-iam-policy-replacement-failure.md) | CloudFormation IAM Policy Replacement | IAM policy replacement failure during stack updates |

---

## GitHub

| # | Title | Summary |
|---|-------|---------|
| [08](github/08-github-runner-stuck-job.md) | GitHub Runner Stuck Job | Self-hosted runner job stuck in queue |
| [10](github/10-workflow-lock-flag-pattern.md) | Workflow Lock Flag Pattern | Preventing concurrent workflow runs |

---

## Identity

| # | Title | Summary |
|---|-------|---------|
| [17](identity/17-lxc-kerberos-keyring-auth-failure.md) | LXC Kerberos Keyring Auth Failure | Password auth fails on LXC due to kernel keyring UID mapping |
| [19](identity/19-freeipa-dns-configuration-issues.md) | FreeIPA DNS Configuration Issues | DNS recursion denied + forwarders syntax error |
| [22](identity/22-kerberos-gssapi-requires-hostnames.md) | Kerberos GSSAPI Requires Hostnames | GSSAPI auth fails when using IP addresses |
| [23](identity/23-freeipa-configuration-requirements.md) | FreeIPA Configuration Requirements | cospriority, server SSSD, UID_MAX gotchas |
| [33](identity/33-freeipa-dns-recursion-denied.md) | FreeIPA DNS Recursion Denied | BIND defaults to localhost-only recursion |
| [34](identity/34-freeipa-dns-forwarders-syntax.md) | FreeIPA DNS Forwarders Syntax | ipadnsconfig requires ip_address dict format |
| [35](identity/35-freeipa-server-sssd-sudo.md) | FreeIPA Server SSSD Sudo | IPA server doesn't use SSSD for sudo lookups |

---

## Linux

| # | Title | Summary |
|---|-------|---------|
| [15](linux/15-rocky-linux-dnf-metadata-error.md) | Rocky Linux DNF Metadata Error | DNF repository metadata download failures |
| [18](linux/18-lxc-ntp-configuration-disabled.md) | LXC NTP Configuration Disabled | LXC containers inherit time from host, can't run chronyd |
| [21](linux/21-lxc-uid-mapping-initgroups-error.md) | LXC UID Mapping initgroups Error | FreeIPA default UIDs outside LXC mapped range |
| [24](linux/24-lxc-chronyd-adjtimex-failure.md) | LXC Chronyd adjtimex Failure | Unprivileged LXC cannot adjust clock, configure host instead |

---

## macOS

| # | Title | Summary |
|---|-------|---------|
| [02](macos/02-macos-local-network-permission.md) | macOS Local Network Permission | Local network access permission prompts |
| [09](macos/09-macos-persistent-route.md) | macOS Persistent Route | Adding persistent routes on macOS |

---

## Network

| # | Title | Summary |
|---|-------|---------|
| [04](network/04-static-route-ssh-disconnect.md) | Static Route SSH Disconnect | SSH disconnects when adding static routes |
| [05](network/05-asymmetric-routing-ssh-wan-lan.md) | Asymmetric Routing SSH WAN/LAN | SSH fails due to asymmetric routing paths |

---

## Proxmox

| # | Title | Summary |
|---|-------|---------|
| [03](proxmox/03-proxmox-node-rename.md) | Proxmox Node Rename | Steps to rename a Proxmox node |
| [11](proxmox/11-proxmox-ssl-certificate.md) | Proxmox SSL Certificate | Custom SSL certificate configuration |
| [16](proxmox/16-proxmox-lxc-snapshot-nfs-mount.md) | LXC Snapshot NFS Mount | Snapshots fail when mount points use NFS storage |
| [20](proxmox/20-vm-ssh-permission-denied-cloud-init.md) | VM SSH Permission Denied Cloud-Init | Cloud-init disables password auth on VMs |

---

## Security

| # | Title | Summary |
|---|-------|---------|
| [07](security/07-secrets-deletion-incident.md) | Secrets Deletion Incident | AWS Secrets Manager accidental deletion recovery |

---

## Terraform

| # | Title | Summary |
|---|-------|---------|
| [06](terraform/06-proxmox-golden-image-terraform.md) | Proxmox Golden Image Terraform | Creating golden images with Terraform |
| [12](terraform/12-terraform-proxmox-cloned-vm-disk-tracking.md) | Terraform Proxmox Cloned VM Disk Tracking | Disk tracking issues with cloned VMs |
| [13](terraform/13-terraform-proxmox-lxc-mount-point-bug.md) | Terraform Proxmox LXC Mount Point Bug | Mount point configuration bugs |
| [14](terraform/14-terraform-proxmox-lxc-clone-ssh-keys.md) | Terraform Proxmox LXC Clone SSH Keys | SSH key injection in cloned containers |

---

## Vault

| # | Title | Summary |
|---|-------|---------|
| [25](vault/25-vault-gpg-signature-validation-failure.md) | Vault GPG Signature Validation Failure | DNF GPG key not imported into RPM keystore |
| [26](vault/26-certmonger-force-flag-not-recognized.md) | Certmonger --force Flag Not Recognized | Flag doesn't exist in Rocky Linux 10 certmonger |
| [27](vault/27-freeipa-ca-rejected-csr-hostname-mismatch.md) | FreeIPA CA Rejected CSR Hostname Mismatch | Certmonger uses short hostname, FreeIPA needs FQDN |
| [28](vault/28-ansible-cert-ownership-task-file-absent.md) | Ansible Cert Ownership Task File Absent | When condition missing rc != 0 check |
| [29](vault/29-vault-tls-ip-san-error.md) | Vault TLS IP SAN Error | VAULT_ADDR not set, defaults to 127.0.0.1 |
| [30](vault/30-ansible-shell-expansion-wrong-node.md) | Ansible Shell Expansion Wrong Node | $(hostname) expands on control node |
| [31](vault/31-ansible-cert-check-missing-file-fatal.md) | Ansible Cert Check Missing File Fatal | Missing failed_when: false on probe task |
| [32](vault/32-rpm-postinstall-task-ordering.md) | RPM Post-Install Task Ordering | RPM scripts run before Ansible continues |

---

## Quick Reference

### Common Patterns

| Symptom | Likely Cause | Case |
|---------|--------------|------|
| Password keeps prompting on LXC | Keyring UID mapping | [17](identity/17-lxc-kerberos-keyring-auth-failure.md) |
| `initgroups: Invalid argument` | FreeIPA UID out of range | [21](linux/21-lxc-uid-mapping-initgroups-error.md) |
| `Permission denied (publickey,gssapi...)` on VM | Cloud-init disabled password | [20](proxmox/20-vm-ssh-permission-denied-cloud-init.md) |
| SSH with IP fails, hostname works | Kerberos needs FQDN | [22](identity/22-kerberos-gssapi-requires-hostnames.md) |
| DNS recursion REFUSED | BIND recursion not allowed | [19](identity/19-freeipa-dns-configuration-issues.md) |
| Chronyd fails on LXC | LXC can't manage time | [18](linux/18-lxc-ntp-configuration-disabled.md) |
| `adjtimex failed: Operation not permitted` | Unprivileged LXC, configure host | [24](linux/24-lxc-chronyd-adjtimex-failure.md) |
| LXC snapshot not supported | Mount point on NFS | [16](proxmox/16-proxmox-lxc-snapshot-nfs-mount.md) |
| `cospriority is required` | Missing password policy priority | [23](identity/23-freeipa-configuration-requirements.md) |

### Key Fixes

```bash
# Case 17: Fix LXC Kerberos keyring
# Add to sssd.conf: krb5_ccache_template = FILE:/tmp/krb5cc_%U

# Case 20: Enable password auth on VMs
ansible k8s -m replace -a "path=/etc/ssh/sshd_config.d/50-cloud-init.conf regexp='PasswordAuthentication no' replace='PasswordAuthentication yes'" --become

# Case 22: Use GSSAPI with kinit
kinit super_bot && ssh super_bot@hostname.lab.local

# Case 16: Move LXC mount to local-lvm for snapshot support
pct stop <ctid> && pct move-volume <ctid> mp0 local-lvm && pct start <ctid>
```

---

## Contributing

When adding new troubleshooting cases:

1. Use format: `XX-short-description.md` (lowercase, hyphens)
2. Place in appropriate category folder
3. Include: Symptom, Root Cause, Solution, Prevention
4. Update this README index
