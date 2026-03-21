# FreeIPA Playbooks

Identity management playbooks for FreeIPA server and client configuration.

## Playbooks

| Playbook | Purpose | Target |
|----------|---------|--------|
| `freeipa_setup.yml` | Install and configure FreeIPA server | freeipa |
| `add_hosts_to_ipa.yml` | Join hosts to FreeIPA domain | all (except freeipa) |
| `domain_config.yml` | Configure users, groups, HBAC, sudo rules | freeipa |
| `fix_lxc_krb5_keyring.yml` | Fix Kerberos ccache on LXC containers | lxc |

## Deployment Order

Run playbooks in this order for initial setup:

```
1. freeipa_setup.yml      - Install FreeIPA server
2. add_hosts_to_ipa.yml   - Join all hosts to domain
3. domain_config.yml      - Create users, groups, rules
4. fix_lxc_krb5_keyring.yml - Fix LXC Kerberos issues
```

## Playbook Details

### freeipa_setup.yml

Installs FreeIPA server with:
- Domain: `lab.local`
- Realm: `LAB.LOCAL`
- UID range: 60001-65500 (fits LXC unprivileged mapping)
- DNS with forwarders (8.8.8.8, 1.1.1.1)

**Credentials:** Injected via environment variables from AWS Secrets Manager.

### add_hosts_to_ipa.yml

Joins all managed hosts to the FreeIPA domain using the `ipaclient` role.

**Pre-requisites:**
- FreeIPA server must be running
- Target hosts must resolve FreeIPA DNS

### domain_config.yml

Creates domain structure:
- **Host Groups:** automation_group, k8s_masters, k8s_workers, vault_cluster, etc.
- **Bot Users:** super_bot (passwordless sudo)
- **Admin Users:** k8s_admin, vault_admin, nginx_admin, etc.
- **HBAC Rules:** SSH access rules per user/hostgroup
- **Sudo Rules:** Privilege escalation rules
- **Password Policies:** 4 years for automation, 1 year for admins

### fix_lxc_krb5_keyring.yml

Fixes Kerberos credential cache issue on LXC containers.

**Problem:** Unprivileged LXC uses kernel keyring by default, which fails due to UID mapping.

**Solution:** Switch to FILE-based ccache (`/tmp/krb5cc_%U`).

**Reference:** See `/troubleshooting/identity/17-lxc-kerberos-keyring-auth-failure.md`

## Usage

```bash
# Install FreeIPA server (run from mac-mini via workflow)
ansible-playbook -i inventory/first_setup_inventory.ini playbooks/freeipa/freeipa_setup.yml

# Join hosts to domain
ansible-playbook -i inventory/first_setup_inventory.ini playbooks/freeipa/add_hosts_to_ipa.yml

# Configure domain (requires kinit admin)
ansible-playbook playbooks/freeipa/domain_config.yml

# Fix LXC Kerberos (after domain join)
ansible-playbook playbooks/freeipa/fix_lxc_krb5_keyring.yml
```

## Troubleshooting

See `/troubleshooting/` (repo root) for detailed issue resolutions:

| Category | Issues |
|----------|--------|
| identity/ | FreeIPA DNS, Kerberos, LXC keyring, SSSD |
| linux/ | UID mapping, NTP, Rocky Linux repos |
