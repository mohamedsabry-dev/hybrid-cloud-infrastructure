# TS-GH-006 | 2026-03-16 | RESOLVED
_____________________________________________________________________

[Info]
Domain: GitHub Actions / Security
Sub-techs: Git history rewrite, git-filter-repo, MAC address redaction, .gitignore
Environment: hybrid-cloud-infrastructure repository
Re-opened: No

_____________________________________________________________________

[Issue Description]
Security audit finding — not a live failure.
Hardware MAC addresses from physical network interfaces found in git history.
Raw command outputs and server config files were committed before .gitignore
rules were added. File deletion does not remove content from git history.

Why MAC addresses matter:
  - Identify and track physical devices
  - Reveal network topology and infrastructure details
  - Combined with other data, enable targeted attacks

Data found:
  1. WiFi Adapter MAC    — deleted server config file, still in history
  2. Ethernet Adapter MAC— deleted server config file, still in history
  3. USB Ethernet MAC    — current file storage/drafted_test_raw_output.txt + history

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Searched current files and git history for MAC address patterns.

Command:
  grep -rE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' . --include="*" 2>/dev/null \
    | grep -v ".git/"

Output:
  MAC address found in storage/drafted_test_raw_output.txt (current file).

Command:
  git log -p --all | grep -iE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -50

Output:
  Multiple real MACs in deleted files still present in history.
  Placeholder MACs (AA:BB:CC:DD:EE:FF, 11:22:33:44:55:66) confirmed safe — docs only.


# Suspected Root Cause
Raw command outputs and server config files containing hardware MAC addresses
were committed before .gitignore rules were in place. Even after the files were
deleted, git history retains the full content of every commit.


# More Checks Notes:
Ran full deep inspection audit while in cleanup mode to confirm no other
sensitive categories were exposed.

  MAC addresses          grep ([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}  Found & cleaned
  Personal emails        grep @gmail|@yahoo|@hotmail               None found
  AWS access keys        grep AKIA[A-Z0-9]{16}                     None found
  GitHub tokens          grep ghp_|gho_|github_pat_                None found
  Private keys           grep BEGIN.*PRIVATE KEY                   None found
  Hardcoded passwords    grep password.*=.*['"]                    Placeholders only


# Suspected Solution
Redact MACs in current files and rewrite git history using git-filter-repo
to replace all real MAC addresses with XX:XX:XX:XX:XX:XX placeholders.


# Test
Ran git-filter-repo with MAC replacement patterns, force-pushed, verified history.

Command:
  git log -p --all | grep -iE '<WIFI_MAC>|<ETHERNET_MAC>'

Result: PASS — no matches, all real MACs replaced with placeholders.

_____________________________________________________________________

[Final Root Cause]
Raw command output files and server config files containing hardware MAC addresses
were committed before .gitignore rules were added. File deletion removed them from
the working tree but not from git history — every past commit is permanently
retained and searchable.

_____________________________________________________________________

[Final Solution]
Redacted current files and rewrote git history using git-filter-repo.

  # 1. Create replacement patterns file
  <WIFI_MAC>==>XX:XX:XX:XX:XX:XX
  <ETHERNET_MAC>==>XX:XX:XX:XX:XX:XX
  <USB_ETHERNET_MAC>==>XX:XX:XX:XX:XX:XX

  # 2. Run filter-repo
  git filter-repo --replace-text /tmp/mac-replacements.txt --force

  # 3. Re-add remote and force push
  git remote add origin git@github.com:<USERNAME>/<REPO>.git
  git push origin --force --all
  git push origin --force --tags

  # 4. Verify
  git log -p --all | grep -iE '<WIFI_MAC>|<ETHERNET_MAC>'
  → no matches

NOTE: All existing clones invalidated after force push. Re-clone required.

Added to .gitignore to prevent recurrence:
  **/test_raw_output*.txt
  **/network_scan*.txt
  **/interface_discovery*.txt

Verified: Yes

_____________________________________________________________________

[Risk Level] HIGH
Note: History rewrite invalidates all collaborator clones. Force push required.
Disable branch protection before running, re-enable after.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Part of security cleanup chain:
  TS-GH-003        → delete workflow logs with exposed secrets
  TS-GH-004        → git history cleanup (AWS IDs, EIPs, passwords)
  TS-GH-006 (this) → MAC address deep inspection cleanup

Pre-commit hook to block real MAC addresses from being committed:
  #!/bin/bash
  if git diff --cached | grep -qE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}'; then
    if git diff --cached | grep -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | \
       grep -qvE '(XX:XX|AA:BB|11:22|00:00|FF:FF)'; then
      echo "ERROR: Commit contains MAC address. Please redact."
      exit 1
    fi
  fi

Workaround if history rewrite not possible:
  Redact current files, add to .gitignore, accept history exposure as residual risk.