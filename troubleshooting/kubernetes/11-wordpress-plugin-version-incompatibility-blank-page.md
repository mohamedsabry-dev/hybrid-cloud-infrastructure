# TS-K8S-011 | 2026-04-04 | RESOLVED

## 1. Context

**System:** WordPress deployment on Kubernetes

**Environment:**
```
+-----------------------------------------------------------------+
|                      Kubernetes Cluster                         |
|                                                                  |
|   +----------------------------------------------------------+  |
|   |                    apps namespace                         |  |
|   |                                                           |  |
|   |   wordpress-64487cb94-66s9v  --+                         |  |
|   |   wordpress-64487cb94-8zrvc  --+-->  mariadb-svc         |  |
|   |   wordpress-64487cb94-xsrkv  --+     (database ns)       |  |
|   |                                                           |  |
|   |   Image: wordpress:6.4-php8.2-apache                     |  |
|   |   Replicas: 3 (with sticky sessions)                     |  |
|   +----------------------------------------------------------+  |
|                                                                  |
|   +----------------------------------------------------------+  |
|   |                  database namespace                       |  |
|   |                                                           |  |
|   |   mariadb-0 (StatefulSet)                                |  |
|   |   Image: mariadb:10.11                                   |  |
|   +----------------------------------------------------------+  |
+-----------------------------------------------------------------+
```

**Stack:**
- Kubernetes v1.31
- WordPress 6.4 (Docker image)
- MariaDB 10.11
- Ingress: nginx with sticky sessions
- Secrets: Vault Agent Injector

**Related Components:**
- WordPress deployment (3 replicas)
- MariaDB StatefulSet
- Vault Agent Injector (sidecar)
- Nginx Ingress with sticky sessions

**Discovered During:** Post-reboot system health check

**Duration:** ~30 minutes troubleshooting

**Note:** Password-related login issues are a separate problem documented in Case 10.

---

## 2. Issue

**Symptom:**
After server reboot, WordPress displayed blank/empty pages in browser while `curl` returned HTML content.

**Initial observation:**
- Browser: Blank/empty white page
- `curl`: Returns valid HTML content
- Login page (`/wp-admin`): Loads but rejects correct password
- Redirect loop when clicking any admin link

**Pod status:**
```bash
$ kubectl get pods -n apps
NAME                        READY   STATUS    RESTARTS        AGE
wordpress-64487cb94-66s9v   2/2     Running   2 (7m57s ago)   51m
wordpress-64487cb94-8zrvc   2/2     Running   2 (7m57s ago)   51m
wordpress-64487cb94-xsrkv   2/2     Running   2 (8m55s ago)   51m

$ kubectl get pods -n database
NAME        READY   STATUS    RESTARTS        AGE
mariadb-0   2/2     Running   2 (8m59s ago)   87m
```

**Curl test (works):**
```bash
$ curl http://wordpress-dev.lab.local
<!doctype html>
<html lang="en-US">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5, viewport-fit=cover">
    <link rel="profile" href="https://gmpg.org/xfn/11">
    <meta name='robots' content='index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1' />
```

**Browser DevTools (F12 -> Console):**
```
wp-login:1 Failed to load resource: the server responded with a status of 404 (Not Found)
```

**Impact:**
- WordPress site completely inaccessible via browser
- Admin dashboard unusable
- All 3 replicas affected

---

## 3. Analysis

### Step 1: Verify Infrastructure is Running

**Commands:**
```bash
kubectl get pods -n apps
kubectl get pods -n database
```

**Result:** All pods Running with 2/2 Ready (includes vault-agent sidecar)

**Analysis:** Infrastructure is healthy - issue is application-level.

---

### Step 2: Verify Database Connectivity

**Command:**
```bash
kubectl exec -it mariadb-0 -n database -- mysqladmin ping -u root -p
```

**Result:**
```
Enter password:
mysqld is alive
```

**Analysis:** Database is responsive.

---

### Step 3: Check WordPress Application Logs (CRITICAL)

**Command:**
```bash
kubectl logs -n apps -l app=wordpress --tail=100
```

**Result - THE SMOKING GUN:**
```
[Sat Apr 04 14:35:43.454793 2026] [php:error] [pid 70] [client 10.0.64.11:0]
PHP Fatal error:  Uncaught Error: Call to undefined function wp_is_serving_rest_request()
in /var/www/html/wp-content/plugins/wordpress-seo/src/integrations/front-end-integration.php:640
Stack trace:
#0 /var/www/html/wp-content/plugins/wordpress-seo/src/integrations/front-end-integration.php(550):
   Yoast\WP\SEO\Integrations\Front_End_Integration->maybe_remove_title_presenter(Array)
#1 /var/www/html/wp-content/plugins/wordpress-seo/src/integrations/front-end-integration.php(506):
   Yoast\WP\SEO\Integrations\Front_End_Integration->get_needed_presenters('Home_Page')
...
```

**Key Error:**
```
Call to undefined function wp_is_serving_rest_request()
```

**Analysis:** The function `wp_is_serving_rest_request()` was introduced in **WordPress 6.5**. The Yoast SEO plugin requires this function, but the deployment uses **WordPress 6.4** image.

---

### Step 4: Verify WordPress Version

**Command:**
```bash
kubectl exec -it wordpress-64487cb94-8zrvc -n apps -c wordpress -- grep "wp_version =" /var/www/html/wp-includes/version.php
```

**Result:**
```
$wp_version = '6.4';
```

**Analysis:** Confirms WordPress 6.4 - missing the required function.

---

### Step 5: Check wp-config.php (Database Connection)

**Command:**
```bash
kubectl exec -it wordpress-64487cb94-8zrvc -n apps -c wordpress -- cat /var/www/html/wp-config.php | grep -i "db"
```

**Result:**
```php
define( 'DB_NAME', getenv_docker('WORDPRESS_DB_NAME', 'wordpress') );
define( 'DB_USER', getenv_docker('WORDPRESS_DB_USER', 'example username') );
define( 'DB_PASSWORD', getenv_docker('WORDPRESS_DB_PASSWORD', 'example password') );
define( 'DB_HOST', getenv_docker('WORDPRESS_DB_HOST', 'mysql') );
```

**Analysis:** Database configuration looks correct (uses environment variables from Vault).

---

### Step 6: Check Active Plugins in Database

**Command:**
```bash
kubectl exec -it mariadb-0 -n database -- mysql -u root -p -e \
  "SELECT option_value FROM wordpress.wp_options WHERE option_name = 'active_plugins';"
```

**Result:**
```
+--------------------------------------------+
| option_value                               |
+--------------------------------------------+
| a:1:{i:0;s:24:"wordpress-seo/wp-seo.php";} |
+--------------------------------------------+
```

**Analysis:** Only Yoast SEO (`wordpress-seo`) is active - confirms it's the problematic plugin.

---

### Evidence Summary

| Evidence | Location | Finding |
|----------|----------|---------&|
| PHP Fatal Error | `kubectl logs -n apps -l app=wordpress` | `Call to undefined function wp_is_serving_rest_request()` |
| WordPress Version | `/var/www/html/wp-includes/version.php` | 6.4 (needs 6.5 for the function) |
| Active Plugins | `wp_options.active_plugins` | Only `wordpress-seo` active |
| Plugin File | `/var/www/html/wp-content/plugins/wordpress-seo/` | Yoast SEO (requires WP 6.5+) |

---

## 4. Root Cause

### Primary Cause: Plugin Version Incompatibility

```
+-----------------------------------------------------------------+
|                     VERSION MISMATCH                             |
|                                                                  |
|   WordPress Image: 6.4-php8.2-apache                            |
|                    +--- Does NOT have wp_is_serving_rest_request()
|                                                                  |
|   Yoast SEO Plugin: Latest version (installed via web UI)       |
|                     +--- REQUIRES wp_is_serving_rest_request()  |
|                          (added in WordPress 6.5)               |
|                                                                  |
|   Result: PHP Fatal Error -> Blank page                          |
+-----------------------------------------------------------------+
```

### Why It Happened After Reboot

1. Before reboot: Plugin was active and somehow working (possibly cached)
2. After reboot: Fresh pod startup, plugin loaded, fatal error triggered immediately
3. PHP fatal error = no output = blank page in browser
4. `curl` returns partial HTML (rendered before fatal error occurred)

### Why Browser Shows Blank But Curl Shows Content

- PHP starts rendering HTML
- Fatal error occurs mid-render
- `curl` shows partial output up to error point
- Browser requires complete response to render properly

---

## 5. Solution

### Immediate Fix (Applied)

**Step 7: Disable Plugin via Database**

**Command:**
```bash
kubectl exec -it mariadb-0 -n database -- mysql -u root -p

# Then in MySQL:
USE wordpress;
UPDATE wp_options SET option_value = 'a:0:{}' WHERE option_name = 'active_plugins';
```

**Result:**
```
Query OK, 1 row affected (0.003 sec)
Rows matched: 1  Changed: 1  Warnings: 0
```

**IMPORTANT: Restart pods after disabling plugins via database!**

```bash
kubectl rollout restart deployment wordpress -n apps
```

Why? PHP/Apache cache the plugin code in memory. Even after database update:
- OPcache still has compiled plugin code
- Apache processes still running with old code loaded
- Changes won't fully take effect until pod restart

---

### Step 8: Verify Fix

**Action:** Refresh browser

**Result:** WordPress loads correctly! Login works!

---

### Permanent Fix Options

**Option 1: Update WordPress Image (Recommended)**
```yaml
# deployment.yaml
containers:
  - name: wordpress
    image: wordpress:6.5-php8.2-apache  # or wordpress:latest
```

**Option 2: Downgrade Plugin**
- Install Yoast SEO version compatible with WordPress 6.4
- Check plugin changelog for version requirements

**Option 3: Use Alternative Plugin**
- Simple SEO plugins that don't require latest WP functions

---

### Prevention Measures

- Pin plugin versions for stability
- Add WordPress version check to monitoring/alerts
- Test plugin updates in staging environment before production
- Document WordPress image version requirements

---

## 6. Solution Risk

**Risk Level:** Low (for immediate fix), Medium (for permanent fix)

**Potential Impact:**

*Immediate Fix (disable plugin):*
- SEO functionality temporarily lost
- No site downtime during fix
- Easily reversible

*Permanent Fix (update WordPress image):*
- Requires deployment update and pod restart
- Brief downtime during rollout
- Other plugins may have compatibility issues with new WP version
- Test thoroughly in staging first

---

## 7. Impact After Fix

**Observed Results:**
- WordPress site loads correctly in browser
- Admin dashboard accessible
- Login functionality restored
- All 3 replicas serving traffic normally

**Action Items:**
- [x] Disable incompatible plugin via database
- [ ] Update WordPress image to 6.5+ in deployment.yaml
- [ ] Consider pinning plugin versions for stability
- [ ] Add WordPress version check to monitoring/alerts

---

## 8. Notes

### Lessons Learned

1. **Check application logs FIRST** - They usually contain the exact error
2. **Version compatibility matters** - Plugin updates can break older WordPress versions
3. **Database is shared state** - Changes to `wp_options` affect all pods immediately
4. **`curl` vs browser difference** - Indicates partial render / fatal error scenario
5. **Pin your versions** - Consider pinning plugin versions or using WP-CLI for updates

---

### Systematic Troubleshooting Flow (For Future Reference)

```
Browser Issue (blank page, login fail, etc.)
    |
    v
+------------------------------------------+
| Step 1: curl vs Browser                   |
| curl http://site  -> Compare output       |
| If curl works, browser doesn't -> JS/CSS  |
| If both fail -> Server-side issue         |
+------------------------------------------+
    |
    v
+------------------------------------------+
| Step 2: Check Pod Status                  |
| kubectl get pods -n <namespace>           |
| All Running? Correct READY count?         |
+------------------------------------------+
    |
    v
+------------------------------------------+
| Step 3: Check Database                    |
| kubectl exec mariadb-0 -- mysqladmin ping |
| Is DB alive and reachable?                |
+------------------------------------------+
    |
    v
+------------------------------------------+
| Step 4: Check Application Logs *          |
| kubectl logs -n <ns> -l app=<app>         |
| Look for: error, fatal, exception         |
| THIS USUALLY REVEALS ROOT CAUSE           |
+------------------------------------------+
    |
    v
+------------------------------------------+
| Step 5: Check Configuration               |
| - wp-config.php (WordPress)               |
| - Environment variables                   |
| - Vault secrets injection                 |
+------------------------------------------+
    |
    v
+------------------------------------------+
| Step 6: Check Database State              |
| - Active plugins                          |
| - User accounts                           |
| - Site URL settings                       |
+------------------------------------------+
    |
    v
+------------------------------------------+
| Step 7: Apply Fix & Verify                |
| - Disable plugins via DB                  |
| - Update image version                    |
| - Clear browser cache                     |
+------------------------------------------+
```

---

### Commands Reference

#### Check Pod Status
```bash
kubectl get pods -n apps
kubectl get pods -n database
kubectl describe pod <pod-name> -n <namespace>
```

#### Check Application Logs
```bash
# All pods with label
kubectl logs -n apps -l app=wordpress --tail=100

# Specific pod
kubectl logs -n apps wordpress-xxxx -c wordpress --tail=100

# Follow logs
kubectl logs -n apps -l app=wordpress -f
```

#### Check Database
```bash
# Ping test
kubectl exec -it mariadb-0 -n database -- mysqladmin ping -u root -p

# Interactive MySQL
kubectl exec -it mariadb-0 -n database -- mysql -u root -p

# One-liner query
kubectl exec -it mariadb-0 -n database -- mysql -u root -p -e "SELECT * FROM wordpress.wp_options WHERE option_name='active_plugins';"
```

#### WordPress Troubleshooting
```bash
# Check wp-config.php
kubectl exec -it <wordpress-pod> -n apps -c wordpress -- cat /var/www/html/wp-config.php

# Check WordPress version
kubectl exec -it <wordpress-pod> -n apps -c wordpress -- grep "wp_version" /var/www/html/wp-includes/version.php

# List plugins
kubectl exec -it <wordpress-pod> -n apps -c wordpress -- ls /var/www/html/wp-content/plugins/
```

#### Disable Plugins via Database
```bash
# Disable ALL plugins
kubectl exec -it mariadb-0 -n database -- mysql -u root -p -e \
  "UPDATE wordpress.wp_options SET option_value = 'a:0:{}' WHERE option_name = 'active_plugins';"

# IMPORTANT: Restart pods after database change!
kubectl rollout restart deployment wordpress -n apps

# Or disable specific plugin by renaming folder
kubectl exec -it <wordpress-pod> -n apps -c wordpress -- \
  mv /var/www/html/wp-content/plugins/wordpress-seo /var/www/html/wp-content/plugins/wordpress-seo.disabled
```

---

### Related Files
- WordPress deployment manifest
- MariaDB StatefulSet manifest
- Vault secrets configuration

---

### References

- [Stack Overflow: Fatal error on WordPress - Call to undefined function wp](https://stackoverflow.com/questions/31031133/fatal-error-on-wordpress-call-to-undefined-function-wp-in-wp-blog-header-php)
- [WordPress 6.5 Release Notes - wp_is_serving_rest_request()](https://developer.wordpress.org/reference/functions/wp_is_serving_rest_request/)
- [Yoast SEO Plugin Requirements](https://yoast.com/help/requirements-for-yoast-seo/)

---

## 9. Workaround

### Temporary Workaround (Applied)

Disable the incompatible plugin via database update:

```sql
-- Disable all plugins
UPDATE wp_options SET option_value = 'a:0:{}' WHERE option_name = 'active_plugins';
```

Then restart pods:
```bash
kubectl rollout restart deployment wordpress -n apps
```

**Limitations:**
- SEO functionality unavailable while plugin is disabled
- Must re-enable plugin after WordPress upgrade
- Alternative: Rename plugin folder to disable without database change:
  ```bash
  kubectl exec -it <wordpress-pod> -n apps -c wordpress -- \
    mv /var/www/html/wp-content/plugins/wordpress-seo /var/www/html/wp-content/plugins/wordpress-seo.disabled
  ```
