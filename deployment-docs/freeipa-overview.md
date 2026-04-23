# FreeIPA — overview

FreeIPA is the identity foundation this whole platform is built on. It's the
first service deployed in each environment — everything else (Vault, Kubernetes,
Ansible automation, app-level DNS) depends on it for DNS, TLS certs, Kerberos,
LDAP, or sudo rules. Its pieces scatter across Ansible (install + domain config),
Terraform (VM + AWS Secrets Manager entries), Kubernetes (CoreDNS overrides, per-app
CA secrets), GitHub Actions (keytab-driven automation), Troubleshooting, Disaster
Recovery, and the Network layer. This file is the map that ties them together.

For operational setup, use the sequenced guide:
- `freeipa-initial-setup-guide.txt` (step 7) — the 7-phase install walkthrough

This overview sits above that guide — what FreeIPA is, the key design calls,
and where every related file lives in the repo.

---

## Reference

| Item | Dev | Prod |
|------|-----|------|
| FreeIPA server IP | 10.0.60.10 (VLAN 60) | 10.0.50.10 (VLAN 50) |
| Hostname | freeipa.lab.local | freeipa.lab.local |
| Domain | lab.local | lab.local |
| Kerberos realm | LAB.LOCAL | LAB.LOCAL |
| UID / GID range | 60001 – 65500 | 60001 – 65500 |
| DNS upstream forwarders | 8.8.8.8, 1.1.1.1 | 8.8.8.8, 1.1.1.1 |
| Node-side DNS fallback | 8.8.8.8 | 8.8.8.8 |
| Admin principal | admin@LAB.LOCAL | admin@LAB.LOCAL |
| Automation service account | super_bot | super_bot |

Same realm/domain in both envs on purpose — they're independent installations
sharing the lab convention, and because the two environments never share a
network boundary, name collision doesn't matter.

---

## Design calls

### FreeIPA over Active Directory / OpenLDAP+MIT Kerberos

Three options were on the table: Active Directory (rejected — Windows-heavy,
licensing cost, Linux clients always second-class), OpenLDAP + MIT Kerberos +
BIND + Dogtag assembled separately (rejected — reinventing what FreeIPA
already integrates, four debug surfaces instead of one), or FreeIPA (picked —
one CLI, one operational surface, Linux-native, free). The tradeoff is first-
time learning curve, which I paid in week one. Everything else — adding a user,
issuing a cert, updating DNS — is a single `ipa` command.

### Single-instance SPOF accepted (with mitigations)

FreeIPA runs as a single VM per environment. No multi-master replication. This
is a documented SPOF in `disaster-recovery/README.md`. Accepted because (1)
multi-master doubles the machine count for identity on a resource-constrained
2-laptop fleet, (2) the DR test showed the platform degrades gracefully when
IPA is down (existing pods + existing SSH sessions keep working; only NEW
operations block), (3) Proxmox vzdump restore brings it back in ~15 minutes,
(4) this is a portfolio project, not a production platform with an SLO. The
fallbacks (`dns_fallback.yml`, CoreDNS hosts plugin) exist precisely because
the SPOF is real.

### ipa-client baked into golden templates

Integration with FreeIPA starts at the **golden image**, not at the per-machine
enrollment step. Both the VM and LXC golden templates (`golden_templates/`)
have `ipa-client` pre-installed and the IPA CA pre-seeded into the system
trust store. When Terraform clones a new VM or provisions a new LXC, the
ipa-client is already there from first boot. What the per-machine
`add_hosts_to_ipa.yml` does is **enrollment only** — `ipa-client-install`
with the FreeIPA server + admin credentials. No package install at enrollment
time means no network dependency for apt/dnf during provisioning, and ~20-30
minutes saved across a full cluster rebuild.

### Dual-inventory bootstrap pattern

Ansible has two inventories per env. `inventory.ini` is the production one —
FQDN hostnames, `ansible_user: super_bot`, Kerberos GSSAPI auth, requires a
valid `kinit` before use. `first_setup_inventory.ini` is the bootstrap one —
raw IPs, `ansible_user: root`, SSH key auth, works without FreeIPA being up.
Reason: during initial provisioning, super_bot doesn't exist yet (it's a
FreeIPA user) and FQDN resolution requires FreeIPA DNS. The bootstrap
inventory handles that cold-start state. It's also the emergency fallback
when FreeIPA is down during an incident.

### LXC-forced changes to FreeIPA defaults

Three defaults don't work on unprivileged LXC containers and required
overrides. (1) **UID range 60001 – 65500** via `ipaserver_idstart` — default
assigns UIDs outside the LXC subuid map, causing "UID out of range" errors
(`TS-IDN-006`). (2) **Kerberos credential cache `FILE:/tmp/krb5cc_%U`**
instead of the default keyring — unprivileged LXC UID mapping breaks keyring
auth (`TS-IDN-001`; applied by `fix_lxc_krb5_keyring.yml`). (3) **NTP skipped
on clients** via `ipaclient_no_ntp: true` — LXC containers share kernel time
with the Proxmox host and can't run their own time daemon (`TS-IDN-007`).

### DNS architecture with fallback

IPA is authoritative for `lab.local` and forwards external queries to
8.8.8.8 / 1.1.1.1. Three distinct DNS paths coexist: (1) **IPA client nodes**
have `zzz-ipa.conf` with IPA primary + 8.8.8.8 fallback, so external queries
survive IPA being down (internal `.lab.local` names do NOT — fallback
doesn't know the zone). (2) **K8s pods** use CoreDNS, which has a `hosts`
plugin ConfigMap hardcoding `vault.lab.local` and `k8s.lab.local` to their
VIPs — this is specifically to let new pods resolve the two names they MUST
have during an IPA outage (pod-level Vault injection). (3) **MikroTik DHCP**
hands out IPA as primary DNS to every VLAN except Management (VLAN 5).
Mitigation pattern came from the IPA-down DR test — `TS-K8S-033`, `TS-K8S-034`,
`TS-LNX-003`.

---

## Layer map — where every FreeIPA-touching file lives

### Ansible

| Path | Purpose |
|------|---------|
| `ansible/<env>/playbooks/freeipa/freeipa_setup.yml` | Install FreeIPA server, DNS, Kerberos, CA; domain + realm + UID range |
| `ansible/<env>/playbooks/freeipa/domain_config.yml` | Host groups, bot user (`super_bot`), admin users, HBAC, sudo rules, password policies |
| `ansible/<env>/playbooks/freeipa/add_hosts_to_ipa.yml` | Per-host enrollment via `ipa-client-install` |
| `ansible/<env>/playbooks/freeipa/add_dns_records.yml` | VIP A-records (`vault.lab.local`, `k8s.lab.local`) + per-app records |
| `ansible/<env>/playbooks/freeipa/dns_fallback.yml` | Node-side 8.8.8.8 fallback in `zzz-ipa.conf` — IPA-down mitigation |
| `ansible/<env>/playbooks/freeipa/fix_lxc_krb5_keyring.yml` | LXC Kerberos cache → FILE mode |
| `ansible/<env>/playbooks/common/ntp.yml` | NTP sync (required for Kerberos clock skew); LXC skips |
| `ansible/<env>/inventory/group_vars/freeipa.yml` | Host groups, admin user list, bot user list, encrypted passwords |
| `ansible/<env>/inventory/group_vars/all.yml` | `ipaadmin_password` (vault), `ipaclient_*` settings, DNS servers, `ipa_managed_hosts` |
| `ansible/<env>/inventory/inventory.ini` | Production inventory — FQDN + super_bot + Kerberos + `KnownHostsCommand=none` |
| `ansible/<env>/inventory/first_setup_inventory.ini` | Bootstrap inventory — IP + root + SSH key (DR fallback too) |

### Terraform

| Path | Purpose |
|------|---------|
| `terraform/<env>/proxmox/vms/freeipa/` | FreeIPA VM on Proxmox |
| `terraform/<env>/aws/secrets/` | AWS Secrets Manager entries: `<env>/freeipa/admin-password`, `<env>/freeipa/dm-password`, `<env>/super_bot/keytab` |

### Kubernetes

| Path | Purpose |
|------|---------|
| `kubernetes/<env>/deployments/infrastructure/coredns/coredns-custom.yaml` | CoreDNS `hosts` plugin for `vault.lab.local` + `k8s.lab.local` (pod-side IPA-down mitigation) |
| `kubernetes/<env>/deployments/apps/*/vault-ca-secret.yaml` | Per-app IPA CA cert for Vault sidecar TLS trust |

### GitHub Actions

| Path | Purpose |
|------|---------|
| `.github/workflows/<env>-freeipa-full-setup.yml` | Terraform VM + Ansible install (fetches admin/DM passwords from AWS SM) |
| `.github/workflows/<env>-vault-full-setup.yml` | Uses `super_bot` keytab from AWS SM for Kerberos-authenticated Ansible runs |

### Network

| Path | Purpose |
|------|---------|
| `network/ip-planning.txt` | Defines IPA IPs, VIPs, DNS forwarders — complete zone layout |
| `network/router/mikrotik/phase2-dev-services.rsc` | MikroTik DHCP — each VLAN's DNS set to IPA server |

### Golden templates

| Path | Purpose |
|------|---------|
| `golden_templates/golden-vm-setup.sh` | VM golden template — installs `ipa-client`, pre-seeds IPA CA trust |
| `golden_templates/golden-lxc-setup.sh` | LXC golden template — same pre-install pattern |

### Troubleshooting (IPA-specific)

| TS ID | File | Short |
|-------|------|-------|
| IDN-001 | `troubleshooting/identity/1-lxc-kerberos-keyring-auth-failure.md` | LXC kernel keyring UID mismatch; fix = FILE ccache |
| IDN-002 | `troubleshooting/identity/2-freeipa-dns-configuration-issues.md` | Forwarders not applied + BIND recursion restricted to 127.0.0.1 |
| IDN-003 | `troubleshooting/identity/3-kerberos-gssapi-requires-hostnames.md` | SSH with IP fails Kerberos; principals are FQDN-bound |
| IDN-004 | `troubleshooting/identity/4-freeipa-password-policy-cospriority.md` | Per-group password policy silently fails without `cospriority` |
| IDN-005 | `troubleshooting/identity/5-freeipa-server-sssd-sudo.md` | FreeIPA server is provider, not a client — sudo rules don't apply to itself |
| IDN-006 | `troubleshooting/identity/6-freeipa-lxc-uid-range-investigation.md` | UID range must fit LXC subuid map (60001 – 65500) |
| IDN-007 | `troubleshooting/identity/7-freeipa-client-ntp-lxc-skip.md` | Skip NTP config on LXC enrollment |
| IDN-008 | `troubleshooting/identity/8-keytab-preauthentication-failed.md` | Regenerate keytab with `-r` or break password auth |
| IDN-009 | `troubleshooting/identity/9-ansible-sssd-knownhosts-timeout.md` | 28s Ansible delay — `KnownHostsCommand=none` fixes it |

### Cross-ref TS (IPA-adjacent failure paths)

| TS ID | File | Why it matters |
|-------|------|----------------|
| VLT-002 | `troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md` | FreeIPA-side cert trap for Vault's VIP SAN |
| K8S-033 | `troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md` | IPA DNS down → pods stuck in Init |
| K8S-034 | `troubleshooting/kubernetes/34-wordpress-external-dns-slowness.md` | IPA-down external DNS slowness |
| K8S-035 | `troubleshooting/kubernetes/35-pod-restart-investigation-ipa-down.md` | Pod restart investigation during IPA outage |
| LNX-003 | `troubleshooting/linux/3-linux-nodes-dns-fallback.md` | Node `zzz-ipa.conf` fallback — drove `dns_fallback.yml` |

### Disaster Recovery

| File | Covers |
|------|--------|
| `disaster-recovery/network-ipa-dns-outage.md` | **The foundational DR test** — drove every mitigation above |
| `disaster-recovery/README.md` | Known SPOFs list (FreeIPA explicit) |

### Deployment docs

| File | Purpose |
|------|---------|
| `deployment-docs/freeipa-initial-setup-guide.txt` | Full 7-phase walkthrough (step 7 in sequence) |
| `deployment-docs/aws-secrets-setup-guide.txt` | Prereq — AWS SM entries for IPA admin passwords + super_bot keytab |

---

## Dependency footprint

### FreeIPA depends on

- **AWS Secrets Manager** — admin password, DM password, super_bot keytab (fetched at runtime by GH workflows, never persisted to disk)
- **Proxmox** — VM host (backed up via vzdump to NAS)
- **Upstream DNS** — 8.8.8.8 / 1.1.1.1 for external forwarders
- **Ansible + local runner** — the host that runs `freeipa_setup.yml`

### Consumers (essentially everything)

- **Vault** — DNS (`vault.lab.local`, `vault1/2/3.lab.local`), TLS cert issuance via IPA CA, Kerberos host principals, LDAP bind user for UI auth
- **Kubernetes nodes** — IPA enrollment for human admin SSH, DNS resolution of `.lab.local` names
- **K8s pods** (via CoreDNS) — `vault.lab.local` and `k8s.lab.local` specifically (via hosts plugin override during IPA outage), other `.lab.local` names via forwarding
- **Ansible automation** — every managed host, via super_bot Kerberos auth with keytab
- **GitHub Actions** — fetches super_bot keytab from AWS SM, `kinit` before running playbooks
- **Every enrolled host** — nginx LXC, runner LXC, ansible LXC, k8s nodes, vault cluster — all have host keytabs at `/etc/krb5.keytab`

### What breaks when FreeIPA is down (from DR test)

**Still works:**
- K8s control plane (kubelet uses IPs)
- Existing pods with cached Vault tokens (until TTL, ~1h)
- Existing SSH sessions
- Internal Vault cluster operations (nodes know each other's IPs)
- External website access from pods (node-side 8.8.8.8 fallback)
- Vault auto-unseal during restart (AWS KMS is independent)

**Breaks:**
- New pod startup with `vault.hashicorp.com/agent-inject` annotation — unless the target is `vault.lab.local` (CoreDNS hosts plugin saves it)
- SSH with FQDN hostnames (fall back to bootstrap inventory with IPs + root)
- Ansible default inventory (28s SSSD KnownHostsCommand delay — fixed with `KnownHostsCommand=none`)
- FluxCD reconcile loops touching IPA-resolved endpoints
- Vault LDAP-based UI login (break-glass userpass still works)
- External DNS from pods (unless node fallback is active)

**Operational rule during IPA outage:** do NOT restart/scale K8s deployments,
do NOT reboot anything, use IPs for SSH. Recover IPA first; everything else
follows.

---

## Why this overview exists

FreeIPA's dependency cascade is wide and subtle. The worst failure modes
aren't the loud ones — they're the "SSH works but sudo fails," the "Ansible
runs 28 seconds slower for no obvious reason," the "new pod stuck in Init
forever with cryptic logs." That collection of half-broken behaviors is the
thing that's hardest to reconstruct later from TS cases alone. This overview
is the single place that ties together what IPA is, what touches it, and
what happens when it isn't there.

The setup guide (`freeipa-initial-setup-guide.txt`) covers HOW to deploy.
The TS cases cover WHAT went wrong when. This file covers WHAT IT IS and
WHERE IT LIVES — the missing layer.
