# TS-K8S-028 | 2026-04-13 | RESOLVED

## 1. Context
- System: External Nginx Proxy / Kubernetes Ingress / WordPress
- Environment: k8s-dev cluster + external nginx reverse proxy
- Related components: External nginx, nginx-ingress controller, WordPress
- Discovered during: DR testing preparation (large file upload test)
- Related Cases:
  - TS-K8S-027 — WordPress PHP upload limits (fixed before this issue)

---

## 2. Issue

**Symptom:** After fixing PHP upload limits (TS-K8S-027), large file uploads still failing.

**Error in browser console:**
```
Failed to load resource: the server responded with a status of 413 (Request Entity Too Large)
POST http://wordpress-dev.lab.local/wp-admin/async-upload.php 413 (Request Entity Too Large)
```

**Browser Network tab evidence:**
| Request | Status | Type | Time |
|---------|--------|------|------|
| async-upload.php | 413 | xhr | 2.40s |

**Error message in WordPress:**
```
Unexpected response from the server. The file may have been uploaded successfully.
Check in the Media Library or reload the page.
```

**Test files:**
- 20MB PDF - FAILED (413)
- 16MB video - FAILED (413)
- Small image - SUCCESS (200)

**Impact:** Cannot upload files larger than 1MB despite PHP limits being increased to 100MB.

---

## 3. Analysis

### Step 1: Verify PHP limits are correct (TS-K8S-027 fix applied)

```bash
kubectl exec -it $(kubectl get pod -n apps -l app=wordpress -o jsonpath='{.items[0].metadata.name}') -n apps -- \
  php -i | grep -E "upload_max|post_max|memory_limit"
```

**Output:**
```
memory_limit => 256M => 256M
post_max_size => 100M => 100M
upload_max_filesize => 100M => 100M
```

**Finding:** PHP limits are correctly set to 100MB. Issue is NOT PHP.

---

### Step 2: Check WordPress pod logs during upload

```bash
kubectl logs -f $(kubectl get pod -n apps -l app=wordpress -o jsonpath='{.items[0].metadata.name}') -n apps
```

**Finding:** No logs appeared for failed uploads. Request never reached WordPress pod.

---

### Step 3: Check nginx-ingress controller logs

```bash
kubectl get pods -n ingress-nginx
kubectl logs -f -n ingress-nginx <ingress-controller-pod>
```

**Finding:** No logs for failed uploads. Request never reached ingress controller.

**Conclusion:** Something is blocking the request BEFORE it reaches Kubernetes.

---

### Step 4: Check ingress annotation for WordPress

```bash
kubectl get ingress ingress-wordpress -n apps -o yaml | grep -A5 annotations
```

**Output:**
```yaml
annotations:
  nginx.ingress.kubernetes.io/affinity: cookie
  nginx.ingress.kubernetes.io/proxy-body-size: 500m
  nginx.ingress.kubernetes.io/session-cookie-expires: "172800"
  nginx.ingress.kubernetes.io/session-cookie-max-age: "172800"
  nginx.ingress.kubernetes.io/session-cookie-name: wordpress-sticky
```

**Finding:** Ingress annotation `proxy-body-size: 500m` is set correctly.

---

### Step 5: Check ingress-nginx controller ConfigMap

```bash
kubectl get configmap -n ingress-nginx
```

**Output:**
```
NAME                       DATA   AGE
ingress-nginx-controller   0      4d2h
kube-root-ca.crt           1      9d
```

```bash
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o yaml | grep -i body-size
```

**Output:** (empty - no global body-size config)

**Finding:** No global ConfigMap override. Ingress should use annotation value.

---

### Step 6: Check Helm release values for ingress-nginx

```bash
helm get values ingress-nginx -n ingress-nginx
```

**Output:**
```yaml
USER-SUPPLIED VALUES:
controller:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
          topologyKey: kubernetes.io/hostname
        weight: 100
  ingressClassResource:
    default: true
    name: nginx
  priorityClassName: system-cluster-critical
  replicaCount: 3
  service:
    nodePorts:
      http: 30080
      https: 30443
    type: NodePort
```

**Finding:** No `controller.config.proxy-body-size` set. Uses default.

---

### Step 7: Check actual nginx.conf inside ingress controller

```bash
kubectl exec -it $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}') -n ingress-nginx -- \
  cat /etc/nginx/nginx.conf | grep -i client_max_body
```

**Output:**
```
client_max_body_size                    1m;
client_max_body_size                    1m;
client_max_body_size                    500m;
client_max_body_size                    21M;
```

**Finding:** Multiple values exist. Need to see which server block each belongs to.

---

### Step 8: Inspect full nginx.conf for server block context

```bash
kubectl exec -it $(kubectl get pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}') -n ingress-nginx -- \
  cat /etc/nginx/nginx.conf
```

**Key findings from full config:**

**Default server block (`_`):**
```nginx
## start server _
server {
    server_name "_" ;
    listen 80 default_server reuseport backlog=4096 ;
    ...
    location "/" {
        client_max_body_size                    1m;   ← DEFAULT
        ...
    }
}
```

**Grafana server block:**
```nginx
## start server grafana-dev.lab.local
server {
    server_name "grafana-dev.lab.local" ;
    ...
    location "/" {
        client_max_body_size                    1m;   ← DEFAULT (no annotation)
        ...
    }
}
```

**WordPress server block:**
```nginx
## start server wordpress-dev.lab.local
server {
    server_name "wordpress-dev.lab.local" ;
    ...
    location "/" {
        client_max_body_size                    500m;  ← ANNOTATION WORKING!
        ...
    }
}
```

**Internal configuration endpoint:**
```nginx
location /configuration {
    client_max_body_size                    21M;   ← Internal use
    ...
}
```

**Conclusion:** The Kubernetes ingress nginx.conf is CORRECT. WordPress server block has 500m.
The 413 error must be coming from somewhere BEFORE the Kubernetes ingress.

---

### Step 9: Identify the external proxy

**Architecture review:**
```
Browser → External Nginx (ex-nginx.lab.local) → K8s NodePort (30080) → Ingress Controller → WordPress
```

**The user confirmed:** There is an external nginx reverse proxy in front of the Kubernetes cluster.

---

### Step 10: Check external nginx configuration

**File:** `ansible/dev/playbooks/nginx/templates/nginx-test.conf.j2`

```nginx
upstream k8s_workers {
    least_conn;
    server 10.0.64.10:30080;
    server 10.0.64.11:30080;
    server 10.0.64.12:30080;
}

server {
    listen 80;
    server_name *.lab.local;

    access_log /var/log/nginx/nginx-test-dev.log upstream;

    location / {
        proxy_pass http://k8s_workers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Finding:** No `client_max_body_size` directive. Nginx default is `1m`.

---

## 4. Root Cause

| Layer | Config | Limit | Status |
|-------|--------|-------|--------|
| WordPress PHP | `upload_max_filesize` | 100M | OK (TS-K8S-027) |
| K8s Ingress annotation | `proxy-body-size` | 500m | OK |
| K8s Ingress nginx.conf | `client_max_body_size` | 500m | OK |
| **External Nginx** | `client_max_body_size` | **1m (default)** | **PROBLEM** |

**Root cause:** External nginx reverse proxy (`ex-nginx.lab.local`) had no `client_max_body_size` configured, defaulting to 1MB. Requests larger than 1MB were rejected with 413 before reaching Kubernetes.

**Request flow with 413:**
```
Browser (20MB upload)
    ↓
External Nginx (1MB limit) → 413 REJECTED HERE
    ✗ Never reaches K8s
```

---

## 5. Solution

### Updated external nginx config

**File:** `ansible/dev/playbooks/nginx/templates/k8s-ingress.conf.j2` (renamed from nginx-test.conf.j2)

```nginx
upstream k8s_workers {
    least_conn;
    server 10.0.64.10:30080;
    server 10.0.64.11:30080;
    server 10.0.64.12:30080;
}

server {
    listen 80;
    server_name *.lab.local;

    access_log /var/log/nginx/nginx-test-dev.log upstream;

    # Allow large file uploads (WordPress media, etc.)
    client_max_body_size 500m;

    location / {
        proxy_pass http://k8s_workers;

        # Timeouts for large uploads
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Changes made

| Change | Detail |
|--------|--------|
| `client_max_body_size 500m` | Allow uploads up to 500MB |
| `proxy_read_timeout 300s` | Wait 5 minutes for backend response |
| `proxy_send_timeout 300s` | Wait 5 minutes to send data to backend |
| File renamed | `nginx-test.conf.j2` → `k8s-ingress.conf.j2` |

### Files updated

**Dev environment:**
- `ansible/dev/playbooks/nginx/templates/k8s-ingress.conf.j2`
- `ansible/dev/playbooks/nginx/apply_new_config.yml`

**Prod environment:**
- `ansible/prod/playbooks/nginx/templates/k8s-ingress.conf.j2`
- `ansible/prod/playbooks/nginx/apply_new_config.yml`

### Deploy changes

```bash
# Run ansible playbook to deploy new config
cd ansible/dev/playbooks/nginx
ansible-playbook apply_new_config.yml

# Or manually on the nginx server
ssh ex-nginx.lab.local
sudo vi /etc/nginx/conf.d/k8s-ingress.conf
sudo nginx -t
sudo nginx -s reload

# Remove old config file
sudo rm /etc/nginx/conf.d/nginx-test.conf
```

---

## 6. Solution Risk

- Risk level: LOW
- Change is additive (increasing limits, not decreasing)
- Only affects `*.lab.local` traffic through this proxy
- Larger body size allows potential abuse (acceptable in controlled lab environment)
- Timeout increases may hold connections longer under load

---

## 7. Impact After Fix

| Test | Before | After |
|------|--------|-------|
| Small image upload | 200 OK | 200 OK |
| 20MB PDF upload | 413 Error | 200 OK |
| 16MB video upload | 413 Error | 200 OK |
| Large file mid-upload kill test | Blocked | Now possible |

**Request flow after fix:**
```
Browser (20MB upload)
    ↓
External Nginx (500MB limit) → PASS
    ↓
K8s Ingress (500MB limit) → PASS
    ↓
WordPress PHP (100MB limit) → PASS
    ↓
Upload successful!
```

---

## 8. Notes

### Key learnings

| Learning | Detail |
|----------|--------|
| 413 can come from any proxy layer | Check ALL proxies in the request path |
| Logs don't show if rejected upstream | If no logs in K8s, check what's in front |
| nginx default body size is 1m | Always set `client_max_body_size` explicitly for upload-heavy apps |
| Browser Network tab shows the truth | Status code tells you exactly what's happening |
| Multiple nginx layers = multiple configs | Each layer needs its own body size config |

### Full request path and limits

```
Browser
    ↓
External Nginx (ex-nginx.lab.local)
    - client_max_body_size: 500m ← FIXED
    - proxy_read_timeout: 300s ← ADDED
    - proxy_send_timeout: 300s ← ADDED
    ↓
K8s NodePort (30080)
    ↓
Ingress Controller (ingress-nginx)
    - client_max_body_size: 500m (per-ingress annotation)
    - proxy_read_timeout: 60s (default)
    - proxy_send_timeout: 60s (default)
    ↓
WordPress Pod
    - upload_max_filesize: 100m (PHP)
    - post_max_size: 100m (PHP)
    - memory_limit: 256m (PHP)
    ↓
NFS Storage
    - Receives uploaded file
```

### Debugging commands reference

```bash
# Check PHP limits inside WordPress pod
kubectl exec -it <wordpress-pod> -n apps -- php -i | grep -E "upload_max|post_max|memory_limit"

# Check ingress annotation
kubectl get ingress ingress-wordpress -n apps -o yaml | grep -A5 annotations

# Check ingress-nginx configmap
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o yaml

# Check helm values for ingress-nginx
helm get values ingress-nginx -n ingress-nginx

# Check nginx.conf inside ingress controller
kubectl exec -it <ingress-pod> -n ingress-nginx -- cat /etc/nginx/nginx.conf | grep client_max_body

# Check full nginx.conf (find your server block)
kubectl exec -it <ingress-pod> -n ingress-nginx -- cat /etc/nginx/nginx.conf | grep -A30 "wordpress"

# Watch pod logs during upload
kubectl logs -f <pod> -n <namespace>

# Check external nginx config
cat /etc/nginx/conf.d/k8s-ingress.conf
nginx -t
nginx -s reload
```

### Related files

| File | Purpose |
|------|---------|
| `ansible/dev/playbooks/nginx/templates/k8s-ingress.conf.j2` | External nginx proxy config |
| `ansible/dev/playbooks/nginx/apply_new_config.yml` | Ansible playbook to deploy config |
| `kubernetes/dev/deployments/apps/wordpress/service.yaml` | Ingress with proxy-body-size annotation |
| `kubernetes/dev/deployments/infrastructure/ingress/helm-release.yaml` | Ingress controller Helm values |

---

## 9. Workaround

**Temporary fix on nginx server (non-persistent):**

```bash
ssh ex-nginx.lab.local
sudo bash -c 'echo "client_max_body_size 500m;" >> /etc/nginx/conf.d/k8s-ingress.conf'
sudo nginx -t && sudo nginx -s reload
```

**Note:** This is lost on config redeployment. Use the ansible template fix for permanent solution.

---

## 10. Timeline

| Time | Action |
|------|--------|
| Initial | PHP limits fixed (TS-K8S-027), expected uploads to work |
| +5 min | Tested 20MB upload, got 413 error |
| +10 min | Checked PHP limits - confirmed 100MB |
| +15 min | Checked WordPress pod logs - no logs for failed upload |
| +20 min | Checked ingress controller logs - no logs |
| +25 min | Checked ingress annotation - 500m set correctly |
| +30 min | Checked nginx.conf inside controller - WordPress block has 500m |
| +35 min | Realized request never reaches K8s - must be external proxy |
| +40 min | Confirmed external nginx exists, checked config |
| +45 min | Found missing `client_max_body_size` in external nginx |
| +50 min | Applied fix, tested upload - SUCCESS |
