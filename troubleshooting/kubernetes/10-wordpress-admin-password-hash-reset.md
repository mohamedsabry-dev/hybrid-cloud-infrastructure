# TS-K8S-010 | 2026-04-04 | TEMP CLOSED
# NOTE: No recurrence observed in 10+ days as of 2026-04-16.
# Temporarily closed — root cause still unconfirmed. Reopen if issue returns.
_____________________________________________________________________

[Info]
Author:
Domain: Kubernetes / WordPress
Sub-techs: WordPress authentication, MariaDB, wp_users, wp-config.php, AUTH_KEY/SALT,
           bcrypt/phpass, NFS PVC
Environment: DEV k8s-dev cluster ONLY (not observed in prod)
Re-opened: No

_____________________________________________________________________

[Issue Description]
WordPress admin login fails with "incorrect password" despite correct password
hash existing in the database. Only observed on dev cluster.

  WordPress login page loads correctly.
  Entering correct password → "incorrect password" error.
  Password hash in DB: valid $wp$2y$10$ (bcrypt/phpass format).
  No PHP errors in logs.

Occurrences:
  2026-04-04  Server reboot                        first occurrence
  2026-04-06  Flux reconcile (StorageClass change) → MariaDB pod recreated
  2026-04-16  No recurrence in 10+ days            monitoring period closed

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

Step 1 — Verify password hash exists:
  Command:
    kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
    "SELECT user_login, LEFT(user_pass, 10) as hash_prefix FROM wordpress.wp_users WHERE ID = 1;"

  Output:
    admin | $wp$2y$10$
    Hash exists, format is valid WordPress bcrypt. Not a data corruption issue.

Step 2 — Verify PVC data intact:
  Command:
    kubectl get pvc -n database
    kubectl get pvc -n apps

  Output:
    mariadb-data-mariadb-0   Bound  15Gi  nfs-retain  2d7h
    wordpress-data           Bound  15Gi  nfs-retain  2d6h
    PVCs are 2+ days old — data was not lost on reboot/reconcile.

Step 3 — Check WordPress logs for errors:
  Command:
    kubectl logs -n apps -l app=wordpress --tail=50 | grep -i error

  Output:
    No PHP errors related to authentication or functions.
    Unlike TS-K8S-011 (plugin incompatibility), no application errors present.

Key observation: issue only occurs on dev, not prod. Environments may have
been set up differently — prod may have had password set via wp-cli or manual
SQL initially, which could explain why it is not affected.


# Suspected Root Cause
Not confirmed. Under monitoring — no recurrence in 10+ days as of 2026-04-16.

Possible causes (unconfirmed):
  WordPress AUTH_KEY/SALT regeneration on pod restart    Medium likelihood
  Cookie/session invalidation after salt change          Medium likelihood
  wp-config.php regenerated with new salts on restart    Medium likelihood
  WordPress upgrade routines running on pod restart      Low likelihood
  Database encoding/charset issue                        Low likelihood

WordPress uses AUTH_KEY and related salts from wp-config.php for cookie
signing and password validation. If salts regenerate on pod restart,
existing sessions and possibly password authentication can break.


# More Checks Notes:
Pattern observed on first two occurrences: issue correlated with pod recreation
events (reboot 2026-04-04, MariaDB pod recreated by Flux 2026-04-06). Suggests
something regenerates on pod startup, not a persistent data issue.

No recurrence since 2026-04-06. Possible that TS-K8S-011 fix (WordPress image
update or pod restart changes) indirectly resolved this, or the triggering
condition has not occurred again. Not enough evidence to confirm either way.


# Suspected Solution
Investigate whether wp-config.php salts regenerate on pod restart.
Compare wp-config.php AUTH_KEY/SALT values between dev and prod.
Consider mounting entire /var/www/html to PVC instead of only wp-content.


# Test
Workaround applied — password reset via database SQL on both occurrences.
MD5 hash accepted by WordPress, auto-upgraded to bcrypt on first successful login.

Result: PASS (workaround) — admin login restored on both occurrences.
No recurrence since 2026-04-06 (10+ days as of 2026-04-16).

_____________________________________________________________________

[Final Root Cause]
Not confirmed. Investigation paused — no recurrence in 10+ days.
If issue returns, resume investigation starting with wp-config.php salt
comparison between dev and prod.

_____________________________________________________________________

[Final Solution]
Workaround only — root cause investigation paused pending recurrence.

Password reset via database when issue occurs:
  kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
  "UPDATE wordpress.wp_users SET user_pass = MD5('YourNewPassword') WHERE user_login = 'admin';"

WordPress accepts MD5 hashes and automatically upgrades to bcrypt on first
successful login after the reset.

Verified: Yes (workaround only)

_____________________________________________________________________

[Risk Level] LOW
Note: MD5 reset temporarily weaker hash until user logs in (auto-upgraded to bcrypt).
Root cause unconfirmed but no recurrence in 10+ days. Dev cluster only.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Dev vs prod comparison:
  Issue observed       Dev: yes (2 times, last 2026-04-06)  Prod: never
  Initial setup        Dev: quick test setup                  Prod: careful manual setup
  WordPress image      same
  MariaDB version      same
  NFS storage          same server, different share

If issue recurs — resume investigation:
  [ ] Compare wp-config.php between dev and prod (AUTH_KEY, SECURE_AUTH_KEY,
      LOGGED_IN_KEY, NONCE_KEY and all SALT values)
  [ ] Check if WordPress entrypoint script regenerates salts on each restart
  [ ] Consider mounting entire /var/www/html to PVC not just wp-content
  [ ] Check if TS-K8S-011 fix was the indirect resolution

Commands reference:
  Check password hash:
    kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
    "SELECT user_login, user_pass FROM wordpress.wp_users WHERE user_login = 'admin';"

  Reset password:
    kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
    "UPDATE wordpress.wp_users SET user_pass = MD5('NewPassword') WHERE user_login = 'admin';"

  Check user registration date:
    kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
    "SELECT user_login, user_registered FROM wordpress.wp_users;"

  Check WordPress startup logs for reinstall events:
    kubectl logs -n apps -l app=wordpress | grep -i "WordPress not found\|copying now\|install"