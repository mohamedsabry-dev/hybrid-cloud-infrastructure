Skill 3 — Bash Scripting (6 questions)
=======================================

Format: Standard questions only. Project examples are ammunition
you inject into answers to bait follow-ups — not separate questions.
Your IO storm watchdog, temperature monitor, UPS monitor, bootstrap
scripts, and CI/CD retry loops are what you inject when answering.

---

1. How do you write and structure a bash script? Walk me through one you built.

   Coverage check:
   - shebang, set -e / set -o pipefail
   - variables, quoting (single vs double vs backticks)
   - conditionals (if, test, [[ ]]), loops (for, while, until)
   - functions, return values, local scope
   - exit codes, $? check
   - $@ vs $*
   - argument parsing (getopts, $1, $2, shift)
   - subshells vs current shell, $() vs backticks

2. How do you handle errors and edge cases in bash?

   Coverage check:
   - set -euo pipefail
   - trap (cleanup on exit, signal handling)
   - exit codes, || and && chaining
   - error messages to stderr
   - file test operators (-f, -d, -r, -s)
   - temp file handling (mktemp, cleanup traps)
   - timeout handling
   - handling signals (trap SIGTERM/SIGHUP)

3. How do you parse and process text — logs, config files, command output?

   Coverage check:
   - grep/awk/sed/cut/sort/uniq/tr/wc one-liners
   - piping and redirection (2>&1, >>, /dev/null, tee)
   - heredocs
   - regex (basic vs extended)
   - parsing log files (top 10 IPs, error counts)
   - reading files line by line
   - find + -exec vs xargs

4. How do you schedule and automate recurring tasks?

   Coverage check:
   - cron syntax, crontab vs /etc/cron.d
   - systemd timers
   - at command
   - cron output handling (mail vs redirect)
   - difference between source and ./script.sh

5. How do you interact with external systems from bash?

   Coverage check:
   - curl/wget for API calls
   - SSH remote execution, SSH loops across hosts
   - reading/writing files
   - environment variables
   - passing secrets safely
   - jq for JSON parsing
   - sshpass for initial provisioning

6. Walk me through debugging a bash script that works locally but fails in CI/CD.

   Coverage check:
   - set -x, bash -x, PS4
   - shellcheck
   - environment differences (PATH, shell version, installed tools)
   - permission issues
   - missing dependencies
   - interactive vs non-interactive shell
   - tty detection
