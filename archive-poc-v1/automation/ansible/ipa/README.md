# FreeIPA Playbooks

Identity management automation for FreeIPA.

## Playbooks

| File | Purpose |
|------|---------|
| `ipa-01-create-users-groups.yml` | Create users and groups |
| `ipa-02-create-hostgroups.yml` | Create host groups |
| `ipa-03-configure-hbac-rules.yml` | Configure HBAC access rules |
| `ipa-04-configure-sudo-rules.yml` | Configure sudo rules |
| `ipa-05-update-dns-resolution.yml` | Update DNS settings |
| `check_ipa_dns.yml` | Verify DNS resolution |
| `fix_ntp_to_ipa.yml` | Fix NTP sync to IPA |

## Guides

- `manual-commands-guide.txt` - Manual IPA commands reference
- `sssd-config-guide.txt` - SSSD configuration guide

## Legacy

The `legacy/` folder contains older playbooks:
- Security hardening scripts
- Audit and cleanup playbooks
- NTP configuration variants

## Usage

```bash
# Create users and groups
ansible-playbook -i ../inventory ipa-01-create-users-groups.yml

# Configure HBAC rules
ansible-playbook -i ../inventory ipa-03-configure-hbac-rules.yml
```
