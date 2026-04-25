DR Test: Ingress NGINX Failures
Date: 2026-04-16
Result: PASS
_____________________________________________________________________

[Info]
Domain: Kubernetes / Ingress / Networking / Lua backends
Environment: DEV k8s-dev cluster | Proxmox
Triggered by: Need to understand ingress failure behavior and backend update mechanics

_____________________________________________________________________

[Planned Scope]

Kill all ingress-nginx pods and observe outage duration + auto-recovery.
Then verify that ingress-nginx dynamically updates its backend table
when pods scale down/up without needing an nginx reload.

Components expected to be affected: ingress-nginx, external nginx (502s),
WordPress (unreachable during ingress outage)

Note: Partial failure (1/3 pods) was skipped — 3 replicas with kube-proxy
routing means killing 1 pod has zero visible impact. Not worth testing.

_____________________________________________________________________

[Pre-State]

3 ingress-nginx controller pods across workers:
```
ingress-nginx-controller-...-4mjnt   1/1  Running  k8s-worker2
ingress-nginx-controller-...-pfpjh   1/1  Running  k8s-worker1
ingress-nginx-controller-...-wx4cv   1/1  Running  k8s-worker2
```

WordPress accessible via external nginx → ingress → pods. Confirmed 200 OK.

_____________________________________________________________________

[Test 1.1 — Kill all 3 ingress pods simultaneously]

Action:
  ```
  kubectl delete pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
  ```

What happened:
  - External NGINX: UP (still listening, forwarding to NodePort)
  - Ingress pods: all gone — no backend to serve
  - User sees: **502 Bad Gateway** for ~17-20 seconds
  - Recovery: Deployment controller recreated all 3 pods automatically

  ```
  curl -I http://wordpress-dev.lab.local
  HTTP/1.1 502 Bad Gateway    # 20:51:08 — 20:51:25
  ```

  New pods came up on different workers (~21s):
  ```
  ingress-nginx-controller-...-c9wrl   1/1  Running  k8s-worker3
  ingress-nginx-controller-...-d782c   1/1  Running  k8s-worker3
  ingress-nginx-controller-...-lcxbl   1/1  Running  k8s-worker1
  ```

Cascade:
  All ingress pods dead → external nginx has no healthy upstream →
  returns 502 → user sees Bad Gateway → Deployment recreates pods →
  service restored

What this tells me:
  The failure mode depends on which layer is down:

  | External NGINX | Ingress | User sees |
  |----------------|---------|-----------|
  | DOWN           | Any     | Connection timeout/refused |
  | UP             | DOWN    | 502 Bad Gateway |
  | UP             | UP      | 200 OK |

  502 means external nginx is working but has nothing to forward to.
  Connection refused/timeout means external nginx itself is gone.
  Useful for quick triage — the HTTP response tells you which layer broke.

_____________________________________________________________________

[Test 1.2 — Verify dynamic backend updates (scale down/up)]

Why this test: ingress-nginx uses Lua to route traffic, not static
  upstream blocks. Wanted to confirm pod IPs update in real time without
  nginx reload.

Action:
  Scaled WordPress to 2 replicas, checked Lua backend table, then let
  Flux reconcile back to 3.

  ```
  kubectl scale deployment wordpress -n apps --replicas=2
  ```

What happened:
  - Kubernetes endpoints: removed terminated pod IP immediately
  - Lua backend (queried via curl localhost:10246/configuration/backends):
    same — removed IP instantly, no reload
  - Flux reconciled back to 3 replicas within seconds
  - New pod IP appeared in both endpoints and Lua backend after pod
    reached 2/2 Ready (11s startup — vault init containers)

  Key observation: pod was NOT added to endpoints until 2/2 Ready.
  Readiness gates correctly held the pod out of rotation until vault
  sidecar was ready.

Cascade:
  Scale down → endpoint removed → Lua table updated (no reload) →
  Flux restores replica count → new pod starts → vault init (4s) →
  sidecar ready (11s) → pod added to endpoints → Lua picks it up

What this tells me:
  ingress-nginx doesn't use static upstream blocks like traditional nginx.
  Everything is in a Lua shared dictionary updated via internal API. Pod
  IPs are never in nginx.conf — they're only in the runtime Lua state.
  This means endpoint changes are instant with zero reload overhead.

  Vault init containers add ~11s minimum to any pod joining the backend.
  That's the floor for how fast a new pod can start serving traffic.

_____________________________________________________________________

[Findings]

1. Full ingress pod kill = ~17-20s outage (502 Bad Gateway). Auto-recovery
   via Deployment controller, no manual intervention needed.

2. Lua-based routing means zero-reload backend updates. Pod IPs live in
   Lua shared memory, not nginx.conf. Endpoint changes propagate instantly.

3. Readiness gates work correctly — pods aren't added to the backend until
   all containers (including vault sidecar) pass readiness checks. No
   premature traffic routing.

4. Vault init adds ~11s startup floor. Any pod needing vault secrets takes
   at minimum 11s before it can serve traffic. This is the real bottleneck
   for recovery speed, not ingress-nginx itself.

5. Flux enforces desired state — manual scale-down gets reconciled back
   automatically. Persistent changes must go through Git.

_____________________________________________________________________

[Planned Next]

- See network-external-nginx-failure.md for external NGINX layer tests

_____________________________________________________________________

[References]

- network-external-nginx-failure.md — External NGINX (LXC) failure tests
- storage-single-worker-nfs-down.md — readiness probe fix (same mechanism)
- kubernetes/dev/deployments/infrastructure/ingress/ — Ingress helm release
