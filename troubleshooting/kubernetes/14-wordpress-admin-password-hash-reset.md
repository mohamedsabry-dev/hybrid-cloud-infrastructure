# Case 14: WordPress Admin Password Hash Reset Issue

## Status: MONITORING
## Date: 2026-04-04 (initial), 2026-04-06 (recurrence)
## Severity: Medium
## Environment: k8s-dev cluster only (NOT observed in prod)
## Related: None (initially suspected Case 7, but confirmed unrelated)

---

## 1. Issue Summary

WordPress admin login fails with "incorrect password" despite the password hash existing in the database. The password hash appears valid (`$wp$2y$10$...` bcrypt format) but authentication fails. Issue has been observed multiple times on dev cluster but never on prod.

**Root Cause:** Not yet determined. Under monitoring.

**Resolution:** Reset password via database.

---

## 2. Symptoms

- WordPress login page loads correctly
- Entering correct password results in "incorrect password" error
- Password hash exists in database with valid format
- No plugin-related PHP errors in logs (unlike Case 7)
- Issue only observed on dev cluster, not prod

---

## 3. Occurrences

| Date | Trigger | Environment | Notes |
|------|---------|-------------|-------|
| 2026-04-04 | Server reboot | dev | First occurrence |
| 2026-04-06 | Flux reconcile (StorageClass changes) | dev | MariaDB pod recreated |

---

## 4. Investigation

### 4.1 Verify Password Hash Exists

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

### 4.2 Verify PVC Data Intact

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

### 4.3 Check WordPress Logs for Errors

```bash
kubectl logs -n apps -l app=wordpress --tail=50 | grep -i error
```

**Result:** No PHP errors related to authentication or functions.

**Analysis:** Unlike Case 7 (plugin incompatibility), no application errors present.

---

## 5. Possible Causes (Unconfirmed)

| Possible Cause | Likelihood | Status |
|----------------|------------|--------|
| WordPress AUTH_KEY/SALT regeneration | Medium | Not investigated |
| Cookie/session invalidation | Medium | Not investigated |
| WordPress upgrade routines on pod restart | Low | Not investigated |
| wp-config.php regeneration with new salts | Medium | Not investigated |
| Database encoding/charset issue | Low | Not investigated |

**Key Observation:** Issue only occurs on dev, not prod. Difference may be in how the environments were initially set up.

---

## 6. Resolution (Workaround)

Reset password via database:

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

---

## 7. Key Differences: Dev vs Prod

| Aspect | Dev | Prod |
|--------|-----|------|
| Issue observed | Yes (multiple times) | No (never) |
| Initial setup | Quick setup for testing | Careful manual setup |
| WordPress image | Same | Same |
| MariaDB version | Same | Same |
| NFS storage | Same server, different share | Same server, different share |

**Note:** Prod may have been set up differently (e.g., password set via wp-cli or manual SQL initially), which could explain why it's not affected.

---

## 8. Recommendations

### Short-term (Current)
- Reset password via database when issue occurs
- Document occurrences to identify pattern

### Long-term Investigation (TODO)
1. Compare wp-config.php between dev and prod (especially AUTH_KEY, SECURE_AUTH_KEY, etc.)
2. Check if WordPress entrypoint script regenerates salts on each restart
3. Consider mounting entire `/var/www/html` to PVC instead of just `wp-content`
4. Monitor if issue correlates with specific pod events (image change, node migration, etc.)

---

## 9. Commands Reference

### Check Password Hash
```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
  "SELECT user_login, user_pass FROM wordpress.wp_users WHERE user_login = 'admin';"
```

### Reset Password
```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
  "UPDATE wordpress.wp_users SET user_pass = MD5('NewPassword') WHERE user_login = 'admin';"
```

### Check User Registration Date
```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p -e \
  "SELECT user_login, user_registered FROM wordpress.wp_users;"
```

### Check WordPress Startup Logs
```bash
kubectl logs -n apps -l app=wordpress | grep -i "WordPress not found\|copying now\|install"
```

---

## 10. Status

**MONITORING** - Root cause not yet determined. Workaround available.

**Action Items:**
- [ ] Investigate AUTH_KEY/SALT differences between dev and prod
- [ ] Determine if wp-config.php salts regenerate on pod restart
- [ ] Consider persistent wp-config.php solution
- [ ] Track next occurrence to gather more data
