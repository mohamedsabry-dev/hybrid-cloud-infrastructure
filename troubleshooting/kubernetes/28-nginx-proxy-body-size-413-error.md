# TS-K8S-028 | 2026-04-13 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Nginx
Sub-techs: External nginx proxy, nginx-ingress, client_max_body_size, 413,
           WordPress upload, proxy_read_timeout, Ansible nginx template
Environment: DEV + PROD k8s clusters | external nginx ex-nginx.lab.local
Re-opened: No

_____________________________________________________________________

[Issue Description]
After fixing PHP upload limits (TS-K8S-027), large file uploads still failing
with 413 Request Entity Too Large. PHP was correctly set to 100MB — 413 coming
from a different layer.

  Browser console:
  POST http://wordpress-dev.lab.local/wp-admin/async-upload.php 413 (Request Entity Too Large)

  Test results:
  20MB PDF   → 413 FAILED
  16MB video → 413 FAILED
  Small image→ 200 OK

  WordPress message: "Unexpected response from the server. The file may have
  been uploaded successfully. Check in the Media Library or reload the page."

Related ticket: TS-K8S-027 — WordPress PHP upload limits (fixed before this)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

Step 1 — Verify PHP limits are correctly set (TS-K8S-027 fix applied):
  Command:
    kubectl exec -it <wordpress-pod> -n apps -- \
      php -i | grep -E "upload_max|post_max|memory_limit"
  Output:
    memory_limit        256M
    post_max_size       100M
    upload_max_filesize 100M
  PHP limits correct. Issue is NOT PHP.

Step 2 — Check WordPress pod logs during upload:
  kubectl logs -f <wordpress-pod> -n apps
  → No logs appeared for failed uploads.
  Request never reached the WordPress pod.

Step 3 — Check nginx-ingress controller logs:
  kubectl logs -f -n ingress-nginx <ingress-controller-pod>
  → No logs for failed uploads.
  Request never reached the ingress controller either.
  Conclusion: something is blocking BEFORE Kubernetes.

Step 4 — Check ingress annotation:
  kubectl get ingress ingress-wordpress -n apps -o yaml | grep -A5 annotations
  Output:
    nginx.ingress.kubernetes.io/proxy-body-size: 500m   ← correctly set
    nginx.ingress.kubernetes.io/affinity: cookie
    nginx.ingress.kubernetes.io/session-cookie-name: wordpress-sticky

Step 5 — Check nginx.conf inside ingress controller:
  kubectl exec -it <ingress-pod> -n ingress-nginx -- \
    cat /etc/nginx/nginx.conf | grep -i client_max_body
  Output:
    client_max_body_size  1m;     ← default server block
    client_max_body_size  1m;     ← grafana block (no annotation)
    client_max_body_size  500m;   ← wordpress-dev.lab.local block ← CORRECT
    client_max_body_size  21M;    ← internal /configuration endpoint

  WordPress server block confirmed at 500m — ingress is NOT the problem.

Step 6 — Architecture review:
  Browser → External Nginx (ex-nginx.lab.local) → K8s NodePort (30080) → Ingress → WordPress

  There is an external nginx reverse proxy in front of Kubernetes.
  The request was being rejected before reaching Kubernetes at all.

Step 7 — Check external nginx configuration:
  File: ansible/dev/playbooks/nginx/templates/nginx-test.conf.j2

  upstream k8s_workers {
    least_conn;
    server 10.0.64.10:30080;
    server 10.0.64.11:30080;
    server 10.0.64.12:30080;
  }
  server {
    listen 80;
    server_name *.lab.local;
    location / {
      proxy_pass http://k8s_workers;
      proxy_set_header Host $host;
      ...
    }
  }

  No client_max_body_size directive. Nginx default is 1m.
  This was rejecting all uploads larger than 1MB with 413.


# Suspected Root Cause
External nginx reverse proxy (ex-nginx.lab.local) had no client_max_body_size
configured — nginx default is 1MB. Requests larger than 1MB were rejected with
413 before reaching Kubernetes. PHP was fine. Ingress was fine. The block was
at the first hop.


# More Checks Notes:
Verified by checking Helm values for ingress-nginx:
  helm get values ingress-nginx -n ingress-nginx
  → No controller.config.proxy-body-size set. ingress-nginx not the problem.

Checked ingress-nginx ConfigMap:
  kubectl get configmap ingress-nginx-controller -n ingress-nginx -o yaml | grep -i body-size
  → Empty. No global override. Confirmed ingress uses annotation value (500m).


# Suspected Solution
Add client_max_body_size 500m and upload timeouts to external nginx config.


# Test
Applied fix to external nginx, reloaded, tested uploads.

  Test results after fix:
  Small image   → 200 OK (unchanged)
  20MB PDF      → 200 OK (was 413)
  16MB video    → 200 OK (was 413)

Result: PASS — all upload tests passing. DR mid-upload kill test now possible.

_____________________________________________________________________

[Final Root Cause]
External nginx reverse proxy (ex-nginx.lab.local) had no client_max_body_size
configured. Nginx default is 1MB. All uploads larger than 1MB were rejected with
413 at the external proxy before the request ever reached Kubernetes. PHP limits
(TS-K8S-027) and Kubernetes ingress annotation (500m) were both correctly set —
only the external proxy was missing the config.

Full request path and where the block was:
  Browser (20MB)
    → External Nginx (1MB default) ← 413 REJECTED HERE
    ✗ Never reached K8s NodePort (30080)
    ✗ Never reached Ingress Controller
    ✗ Never reached WordPress pod

_____________________________________________________________________

[Final Solution]
Added client_max_body_size and upload timeouts to external nginx config.

  File renamed: nginx-test.conf.j2 → k8s-ingress.conf.j2

  Updated config:
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

      client_max_body_size 500m;    ← ADDED

      location / {
        proxy_pass http://k8s_workers;
        proxy_read_timeout 300s;    ← ADDED (5 min for large uploads)
        proxy_send_timeout 300s;    ← ADDED
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      }
    }

  Changes summary:
    client_max_body_size 500m   allow uploads up to 500MB
    proxy_read_timeout 300s     wait 5 minutes for backend response
    proxy_send_timeout 300s     wait 5 minutes to send data to backend
    file renamed                nginx-test.conf.j2 → k8s-ingress.conf.j2

  Deploy:
    cd ansible/dev/playbooks/nginx
    ansible-playbook apply_new_config.yml

  Or manually on nginx server:
    sudo vi /etc/nginx/conf.d/k8s-ingress.conf
    sudo nginx -t && sudo nginx -s reload
    sudo rm /etc/nginx/conf.d/nginx-test.conf

  Applied to both dev and prod nginx templates.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Additive change — increasing limits. Only affects *.lab.local traffic.
Larger body size allows potential storage abuse — acceptable in controlled lab.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Full request path and limits (after fix):
  External Nginx (ex-nginx.lab.local)
    client_max_body_size: 500m   proxy_read_timeout: 300s   proxy_send_timeout: 300s
    ↓
  K8s NodePort (30080)
    ↓
  Ingress Controller (ingress-nginx)
    client_max_body_size: 500m (per-ingress annotation)
    ↓
  WordPress Pod
    upload_max_filesize: 100M   post_max_size: 100M   memory_limit: 256M
    ↓
  NFS Storage

Investigation timeline:
  +0 min   PHP limits fixed (TS-K8S-027), expected uploads to work
  +5 min   Tested 20MB upload — 413 error
  +10 min  Checked PHP limits — confirmed 100MB, not the cause
  +15 min  Checked WordPress pod logs — no logs for failed upload
  +20 min  Checked ingress controller logs — no logs, never reached K8s
  +25 min  Checked ingress annotation — 500m set correctly
  +30 min  Checked nginx.conf inside controller — WordPress block has 500m
  +35 min  Realised request never reaches K8s — must be external proxy
  +40 min  Confirmed external nginx exists, checked config
  +45 min  Found missing client_max_body_size in external nginx
  +50 min  Applied fix, tested upload — SUCCESS

Key lessons:
  1. 413 can come from any proxy layer — check ALL proxies in the request path
  2. If no logs in K8s during a request, the block is upstream of Kubernetes
  3. Nginx default body size is 1m — always set client_max_body_size explicitly
     for any upload-heavy application
  4. Browser Network tab (F12) shows the exact status code and which URL rejected
  5. Multiple nginx layers = multiple configs — each layer needs its own body size

Commands reference:
  # PHP limits
  kubectl exec -it <wordpress-pod> -n apps -- \
    php -i | grep -E "upload_max|post_max|memory_limit"

  # Ingress annotation
  kubectl get ingress ingress-wordpress -n apps -o yaml | grep -A5 annotations

  # nginx.conf inside ingress controller (check client_max_body_size per server block)
  kubectl exec -it <ingress-pod> -n ingress-nginx -- \
    cat /etc/nginx/nginx.conf | grep -A30 "wordpress-dev.lab.local"

  # Watch pod logs during upload
  kubectl logs -f <pod> -n <namespace>

  # External nginx
  cat /etc/nginx/conf.d/k8s-ingress.conf
  nginx -t && nginx -s reload

Related files:
  ansible/dev/playbooks/nginx/templates/k8s-ingress.conf.j2
  ansible/dev/playbooks/nginx/apply_new_config.yml
  kubernetes/dev/deployments/apps/wordpress/service.yaml   (ingress proxy-body-size annotation)
  kubernetes/dev/deployments/infrastructure/ingress/helm-release.yaml