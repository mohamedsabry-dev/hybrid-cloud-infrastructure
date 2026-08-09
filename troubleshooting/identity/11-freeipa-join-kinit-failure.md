# TS Case 02 — FreeIPA Client Join Fails: "kinit: Cannot read password while getting initial credentials"

## Environment
- Ansible control node: `ansible.lab.local`
- Collection/role: `freeipa.ansible_freeipa.ipaclient`
- Playbook: `playbooks/freeipa/add_hosts_to_ipa.yml`
- Target hosts: Jenkins masters/agents, K8s masters/workers, Vault nodes (all `!freeipa` group)
- Auth: `ipaadmin_password` supplied via Ansible Vault, decrypted automatically at runtime via `vault_password_file` in `ansible.cfg`

## Symptom
The `Install - Join IPA` task fails during client enrollment:
```
fatal: [10.0.63.100]: FAILED! => {"changed": false, "msg": "Kerberos authentication failed: kinit: Cannot read password while getting initial credentials\n"}
```
Play recap shows the task as `failed=1`, with prior tasks (fact gathering, hostname/hosts file setup) completing successfully.

## Diagnostic Steps (in order of elimination)

1. **Confirmed inventory parsing was correct** and hosts were actually reachable via SSH before investigating auth further — ruled out as unrelated to a separate earlier inventory syntax issue.

2. **Checked whether the `ipaadmin_password` variable was self-referencing or missing scope** in the play (a common cause of this exact error when the var resolves to empty):
   ```yaml
   vars:
     ipaadmin_password: "{{ ipaadmin_password }}"
   ```
   → Confirmed this pattern was **not** present in the actual playbook, ruling out self-reference as the cause.

3. **Verified the variable actually resolves at runtime**, decrypted, non-empty, and in scope for the target hosts:
   ```bash
   ansible all -i inventory/inventory.ini -m debug -a "var=ipaadmin_password"
   ```
   → Returned successfully with the correct value for all target hosts. This ruled out:
   - Vault decryption failure
   - `group_vars`/`host_vars` scoping issues
   - Variable precedence problems

4. **Searched known issues for this exact error string** against `ansible-freeipa` / `ipa-client-install` behavior.
   → Consistent finding across FreeIPA documentation: this specific message is produced when `kinit` needs to prompt for a **new** password because the current one is expired, but no interactive terminal is available to answer that follow-up prompt. It is distinct from "wrong password" or "no password supplied" — the variable can be perfectly correct and still hit this error if the account itself requires a password change.

5. **Verified directly** by logging into the FreeIPA Web UI with the admin account.
   → Login immediately forced a mandatory password change, confirming the account's password was in an expired state.

6. **Confirmed via manual interactive `kinit`** on a test host:
   ```bash
   kinit admin
   ```
   → Prompted with `Password expired. You must change it now.` followed by `Enter new password` / `Enter it again` — the exact multi-prompt sequence that cannot be satisfied non-interactively, matching the Ansible failure precisely.

## Root Cause
The FreeIPA `admin` account's password was in an **expired** state (common after initial `ipa-server-install`, where the install-time password is often flagged as temporary/must-change-on-first-use). `kinit`, when run non-interactively by the Ansible role, could supply the current password but had no way to respond to the mandatory "enter new password" follow-up prompts triggered by the expiry — resulting in the misleading-sounding "Cannot read password" error, even though the credential itself was correct and correctly passed through Ansible.

## Resolution
Cleared the expired state by performing a one-time interactive password change:
```bash
kinit admin
# authenticate with current password
# respond to "Enter new password" / "Enter it again" prompts
```
or equivalently from the IPA server as root:
```bash
kpasswd admin
```
After the account password was no longer flagged as expired, re-running the playbook allowed `kinit` to authenticate in a single non-interactive step, and the join task completed successfully.

## Prevention
- After any fresh `ipa-server-install`, immediately perform one interactive `kinit`/password-change cycle for the admin account (or set a policy explicitly excluding admin from forced first-use expiry) **before** relying on it for unattended Ansible-based client enrollment.
- When troubleshooting Kerberos-related Ansible failures, don't assume the error text maps literally to "credential missing" — cross-check against the account's actual password/expiry state directly (Web UI login or manual interactive `kinit`) before treating it as a variable/vault/scope problem.