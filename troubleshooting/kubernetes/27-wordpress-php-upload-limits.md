# TS-K8S-027 | 2026-04-13 | RESOLVED

## 1. Context
- System: WordPress / PHP / Kubernetes
- Environment: k8s-dev cluster
- Related components: WordPress deployment, PHP configuration, NFS storage
- Discovered during: DR testing preparation (large file upload test)
- Related Cases:
  - TS-K8S-003 — NFS mount options (storage backend for uploads)

---

## 2. Issue

**Symptom:** WordPress file uploads failing with multiple errors.

**Error 1 — Large image processing failure:**
```
video-frame-0.00s.jpg
The server cannot process the image. This can happen if the server is busy or does not have enough resources to complete the task. Uploading a smaller image may help. Suggested maximum size is 2560 pixels.
```

**Error 2 — File type blocked:**
```
backup-ER605_UN_v2.20-2026-03-14 (1).bin
This file cannot be processed by the web server.

backup-after-acl-api-rules.backup
This file cannot be processed by the web server.

1860_rev43.json
This file cannot be processed by the web server.
```

**Error 3 — Upload size limit:**
```
Maximum upload file size: 2 MB.
```

**Impact:** Cannot upload large media files or perform DR tests requiring mid-upload failure simulation.

---

## 3. Analysis

### Step 1: Check PHP Limits

```bash
kubectl exec -it $(kubectl get pod -n apps -l app=wordpress -o jsonpath='{.items[0].metadata.name}') -n apps -- \
  php -i | grep -E "upload_max|post_max|memory_limit"
```

**Output:**
```
memory_limit => 128M => 128M
post_max_size => 8M => 8M
upload_max_filesize => 2M => 2M
```

**Finding:** PHP default limits are too restrictive.

### Step 2: Check WordPress Deployment for PHP Config

```bash
kubectl describe deploy wordpress -n apps | grep -i configmap
kubectl get cm -n apps | grep php
```

**Finding:** No custom PHP configuration existed.

### Step 3: Understanding WordPress File Type Restrictions

WordPress uses a MIME type whitelist for security. Files like `.bin`, `.backup`, `.json` are not in the default allowed list.

| File Type | Default Allowed | Reason |
|-----------|-----------------|--------|
| `.jpg`, `.png`, `.gif` | YES | Images |
| `.mp4`, `.mov`, `.webm` | YES | Videos |
| `.pdf`, `.doc` | YES | Documents |
| `.bin` | NO | Binary executable — security risk |
| `.backup` | NO | Not in whitelist |
| `.json` | NO | Not in default whitelist |

---

## 4. Root Cause

| Issue | Cause |
|-------|-------|
| 2MB upload limit | PHP default `upload_max_filesize = 2M` |
| Image processing failure | PHP default `memory_limit = 128M` too low for large images |
| File type blocked | WordPress MIME type whitelist — security feature |

No custom PHP configuration was deployed with WordPress.

---

## 5. Solution

### Created PHP ConfigMap

**File:** `kubernetes/dev/deployments/apps/wordpress/php-config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: wordpress-php-config
  namespace: apps
data:
  uploads.ini: |
    ; PHP Upload Settings for WordPress
    upload_max_filesize = 100M
    post_max_size = 100M
    memory_limit = 256M
    max_execution_time = 300
    max_input_time = 300
```

### Updated Deployment to Mount ConfigMap

**File:** `kubernetes/dev/deployments/apps/wordpress/deployment.yaml`

```yaml
volumeMounts:
  - name: wordpress-data
    mountPath: /var/www/html/wp-content
  - name: php-config
    mountPath: /usr/local/etc/php/conf.d/uploads.ini
    subPath: uploads.ini

volumes:
  - name: wordpress-data
    persistentVolumeClaim:
      claimName: wordpress-data
  - name: php-config
    configMap:
      name: wordpress-php-config
```

### Updated Kustomization

**File:** `kubernetes/dev/deployments/apps/wordpress/kustomization.yaml`

Added `php-config.yaml` to resources list.

### Applied to Both Environments

Same changes applied to:
- `kubernetes/dev/deployments/apps/wordpress/`
- `kubernetes/prod/deployments/apps/wordpress/`

### Deploy Changes

```bash
git add -A && git commit -m "Add PHP upload config for WordPress" && git push
flux reconcile kustomization apps --with-source
```

### Verify New Limits

```bash
kubectl exec -it $(kubectl get pod -n apps -l app=wordpress -o jsonpath='{.items[0].metadata.name}') -n apps -- \
  php -i | grep -E "upload_max|post_max|memory_limit"
```

**Expected output:**
```
memory_limit => 256M => 256M
post_max_size => 100M => 100M
upload_max_filesize => 100M => 100M
```

---

## 6. Solution Risk
- Risk level: LOW
- Pod restart required for new config to take effect
- Larger upload limits increase potential for storage abuse (acceptable in controlled environment)

---

## 7. Impact After Fix
- Upload limit increased from 2MB to 100MB
- Large image processing now works (256MB memory limit)
- Can perform DR mid-upload tests with large files

---

## 8. Notes

### Key Rules

| Rule | Detail |
|------|--------|
| PHP defaults are restrictive | Always configure upload limits explicitly |
| ConfigMap + volumeMount for PHP config | Don't rely on image defaults |
| WordPress blocks unknown file types | Security feature — don't disable unless necessary |
| Use allowed file types for testing | `.jpg`, `.mp4`, `.pdf` — not `.bin`, `.backup` |

### File Types for DR Upload Testing

Use these for mid-upload kill tests (WordPress allows by default):
- Large `.jpg` / `.png` images (50-100MB)
- Video files `.mp4` / `.webm` (50-100MB)
- PDF documents

### If You Need to Upload Blocked File Types

**Option A: Add MIME types (wp-config.php or functions.php):**
```php
add_filter('upload_mimes', function($mimes) {
    $mimes['json'] = 'application/json';
    return $mimes;
});
```

**Option B: Upload directly to NFS (bypass WordPress):**
```bash
kubectl cp myfile.json wordpress-pod:/var/www/html/wp-content/uploads/
```

### Commands Reference

```bash
# Check PHP limits
kubectl exec -it <wordpress-pod> -n apps -- php -i | grep -E "upload_max|post_max|memory_limit"

# Check mounted PHP config
kubectl exec -it <wordpress-pod> -n apps -- cat /usr/local/etc/php/conf.d/uploads.ini

# Reload PHP (Apache)
kubectl exec -it <wordpress-pod> -n apps -- apachectl graceful
```

---

## 9. Workaround

**Quick temporary fix (non-persistent, lost on pod restart):**

```bash
kubectl exec -it <wordpress-pod> -n apps -- bash -c '
  echo "upload_max_filesize = 100M" > /usr/local/etc/php/conf.d/uploads.ini
  echo "post_max_size = 100M" >> /usr/local/etc/php/conf.d/uploads.ini
  echo "memory_limit = 256M" >> /usr/local/etc/php/conf.d/uploads.ini
  apachectl graceful
'
```

Use the ConfigMap solution for permanent fix.
