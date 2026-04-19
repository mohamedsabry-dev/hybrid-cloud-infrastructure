# FreeIPA Playbooks — DEV

Ansible playbooks that install FreeIPA, enroll managed hosts in the domain,
create users/groups/HBAC/sudo rules, and apply the LXC-specific Kerberos
fixes. The Ansible side of the broader FreeIPA story — for the full identity
layer (DNS architecture, keytab lifecycle, dependency map, LXC UID range
rationale, dual inventory) see
[`../../../../deployment-docs/freeipa-overview.md`](../../../../deployment-docs/freeipa-overview.md).

For run order + commands see [`freeipa-setup-guide.txt`](freeipa-setup-guide.txt).

---

## Playbooks

| Playbook | Purpose | Target |
|----------|---------|--------|
| `freeipa_setup.yml` | Install + configure FreeIPA server | `freeipa` |
| `add_hosts_to_ipa.yml` | Join managed hosts to the domain via `ipaclient` role | all (except freeipa) |
| `domain_config.yml` | Create host groups, bot + admin users, HBAC, sudo rules, password policies | `freeipa` |
| `add_dns_records.yml` | Add A records for VIPs (`vault.lab.local`, `k8s.lab.local`) + per-app names | `freeipa` |
| `fix_lxc_krb5_keyring.yml` | Switch LXC Kerberos cache from keyring to FILE (fixes TS-IDN-001) | `lxc` |
| `dns_fallback.yml` | Add 8.8.8.8 fallback in `/etc/NetworkManager/conf.d/zzz-ipa.conf` on every node | all managed hosts |

## Key settings (applied by `freeipa_setup.yml`)

- **Domain / Realm:** `lab.local` / `LAB.LOCAL`
- **UID range:** `60001–65500` (fits LXC unprivileged UID mapping — TS-IDN-006)
- **DNS forwarders:** `8.8.8.8`, `1.1.1.1`
- **Credential source:** env vars injected by GitHub workflow from AWS Secrets Manager

## Domain structure (applied by `domain_config.yml`)

- **Host groups:** `automation_group`, `k8s_masters`, `k8s_workers`, `vault_cluster`, `ansible_nodes`, `runner_nodes`, `nginx_nodes`
- **Bot users:** `super_bot` (passwordless sudo via HBAC for automation)
- **Admin users:** `k8s_admin`, `vault_admin`, `nginx_admin`, `ansible_admin`, `runner_admin`
- **Password policies:** relaxed for `automation_users`, strict for `admin_users` (cospriority gate — TS-IDN-004)

## LXC-specific (applied by `fix_lxc_krb5_keyring.yml`)

Unprivileged LXC containers use UID-remapping that breaks the default kernel
keyring Kerberos cache. The playbook sets `krb5_ccache_template = FILE:/tmp/krb5cc_%U`
in sssd.conf so credentials go to a file path instead. See TS-IDN-001.

## Troubleshooting

See `/troubleshooting/identity/` (repo root) for the per-case writeups:

| Case | Issue |
|------|-------|
| 1 | LXC Kerberos keyring UID mismatch → FILE ccache |
| 2 | FreeIPA DNS forwarders + BIND recursion |
| 3 | Kerberos GSSAPI requires FQDN (not IP) |
| 4 | Per-group password policy needs `cospriority` |
| 5 | FreeIPA server is provider, not a client (sudo rules don't apply to itself) |
| 6 | UID range must fit LXC subuid map |
| 7 | Skip NTP on LXC client enrollment |
| 8 | Keytab invalidated by password change (regenerate with `-r`) |
| 9 | Ansible 28s delay from SSSD KnownHostsCommand |

## Related

- [`freeipa-setup-guide.txt`](freeipa-setup-guide.txt) — run order + commands
- [`../../../../deployment-docs/freeipa-overview.md`](../../../../deployment-docs/freeipa-overview.md) — identity-layer system overview
- [`../../../../deployment-docs/freeipa-initial-setup-guide.txt`](../../../../deployment-docs/freeipa-initial-setup-guide.txt) — sequenced step-7 walkthrough
- [`../../inventory/group_vars/freeipa.yml`](../../inventory/group_vars/freeipa.yml) — host groups + user definitions + encrypted passwords
