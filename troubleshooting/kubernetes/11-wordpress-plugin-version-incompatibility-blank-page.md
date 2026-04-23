# TS-K8S-011 | 2026-04-04 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / WordPress
Sub-techs: WordPress plugin compatibility, MariaDB, PHP fatal error, OPcache,
           Vault Agent Injector, Nginx Ingress sticky sessions
Environment: DEV k8s-dev cluster | apps namespace
  Stack: Kubernetes v1.31, WordPress 6.4-php8.2-apache (3 replicas, sticky sessions),
         MariaDB 10.11, Nginx Ingress, Vault Agent Injector sidecar
Re-opened: No

_____________________________________________________________________

[Issue Description]
After server reboot, WordPress displays blank/empty pages in browser while curl
returns HTML content. Login page loads but rejects correct password. Redirect
loop on admin links.

  Browser:  blank white page
  curl:     returns valid HTML content
  /wp-admin: loads but rejects password, redirect loops

  All pods Running 2/2 (includes vault-agent sidecar).
  Browser DevTools: wp-login:1 Failed to load resource: 404 Not Found

Note: password rejection is a separate issue documented in TS-K8S-010.
This ticket covers the blank page / PHP fatal error issue only.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Verified infrastructure first — all pods running, MariaDB responsive.

Step 1 — Verify pods:
  kubectl get pods -n apps && kubectl get pods -n database
  All Running 2/2. Not an infrastructure issue — application-level.

Step 2 — Verify database:
  kubectl exec -it mariadb-0 -n database -- mysqladmin ping -u root -p
  → mysqld is alive

Step 3 — Check WordPress application logs (CRITICAL FINDING):
  Command:
    kubectl logs -n apps -l app=wordpress --tail=100

  Output:
    [Sat Apr 04 14:35:43.454793 2026] [php:error]
    PHP Fatal error: Uncaught Error: Call to undefined function wp_is_serving_rest_request()
    in .../plugins/wordpress-seo/src/integrations/front-end-integration.php:640
    Stack trace:
    #0 .../front-end-integration.php(550): maybe_remove_title_presenter(Array)
    #1 .../front-end-integration.php(506): get_needed_presenters('Home_Page')

  wp_is_serving_rest_request() was introduced in WordPress 6.5.
  Yoast SEO plugin requires this function.
  WordPress image is 6.4 — function does not exist.

Step 4 — Verify WordPress version:
  kubectl exec -it <pod> -n apps -c wordpress -- \
    grep "wp_version =" /var/www/html/wp-includes/version.php
  → $wp_version = '6.4'

Step 5 — Check active plugins in database:
  kubectl exec -it mariadb-0 -n database -- mysql -u root -p -e \
    "SELECT option_value FROM wordpress.wp_options WHERE option_name = 'active_plugins';"
  → a:1:{i:0;s:24:"wordpress-seo/wp-seo.php";}
  Only Yoast SEO active — confirmed as the problematic plugin.

Evidence summary:
  PHP Fatal Error    kubectl logs -n apps -l app=wordpress
                     Call to undefined function wp_is_serving_rest_request()
  WordPress version  /var/www/html/wp-includes/version.php → 6.4
  Active plugins     wp_options.active_plugins → wordpress-seo only
  Plugin location    /var/www/html/wp-content/plugins/wordpress-seo/

Why browser shows blank but curl shows content:
  PHP starts rendering HTML.
  Fatal error occurs mid-render.
  curl shows partial output up to the error point.
  Browser requires a complete valid response to render — shows blank instead.

Why it happened after reboot specifically:
  Before reboot: plugin active, possibly masked by OPcache.
  After reboot: fresh pod startup, plugin loaded clean, fatal error immediately.


# Suspected Root Cause
Yoast SEO plugin (latest version installed via WordPress UI) requires
wp_is_serving_rest_request() added in WordPress 6.5. WordPress image pinned
to 6.4 — function does not exist. PHP fatal error on every page load.


# More Checks Notes:
Confirmed wp-config.php database credentials injected correctly via Vault
environment variables. DB connection not the issue.


# Suspected Solution
Disable incompatible plugin via database. Restart pods to clear OPcache.
Permanently update WordPress image to 6.5+.


# Test
Disabled Yoast SEO via database UPDATE, restarted deployment.

Command:
  kubectl exec -it mariadb-0 -n database -- mysql -u root -p -e \
    "UPDATE wordpress.wp_options SET option_value = 'a:0:{}' WHERE option_name = 'active_plugins';"
  kubectl rollout restart deployment wordpress -n apps

Result: PASS — WordPress loads correctly in browser, admin dashboard accessible.

Why pod restart is required after database change:
  PHP OPcache still has compiled plugin code in memory.
  Apache processes still running with old code loaded.
  Database change alone is not enough — pods must restart to clear cache.

_____________________________________________________________________

[Final Root Cause]
Yoast SEO plugin (latest version) calls wp_is_serving_rest_request() which
was introduced in WordPress 6.5. WordPress image is pinned to 6.4 — function
does not exist. Every page load triggers a PHP fatal error mid-render. curl
sees partial HTML output, browser shows blank. Error was masked before reboot
(possibly OPcache). After reboot, fresh pod startup hit the error immediately.

_____________________________________________________________________

[Final Solution]

Immediate fix — disable plugin via database and restart pods:
  kubectl exec -it mariadb-0 -n database -- mysql -u root -p -e \
    "UPDATE wordpress.wp_options SET option_value = 'a:0:{}' WHERE option_name = 'active_plugins';"
  kubectl rollout restart deployment wordpress -n apps

Permanent fix — update WordPress image in deployment.yaml:
  image: wordpress:6.5-php8.2-apache   (or wordpress:latest)

Alternative disable without database (rename folder):
  kubectl exec -it <wordpress-pod> -n apps -c wordpress -- \
    mv /var/www/html/wp-content/plugins/wordpress-seo \
       /var/www/html/wp-content/plugins/wordpress-seo.disabled

Action items:
  [x] Disable incompatible plugin via database
  [ ] Update WordPress image to 6.5+ in deployment.yaml
  [ ] Pin plugin versions for stability
  [ ] Add WordPress version check to monitoring

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW (immediate fix) / MEDIUM (image update)
Note: Immediate fix — SEO functionality temporarily lost, easily reversible.
Image update — brief downtime during rollout, test other plugin compatibility.

_____________________________________________________________________

[References]
- https://developer.wordpress.org/reference/functions/wp_is_serving_rest_request/
- https://yoast.com/help/requirements-for-yoast-seo/

_____________________________________________________________________

[Draft Notes]

_____________________________________________________________________
TROUBLESHOOTING FLOW — WordPress blank page / browser issues
_____________________________________________________________________

Step 1 — curl vs browser:
  curl http://site → if curl works but browser blank → partial render / fatal error
  Both fail → server-side issue before any HTML rendered

Step 2 — Check pod status:
  kubectl get pods -n apps
  kubectl get pods -n database
  All Running? Correct READY count?

Step 3 — Check database:
  kubectl exec -it mariadb-0 -n database -- mysqladmin ping -u root -p
  DB alive and reachable?

Step 4 — Check application logs ← THIS USUALLY REVEALS ROOT CAUSE:
  kubectl logs -n apps -l app=wordpress --tail=100
  grep for: error, fatal, exception, undefined function

Step 5 — Check configuration:
  wp-config.php, environment variables, Vault secret injection

Step 6 — Check database state:
  Active plugins, user accounts, site URL settings in wp_options

Step 7 — Apply fix and verify:
  Disable plugins via DB, update image version, clear browser cache,
  restart pods after any database change (OPcache)


_____________________________________________________________________
COMMANDS REFERENCE
_____________________________________________________________________

Pod status:
  kubectl get pods -n apps
  kubectl get pods -n database
  kubectl describe pod <pod-name> -n <namespace>

Application logs:
  kubectl logs -n apps -l app=wordpress --tail=100    all pods
  kubectl logs -n apps wordpress-xxxx -c wordpress --tail=100   specific pod
  kubectl logs -n apps -l app=wordpress -f            follow

Database checks:
  kubectl exec -it mariadb-0 -n database -- mysqladmin ping -u root -p
  kubectl exec -it mariadb-0 -n database -- mysql -u root -p
  kubectl exec -it mariadb-0 -n database -- mysql -u root -p -e \
    "SELECT option_value FROM wordpress.wp_options WHERE option_name='active_plugins';"

WordPress inspection:
  kubectl exec -it <pod> -n apps -c wordpress -- cat /var/www/html/wp-config.php
  kubectl exec -it <pod> -n apps -c wordpress -- \
    grep "wp_version" /var/www/html/wp-includes/version.php
  kubectl exec -it <pod> -n apps -c wordpress -- \
    ls /var/www/html/wp-content/plugins/

Disable plugins via database:
  kubectl exec -it mariadb-0 -n database -- mysql -u root -p -e \
    "UPDATE wordpress.wp_options SET option_value = 'a:0:{}' WHERE option_name = 'active_plugins';"
  kubectl rollout restart deployment wordpress -n apps   ← always restart after DB change

Disable plugin by renaming folder (no DB required):
  kubectl exec -it <pod> -n apps -c wordpress -- \
    mv /var/www/html/wp-content/plugins/wordpress-seo \
       /var/www/html/wp-content/plugins/wordpress-seo.disabled

Notes:
  1. Check application logs first — they contain the exact error
  2. curl vs browser blank = partial render / PHP fatal error
  3. Plugin updates can silently break older WordPress versions
  4. wp_options is shared state — database change affects all pods immediately
  5. Pod restart required after database change to clear PHP OPcache
  6. Pin plugin versions or use WP-CLI for controlled updates