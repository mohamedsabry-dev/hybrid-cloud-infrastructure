# TS-K8S-027 | 2026-04-13 | RESOLVED
_____________________________________________________________________

[Info]
Author:
Domain: Kubernetes / WordPress
Sub-techs: PHP configuration, WordPress upload limits, ConfigMap, volumeMount,
           MIME type whitelist, NFS storage
Environment: DEV + PROD k8s clusters | apps namespace
Re-opened: No

_____________________________________________________________________

[Issue Description]
WordPress file uploads failing with multiple errors. Discovered during DR testing
preparation (large file upload test).

  Error 1 — Large image processing failure:
  "The server cannot process the image. Uploading a smaller image may help.
  Suggested maximum size is 2560 pixels."

  Error 2 — File type blocked:
  "This file cannot be processed by the web server."
  (affected: .bin, .backup, .json files)

  Error 3 — Upload size limit:
  "Maximum upload file size: 2 MB."

Related tickets:
  TS-K8S-003 — NFS mount options (storage backend for uploads)
  TS-K8S-028 — External nginx proxy 413 error (discovered after fixing PHP limits)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked PHP limits inside the WordPress pod:

Command:
  kubectl exec -it <wordpress-pod> -n apps -- \
    php -i | grep -E "upload_max|post_max|memory_limit"

Output:
  memory_limit       128M
  post_max_size       8M
  upload_max_filesize 2M

PHP defaults are too restrictive — no custom PHP configuration was deployed.

Checked if any PHP ConfigMap existed:
  kubectl describe deploy wordpress -n apps | grep -i configmap
  kubectl get cm -n apps | grep php
  → No custom PHP configuration found.

Checked WordPress file type whitelist behaviour:
  .jpg .png .gif .mp4 .pdf .doc  → allowed by default (images, video, documents)
  .bin                            → blocked (binary executable — security risk)
  .backup                         → blocked (not in whitelist)
  .json                           → blocked (not in default whitelist)
  WordPress MIME type whitelist is a security feature — not a bug.

Root cause summary:
  2MB upload limit           → PHP default upload_max_filesize = 2M
  Image processing failure   → PHP default memory_limit = 128M too low for large images
  File type blocked          → WordPress MIME whitelist — expected security behaviour


# Suspected Root Cause
No custom PHP configuration deployed with WordPress. PHP defaults are too
restrictive for large file uploads. File type errors are a separate issue
(WordPress security whitelist) — not a PHP config problem.


# More Checks Notes:
N/A — PHP config check confirmed the issue. Whitelist behaviour is by design.


# Suspected Solution
Create PHP ConfigMap with increased limits and mount it into WordPress pod.
Separate issue for blocked file types — use allowed file types (.jpg, .mp4, .pdf)
for DR testing instead of .bin or .backup.


# Test
Applied ConfigMap, reconciled Flux, restarted pods, verified new limits.

Command:
  kubectl exec -it <wordpress-pod> -n apps -- \
    php -i | grep -E "upload_max|post_max|memory_limit"

Result: PASS
  memory_limit        256M
  post_max_size       100M
  upload_max_filesize 100M
  Large image processing and file uploads working.

_____________________________________________________________________

[Final Root Cause]
No custom PHP configuration deployed with WordPress. PHP defaults (2MB upload,
128MB memory) were too restrictive for large file uploads and image processing.
File type errors (.bin, .backup, .json) are a separate WordPress MIME whitelist
security feature — not a configuration problem.

_____________________________________________________________________

[Final Solution]
Created PHP ConfigMap and mounted it into WordPress deployment in both DEV and PROD.

  File: kubernetes/dev|prod/deployments/apps/wordpress/php-config.yaml

  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: wordpress-php-config
    namespace: apps
  data:
    uploads.ini: |
      upload_max_filesize = 100M
      post_max_size = 100M
      memory_limit = 256M
      max_execution_time = 300
      max_input_time = 300

  Deployment volumeMount:
    - name: php-config
      mountPath: /usr/local/etc/php/conf.d/uploads.ini
      subPath: uploads.ini

  Volume:
    - name: php-config
      configMap:
        name: wordpress-php-config

  Added php-config.yaml to kustomization.yaml resources in both environments.

  Deploy:
    git add -A && git commit -m "Add PHP upload config for WordPress" && git push
    flux reconcile kustomization apps --with-source

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Pod restart required for new config to take effect. Larger upload limits
increase potential for storage abuse — acceptable in controlled environment.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

File types for DR upload testing (WordPress allows by default):
  Large .jpg / .png images  (50-100MB)
  Video files .mp4 / .webm  (50-100MB)
  PDF documents
  Do NOT use .bin, .backup, .json — blocked by WordPress whitelist by design.

If blocked file types must be uploaded:
  Option A: add MIME type via functions.php
    add_filter('upload_mimes', function($mimes) {
      $mimes['json'] = 'application/json';
      return $mimes;
    });

  Option B: copy directly to NFS bypassing WordPress
    kubectl cp myfile.json wordpress-pod:/var/www/html/wp-content/uploads/

Quick temporary fix (non-persistent, lost on pod restart):
  kubectl exec -it <wordpress-pod> -n apps -- bash -c '
    echo "upload_max_filesize = 100M" > /usr/local/etc/php/conf.d/uploads.ini
    echo "post_max_size = 100M" >> /usr/local/etc/php/conf.d/uploads.ini
    echo "memory_limit = 256M" >> /usr/local/etc/php/conf.d/uploads.ini
    apachectl graceful
  '

Commands reference:
  kubectl exec -it <pod> -n apps -- php -i | grep -E "upload_max|post_max|memory_limit"
  kubectl exec -it <pod> -n apps -- cat /usr/local/etc/php/conf.d/uploads.ini
  kubectl exec -it <pod> -n apps -- apachectl graceful