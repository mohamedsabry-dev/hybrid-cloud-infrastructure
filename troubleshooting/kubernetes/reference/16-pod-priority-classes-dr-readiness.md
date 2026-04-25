# TS-K8S-016 | 2026-04-06 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes
Sub-techs: Pod priority classes, preemption, eviction order, DR readiness,
           Vault Injector, Ingress NGINX, Flux, MariaDB, WordPress
Environment: DEV k8s-dev cluster | k8s-master1.lab.local | all namespaces
Re-opened: No

_____________________________________________________________________

[Issue Description]
Configuration gap discovered during DR Test 1 preparation — not a live failure.
Critical infrastructure pods have no priority class configured. During node
failures or resource pressure, critical pods would be evicted with same priority
as monitoring pods, causing incorrect eviction order and service disruption.

Required priority order (highest to lowest):
  1. Infrastructure (system-node-critical / system-cluster-critical)
     NFS CSI driver, Vault Injector, Ingress NGINX, Flux controllers
  2. Database (database-critical)
     MariaDB
  3. Application (app-standard)
     WordPress
  4. Monitoring (default/0)
     Prometheus, Grafana, Alertmanager

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Audited priority classes on all critical workloads.

Command:
  kubectl get priorityclass
Output:
  system-cluster-critical  2000000000
  system-node-critical     2000001000
  (only system classes exist — custom classes needed for db/app)

Component audit results:

  CSI NFS Controller/Node    system-cluster-critical   OK
  Vault Injector             0 (default)               NEEDS FIX
  Ingress NGINX              0 (default)               NEEDS FIX
  Flux helm-controller       system-cluster-critical   OK
  Flux kustomize-controller  system-cluster-critical   OK
  Flux source-controller     system-cluster-critical   OK
  Flux notification-ctrl     0 (default)               ACCEPTABLE
  MariaDB                    0 (default)               NEEDS FIX
  WordPress                  0 (default)               NEEDS FIX
  Monitoring (all 11 pods)   0 (default)               OK (lowest as expected)

Both Vault and Ingress NGINX Helm charts support priorityClassName but it
was not set:
  helm show values vault | grep priorityClassName → priorityClassName: ""
  helm show values ingress-nginx | grep priorityClassName → priorityClassName: ""


# Suspected Root Cause
Critical workloads (Vault Injector, Ingress NGINX, MariaDB, WordPress) deployed
without priority class configuration. During resource pressure or node failure,
these pods would be evicted at the same priority as monitoring pods — incorrect
eviction order, database could be evicted before monitoring.


# More Checks Notes:
N/A — audit confirmed all gaps. Fix direction clear.


# Suspected Solution
Create custom priority classes (database-critical, app-standard) and configure
all affected workloads via Helm values and manifest patches.


# Test
Applied priority classes and updated all workloads. Verified with:

Command:
  kubectl describe pod -A | grep -i priority -B 4

Result: PASS — all components at correct priority levels (see final solution table).

_____________________________________________________________________

[Final Root Cause]
Critical workloads deployed without priority class configuration. Default priority
(0) means Vault Injector, Ingress NGINX, and MariaDB would be evicted at the same
time as monitoring during resource pressure — incorrect order for DR and cluster
stability.

_____________________________________________________________________

[Final Solution]

Step 1 — Create custom priority classes:
  File: kubernetes/deployments/infrastructure/priority-classes.yaml

  apiVersion: scheduling.k8s.io/v1
  kind: PriorityClass
  metadata:
    name: database-critical
  value: 1000000
  globalDefault: false
  description: "Database workloads - higher than apps, lower than infrastructure"
  ---
  apiVersion: scheduling.k8s.io/v1
  kind: PriorityClass
  metadata:
    name: app-standard
  value: 500000
  globalDefault: false
  description: "Application workloads - standard priority"

Step 2 — Update infrastructure Helm releases:
  Vault Injector:     injector.priorityClassName: system-cluster-critical
  Ingress NGINX:      controller.priorityClassName: system-cluster-critical

Step 3 — Update application workloads:
  MariaDB StatefulSet:   spec.template.spec.priorityClassName: database-critical
  WordPress Deployment:  spec.template.spec.priorityClassName: app-standard

Final priority table:
  system-node-critical    2000001000   etcd, apiserver, scheduler, controller-manager,
                                       kube-proxy, calico-node, csi-nfs-node
  system-cluster-critical 2000000000   calico-controllers, coredns, csi-nfs-controller,
                                       descheduler, vault-injector, ingress-nginx,
                                       flux controllers
  database-critical       1000000      mariadb
  app-standard            500000       wordpress
  (default)               0            monitoring stack, notification-controller

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Pods will be briefly restarted when priority class is added to existing
deployments. No data loss expected.

_____________________________________________________________________

[References]
- https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/
- DR Test 1 prerequisites

_____________________________________________________________________

[Draft Notes]

Why priority classes matter for DR:
  During node failure: pods evicted in priority order (lowest first)
  During resource pressure: lower priority pods preempted for higher priority
  Incorrect order example: database evicted before monitoring → data layer
  unavailable while dashboards still show green

Correct reasoning for each tier:
  Monitoring at default (0) → non-critical, should be evicted first to free resources
  Infrastructure highest    → storage and networking must be available before anything else
  Database before app       → data layer must be ready before application layer

Verification command:
  kubectl describe pod -A | grep -i priority -B 4