# TS-K8S-010 | 2026-04-04 | MONITORING

## 1. Context

- **System:** WordPress / MariaDB / Authentication
- **Environment:** k8s-dev cluster only (NOT observed in prod)
- **Related Components:** WordPress deployment, MariaDB StatefulSet, wp_users table, wp-config.php
- **Discovered During:** Post-reboot login attempt
- **Related:** None (initially suspected Case 8, but confirmed unrelated)

---

## 2. Issue

**Symptom:** WordPress admin login fails with "incorrect password" despite the password hash existing in the database.

**Observations:**
- WordPress login page loads correctly
- Entering correct password results in "incorrect password" error
- Password hash exists in database with valid format (`$wp$2y$10$...` bcrypt format)
- No plugin-related PHP errors in logs (unlike Case 8)
- Issue only observed on dev cluster, not prod

**Occurrences:**

| Date | Trigger | Environment | Notes |
|------|---------|-------------|-------|
| 2026-04-04 | Server reboot | dev | First occurrence |
| 2026-04-06 | Flux reconcile (StorageClass changes) | dev | MariaDB pod recreated |

**Impact:** Admin users locked out of WordPress dashboard on dev cluster.

---

## 3. Analysis

### Step 1: Verify Password Hash Exists

```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
  "SELECT user_login, LEFT(user_pass, 10) as hash_prefix FROM wordpress.wp_users WHERE ID = 1;"
```

**Result:**
```
+------------+-------------+
| user_login | hash_prefix |
+------------+-------------+
| admin      | $wp$2y$10$  |
+------------+-------------+
```

**Analysis:** Hash exists and format is valid WordPress bcrypt/phpass (`$wp$2y$10$`).

### Step 2: Verify PVC Data Intact

```bash
kubectl get pvc -n database
kubectl get pvc -n apps
```

**Result:**
```
NAME                     STATUS   VOLUME   CAPACITY   STORAGECLASS   AGE
mariadb-data-mariadb-0   Bound    ...      15Gi       nfs-retain     2d7h

NAME             STATUS   VOLUME   CAPACITY   STORAGECLASS   AGE
wordpress-data   Bound    ...      15Gi       nfs-retain     2d6h
```

**Analysis:** PVCs are old (2d+), data was not lost. Issue is not data loss.

### Step 3: Check WordPress Logs for Errors

```bash
kubectl logs -n apps -l app=wordpress --tail=50 | grep -i error
```

**Result:** No PHP errors related to authentication or functions.

**Analysis:** Unlike Case 8 (plugin incompatibility), no application errors present.

---

## 4. Root Cause

**Not yet determined. Under monitoring.**

**Possible Causes (Unconfirmed):**

| Possible Cause | Likelihood | Status |
|----------------|------------|--------|
| WordPress AUTH_KEY/SALT regeneration | Medium | Not investigated |
| Cookie/session invalidation | Medium | Not investigated |
| WordPress upgrade routines on pod restart | Low | Not investigated |
| wp-config.php regeneration with new salts | Medium | Not investigated |
| Database encoding/charset issue | Low | Not investigated |

**Key Observation:** Issue only occurs on dev, not prod. Difference may be in how the environments were initially set up.

---

## 5. Solution

### Workaround Applied: Reset Password via Database

```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
  "UPDATE wordpress.wp_users SET user_pass = MD5('YourNewPassword') WHERE user_login = 'admin';"
```

WordPress accepts MD5 and automatically re-hashes to bcrypt on first successful login.

**Example (used on 2026-04-06):**
```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
  "UPDATE wordpress.wp_users SET user_pass = MD5('YourSecurePassword') WHERE user_login = 'admin';"
```

### Long-term Investigation (TODO)

1. Compare wp-config.php between dev and prod (especially AUTH_KEY, SECURE_AUTH_KEY, etc.)
2. Check if WordPress entrypoint script regenerates salts on each restart
3. Consider mounting entire `/var/www/html` to PVC instead of just `wp-content`
4. Monitor if issue correlates with specific pod events (image change, node migration, etc.)

### Key Differences: Dev vs Prod

| Aspect | Dev | Prod |
|--------|-----|------|
| Issue observed | Yes (multiple times) | No (never) |
| Initial setup | Quick setup for testing | Careful manual setup |
| WordPress image | Same | Same |
| MariaDB version | Same | Same |
| NFS storage | Same server, different share | Same server, different share |

**Note:** Prod may have been set up differently (e.g., password set via wp-cli or manual SQL initially), which could explain why it's not affected.

---

## 6. Solution Risk

- **Risk Level:** Low
- **Potential Impact:**
  - Password reset via MD5: Temporary weaker hash until user logs in (then auto-upgraded to bcrypt)
  - Does not solve root cause - issue may recur
  - Only affects dev cluster currently

---

## 7. Impact After Fix

**Observed Results:**
- Admin login restored immediately after password reset
- No data loss or corruption
- Issue may recur on next pod recreation/restart

---

## 8. Notes

### Lessons Learned

- Password hash format can be valid but authentication may still fail due to salt/key issues
- WordPress uses cookies that depend on AUTH_KEY and related salts in wp-config.php
- If salts change, existing sessions and possibly password validation can break

### Commands Reference

#### Check Password Hash
```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
  "SELECT user_login, user_pass FROM wordpress.wp_users WHERE user_login = 'admin';"
```

#### Reset Password
```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
  "UPDATE wordpress.wp_users SET user_pass = MD5('NewPassword') WHERE user_login = 'admin';"
```

#### Check User Registration Date
```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
  "SELECT user_login, user_registered FROM wordpress.wp_users;"
```

#### Check WordPress Startup Logs
```bash
kubectl logs -n apps -l app=wordpress | grep -i "WordPress not found\|copying now\|install"
```

### Action Items

- [ ] Investigate AUTH_KEY/SALT differences between dev and prod
- [ ] Determine if wp-config.php salts regenerate on pod restart
- [ ] Consider persistent wp-config.php solution
- [ ] Track next occurrence to gather more data

---

## 9. Workaround

**Temporary:** Reset password via database when issue occurs:

```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
  "UPDATE wordpress.wp_users SET user_pass = MD5('YourNewPassword') WHERE user_login = 'admin';"
```

WordPress accepts MD5 hashes and automatically upgrades to bcrypt on first successful login.

**Note:** This workaround must be repeated each time the issue recurs. Root cause investigation needed for permanent fix.
