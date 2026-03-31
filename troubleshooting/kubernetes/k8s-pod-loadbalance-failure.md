Troubleshooting case — NFS hard mount causing intermittent pod unresponsiveness
Environment: bare-metal kubeadm cluster · 3 workers · Calico CNI · NFS backend storage · Vault agent sidecar injection · Date: 31 March 2026
1. What we were testing
objective
A new external NGINX reverse proxy LXC container (Rocky Linux 10, on Proxmox management VLAN) was being configured to load-balance HTTP traffic across three Kubernetes worker nodes (10.0.64.10, 10.0.64.11, 10.0.64.12) on NodePort 30080. The backend application was a test nginx deployment in the testing namespace with 3 replicas — one Pod per worker — serving a static file from an NFS-backed PersistentVolume. The test application was already confirmed reachable from both AWS (via WireGuard VPN) and internal networks before this session.
nginx upstream config deployed
upstream k8s_workers {
    least_conn;
    server 10.0.64.10:30080;
    server 10.0.64.11:30080;
    server 10.0.64.12:30080;
}

server {
    listen 80;
    server_name nginx-test-dev.local;
    access_log /var/log/nginx/k8s-workers.log upstream_log;

    location / {
        proxy_pass http://k8s_workers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
2. How the issue was first captured
1
After enabling a custom upstream log format, the first meaningful log entry showed two upstream IPs on a single request line — indicating NGINX had retried across workers before getting a response.
192.168.100.223 - [31/Mar/2026:20:14:26] "GET / HTTP/1.1" 200 upstream: 10.0.64.10:30080, 10.0.64.11:30080
Two workers in one log line = NGINX tried worker 1, failed or timed out, then retried on worker 2. This was the first signal that at least one worker was not responding.
2
A second log entry showed all three workers tried and still returned 499 — meaning the client (browser) gave up and closed the connection before any worker responded.
192.168.100.223 - [31/Mar/2026:20:17:45] "GET / HTTP/1.1" 499 upstream: 10.0.64.12:30080, 10.0.64.11:30080, 10.0.64.10:30080
499 = client closed connection. All three workers tried, none responded in time. The issue was not limited to one worker.
3
Browser experience masked the issue — the page loaded most of the time because the browser silently retried failed requests. curl made the hanging visible because it waits patiently with no retry logic.
This explained why the application appeared to work normally when browsing, while curl exposed intermittent hangs clearly.
3. Scaling down suspects — what we tested and what it ruled out
1
Suspect: NGINX misconfiguration
Tested by reviewing config, running nginx -t, confirming upstream block and proxy_pass were syntactically and logically correct.
Ruled out. Config was valid. nginx -t passed. Reload succeeded. The issue persisted after confirmed clean config.
2
Suspect: Network connectivity between NGINX LXC and worker nodes
Tested with ping from NGINX LXC to all three worker IPs.
ping 10.0.64.10  →  0% packet loss, ~2.9ms
ping 10.0.64.11  →  0% packet loss, ~3.0ms
ping 10.0.64.12  →  0% packet loss, ~3.0ms
Ruled out. All three workers were fully reachable at ICMP level. No packet loss. Network was healthy.
3
Suspect: NodePort not reachable on specific workers
Tested curl to NodePort 30080 directly on each worker from the NGINX LXC and from the Mac client.
curl http://10.0.64.10:30080  →  hangs (TCP connects, no HTTP response)
curl http://10.0.64.11:30080  →  hangs intermittently
curl http://10.0.64.12:30080  →  hangs intermittently
Not ruled out yet — TCP connection established (worker port is open) but HTTP response never arrives. This confirmed the problem was above the TCP layer, not a firewall or port issue.
4
Suspect: Calico BGP / cross-node pod routing
Tested calicoctl node status from the master.
| 10.0.64.10 | node-to-node mesh | up | Established |
| 10.0.64.11 | node-to-node mesh | up | Established |
| 10.0.64.12 | node-to-node mesh | up | Established |
Ruled out. All BGP peers established. Calico overlay routing was fully functional across all nodes.
5
Suspect: ClusterIP / kube-proxy internal routing
Tested curl to ClusterIP directly from the master node.
curl http://10.96.229.52:8080  →  Hello from NFS!  (first attempt)
curl http://10.96.229.52:8080  →  hangs           (second attempt)
curl http://10.96.229.52:8080  →  hangs           (third attempt)
Critical finding. The ClusterIP itself was intermittently hanging even from inside the cluster. This proved the problem was not NGINX, not NodePort, not Calico — it was inside the cluster at the Pod or application level. kube-proxy was simply routing to a Pod that was not responding.
4. Confirming it was pod-level — isolation steps
1
Checked pod status — all three showed 2/2 Running with no restarts flagged at that moment. Running status alone does not mean the application inside is healthy.
kubectl get pods -n testing -o wide
nginx-test-858cd7c5cb-52q7x  2/2  Running  k8s-worker3.lab.local  10.244.29.154
nginx-test-858cd7c5cb-7vmzj  2/2  Running  k8s-worker2.lab.local  10.244.207.88
nginx-test-858cd7c5cb-d2t65  2/2  Running  k8s-worker1.lab.local  10.244.62.54
2
Curled each Pod IP directly from the master to bypass NodePort and kube-proxy entirely.
curl http://10.244.62.54:80   →  Hello from NFS!   (worker1 pod — always responds)
curl http://10.244.207.88:80  →  hangs              (worker2 pod — never responds)
curl http://10.244.29.154:80  →  hangs              (worker3 pod — never responds)
This was the definitive isolation step. The problem was confirmed at Pod IP level — not NodePort, not kube-proxy, not Calico. Worker1 pod was healthy, worker2 and worker3 pods were not serving traffic at all.
3
Checked nginx and vault-agent container logs on all three pods. All showed clean nginx startup and successful vault-agent token renewals every ~43 minutes. No errors in any container log.
Logs were clean. This ruled out application crash, vault secret injection failure, and nginx config errors inside the Pod.
4
Checked /proc/1/status inside the broken pod (52q7x on worker3). Nginx master process was alive and sleeping normally. nginx.pid file existed. No crash.
Nginx process was running. The problem was not a crashed process. Something was causing nginx to accept connections but never complete serving a response.
5
Ran ls on the NFS-backed document root inside the broken pod vs the working pod.
kubectl exec nginx-test-858cd7c5cb-52q7x -- ls /usr/share/nginx/html
→  hangs, had to Ctrl+C

kubectl exec nginx-test-858cd7c5cb-d2t65 -- ls /usr/share/nginx/html
→  index.html  (instant response)
Root cause confirmed. The filesystem operation itself hung inside the broken pod. This was not an nginx issue or a Kubernetes issue. The NFS mount was stuck — any operation touching the mounted path blocked indefinitely.
5. Immediate remediation — rolling restart
Since the NFS mount was stuck at the kernel level inside the Pod and no operation on the path could complete, the only available recovery without node-level intervention was to restart the Pods. A rolling restart was triggered from the master.
kubectl rollout restart -n testing deploy/nginx-test
New Pods were scheduled and came up with fresh NFS mounts. All three workers became responsive immediately after the new Pods reached Running state. Post-restart verification confirmed distribution across all three workers.
cat /var/log/nginx/k8s-workers.log

192.168.100.223 - [31/Mar/2026:20:57:53] "GET / HTTP/1.1" 200 upstream: 10.0.64.12:30080
192.168.100.223 - [31/Mar/2026:20:58:00] "GET / HTTP/1.1" 200 upstream: 10.0.64.10:30080
192.168.100.223 - [31/Mar/2026:20:58:06] "GET / HTTP/1.1" 200 upstream: 10.0.64.11:30080
All three workers serving. Load balancing confirmed working correctly across the full upstream pool.
6. Root cause analysis
confirmed root cause
The PersistentVolume definitions for all NFS volumes in the cluster had no mountOptions field. This caused Kubernetes to use kernel NFS defaults when mounting the volumes on worker nodes, which includes hard mount behavior. A hard NFS mount instructs the kernel to retry NFS operations indefinitely if the server becomes unreachable or unresponsive. When the NFS server at 10.0.40.120 experienced a brief disruption (or the path from workers 2 and 3 to the NFS server had a transient issue), operations on those workers entered a permanent wait state. The kernel retried forever with timeo=600 (60 second intervals) but never gave up. Worker1 was either not performing an active NFS operation at the moment of the disruption and recovered cleanly, while workers 2 and 3 got stuck. The nginx process inside the affected Pods was alive and accepting TCP connections, but every attempt to read the index.html file from the NFS-backed path entered the infinite kernel wait. From the outside this looked like nginx accepting connections and then hanging — exactly what was observed.
evidence chain
ls hung inside broken pods → NFS mount stuck at kernel level
ls responded instantly in working pod → NFS mount healthy on worker1
showmount responded from all workers → NFS server itself was reachable
mount | grep nfs showed hard,timeo=600 on all workers → hard mount confirmed as default
No mountOptions in any PV definition → confirmed no override was in place
fix applied to pv definitions
mountOptions:
  - soft
  - timeo=30
  - retrans=3
soft instructs the kernel to return an IO error after retrans retries instead of waiting forever. timeo=30 means each retry waits 3 seconds. retrans=3 means three attempts before returning the error. With this in place, a future NFS disruption causes nginx to return a 500 error to the client rather than hanging indefinitely. The external NGINX load balancer will detect the 500 or timeout, mark that upstream as temporarily unavailable, and route all traffic to the remaining healthy workers automatically — achieving graceful degradation instead of silent hanging.
note on hard vs soft tradeoff
hard mounts are appropriate for write-heavy stateful workloads such as databases where a write that silently fails could cause data corruption. For this use case — nginx pods reading static files from NFS with three replicas — soft is the correct choice. A pod returning a 500 error gracefully is far better than silently hanging and taking the upstream out of rotation without recover