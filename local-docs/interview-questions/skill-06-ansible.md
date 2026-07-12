Skill 6 — Ansible (7 questions)
================================

Format: Standard questions only. Project examples are ammunition.
Your 76 playbooks, dual-inventory pattern, FreeIPA enrollment,
kubeadm HA automation, Vault TLS via certmonger, Jinja2 HAProxy
template, Kerberos keytab handling — inject when the bridge is earned.

---

1. What is Ansible and how does it differ from other config management and IaC tools?

   Coverage check:
   - agentless (SSH-based push model)
   - declarative tasks, procedural execution order
   - Ansible vs Terraform (config management vs infrastructure provisioning)
   - Ansible vs Puppet/Chef (agentless vs agent-based, YAML vs DSL)
   - push vs pull mode (ansible-pull exists)
   - connection types (SSH, WinRM, local)
   - privilege escalation (become)

2. What is idempotency and why does it matter in Ansible?

   Coverage check:
   - same playbook run multiple times produces same result
   - how built-in modules achieve idempotency (check state before acting)
   - when command/shell breaks idempotency (no state check)
   - creates, changed_when, failed_when to enforce idempotency
   - why idempotency matters for CI/CD (safe to re-run)

3. How do you structure Ansible code — playbooks, roles, tasks, templates?

   Coverage check:
   - playbook → plays → tasks
   - roles: directory layout (tasks, handlers, defaults, vars, templates, files)
   - handlers and when they trigger (notify, flush_handlers)
   - tags for selective execution
   - Jinja2 templates with loops and conditionals
   - variable precedence (22 levels — extra-vars wins, defaults loses)
   - facts (gather_facts, set_fact, registered variables)
   - role dependencies, Ansible Galaxy
   - lookups and filters

4. How does Ansible manage secrets?

   Coverage check:
   - Ansible Vault (encrypting files vs strings)
   - vault-id for multiple passwords
   - rekeying
   - integrating Vault with CI/CD (password file, env var)
   - separating encrypted vars from playbooks
   - env var lookups as alternative to vault-encrypted vars

5. How do you handle errors and conditional execution in Ansible?

   Coverage check:
   - ignore_errors
   - block / rescue / always (try/catch/finally pattern)
   - failed_when, changed_when
   - any_errors_fatal (stop all hosts on first failure)
   - when conditionals (facts, registered vars, hostvars)
   - conditional execution based on host properties (OS, virt type)
   - delegation (delegate_to, local_action)

6. How do you manage inventory — static, dynamic, and multi-environment?

   Coverage check:
   - static inventory (INI or YAML format)
   - groups, children, host_vars, group_vars
   - dynamic inventory (scripts, plugins — AWS, GCP, etc.)
   - patterns for targeting hosts
   - dual-inventory pattern (bootstrap IPs vs production FQDNs)
   - inventory per environment (dev vs prod)

7. How do you test and validate Ansible before running in production?

   Coverage check:
   - check mode (--check, dry run)
   - diff mode (--diff, show changes)
   - ansible-lint
   - molecule (role testing framework)
   - limit (--limit, run on subset)
   - step mode (--step)
   - performance tuning (forks, pipelining, async/poll, fact caching, strategy linear/free)
