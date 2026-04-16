# TS-IDN-004 | 2026-03-05 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Identity / FreeIPA
Sub-techs: FreeIPA password policy, cospriority, Ansible ansible-freeipa
Environment: DEV lab.local | FreeIPA server freeipa.lab.local
Re-opened: No

_____________________________________________________________________

[Issue Description]
Ansible task to create a group-based password policy for automation_users fails.

  TASK [Set password policy for automation users (4 years)]
  fatal: [freeipa.lab.local]: FAILED!
  "pwpolicy_add: automation_users: 'cospriority' is required"

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked what the task was doing and what cospriority means.

Task was creating a password policy for automation_users group with 4-year expiry (maxlife: 1460).
The cospriority field was missing from the task.

Command:
  ipa help pwpolicy

Output:
  cospriority = Class of Service Priority.
  Required for group-based policies to determine which policy wins when a user
  belongs to multiple groups.

FreeIPA has two types of password policies:
  1. Global policy  — applies to all users, no priority needed
  2. Group policy   — applies to group members, cospriority required

Example conflict: super_bot is in both automation_users (4-year expiry) and
admin_users (1-year expiry). FreeIPA needs cospriority to know which one applies.
Lowest number wins.


# Suspected Root Cause
Group-based password policies require cospriority. Without it FreeIPA cannot
determine precedence when a user belongs to multiple groups with different policies.


# More Checks Notes:
N/A — error message was explicit and ipa help pwpolicy confirmed the requirement.


# Suspected Solution
Add cospriority to all group-based password policy tasks in the playbook.
Use spaced numbers (10, 20, 30...) to leave room for inserting new policies later.


# Test
Added cospriority to both automation_users and admin_users policy tasks and re-ran playbook.

Command:
  ipa pwpolicy-show automation_users
  ipa pwpolicy-show admin_users

Result: PASS — both policies created successfully with correct priority and maxlife values.

_____________________________________________________________________

[Final Root Cause]
Group-based password policies in FreeIPA require the cospriority parameter.
It was missing from the Ansible task. Without it FreeIPA has no way to resolve
which policy applies when a user belongs to multiple groups.

_____________________________________________________________________

[Final Solution]
Added cospriority to all group-based password policy tasks in
ansible/dev/playbooks/freeipa/domain_config.yml:

  automation_users: maxlife=1460, cospriority=10  (higher priority)
  admin_users:      maxlife=360,  cospriority=20  (lower priority)

Lower cospriority number = higher priority. Gaps of 10 between values so new
policies can be inserted later without renumbering.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: No impact — just adding a required parameter that was missing.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

cospriority rules:
  - Global password policy (default) does NOT need cospriority
  - Only group-based policies require it
  - Lowest number wins when user belongs to multiple groups
  - Use gaps when assigning numbers (10, 20, 30) not (1, 2, 3)
    so you can insert new policies between existing ones later