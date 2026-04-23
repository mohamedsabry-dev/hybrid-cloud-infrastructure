# TS-K8S-044 | 2026-04-18 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / CoreDNS / High Availability
Sub-techs: CoreDNS deployment, nodeSelector, podAntiAffinity, kubeadm,
           control-plane taint toleration, DNS cascade failure
Environment: DEV k8s cluster | 3 masters + 3 workers
Severity: CRITICAL
Discovered during: DR Test 2 — Total Worker Loss
Related: TS-K8S-043 (NoExecute taint not applied — related eviction issue),
         disaster-recovery/worker-2of3-down.md
Re-opened: No

_____________________________________________________________________

[Issue Description]
CoreDNS pods (replicas=2) could both be scheduled on nodes that fail together.
During DR test, both CoreDNS pods ended up on nodes that went down, causing
complete DNS failure which cascaded to total cluster failure.

During DR test:
- coredns-m7bw6 → worker1 (SHUTDOWN)
- coredns-t8p4b → master3 (SHUTDOWN)
- Result: complete DNS failure

_____________________________________________________________________

[Analysis]

# DNS failure cascade

```
DNS down
    ↓
kube-controller-manager can't do leader election
    ↓
No leader = no taint management
    ↓
Pods don't get evicted
    ↓
Remediation can't start (Vault DNS lookup fails)
    ↓
No self-healing → CLUSTER STUCK
```

Evidence — Vault authentication fails without DNS:
```
error authenticating: "Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\":
dial tcp: lookup vault.lab.local on 10.96.0.10:53: read: connection refused"
```

Controller-manager lost leadership:
```
E0418 19:44:19 "Error retrieving lease lock" err="context deadline exceeded"
```

# Root cause

CoreDNS is deployed by kubeadm with replicas=2 but no `nodeSelector` forcing it
onto control-plane nodes. Both pods can end up on workers or a mix of workers and
masters. No guarantee DNS survives a node failure scenario.

_____________________________________________________________________

[Final Root Cause]
kubeadm deploys CoreDNS without node affinity constraints. Both CoreDNS pods
can schedule on any combination of nodes. When the nodes hosting CoreDNS go
down, the entire cluster loses DNS, which cascades to controller-manager
leadership loss, taint management failure, and complete self-healing breakdown.

_____________________________________________________________________

[Final Solution]

Force CoreDNS to run on control-plane nodes only with podAntiAffinity to spread
across masters:

```bash
kubectl patch deployment coredns -n kube-system --type='strategic' -p '{
  "spec":{
    "template":{
      "spec":{
        "nodeSelector":{"node-role.kubernetes.io/control-plane":""},
        "tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}],
        "affinity":{
          "podAntiAffinity":{
            "requiredDuringSchedulingIgnoredDuringExecution":[{
              "labelSelector":{"matchLabels":{"k8s-app":"kube-dns"}},
              "topologyKey":"kubernetes.io/hostname"
            }]
          }
        }
      }
    }
  }
}'
```

Verified result:
```
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
NAME                       READY   STATUS    NODE
coredns-74b76c898f-94k7p   1/1     Running   k8s-master2.lab.local
coredns-74b76c898f-rr6s9   1/1     Running   k8s-master3.lab.local
```

Both CoreDNS pods on different masters. All workers can die, DNS stays up.

# Why not Flux?

CoreDNS is managed by kubeadm, not Flux. Using Flux creates a circular
dependency: Flux needs API server → needs DNS → needs CoreDNS. If CoreDNS update
fails mid-way, Flux can't recover.

Applied via Ansible playbook instead:

```yaml
# ansible/dev/playbooks/k8s/coredns_ha.yml
- name: Configure CoreDNS HA
  hosts: k8s_masters[0]
  gather_facts: false
  tasks:
    - name: Patch CoreDNS to run on masters
      shell: |
        kubectl patch deployment coredns -n kube-system --type='strategic' -p '{
          "spec": {
            "template": {
              "spec": {
                "nodeSelector": {
                  "node-role.kubernetes.io/control-plane": ""
                },
                "tolerations": [
                  {"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}
                ]
              }
            }
          }
        }'
      environment:
        KUBECONFIG: /etc/kubernetes/admin.conf
```

Command also recorded in: `kubernetes/docs/manual-operation.txt`

# When to re-apply

- After `kubeadm upgrade` (may reset CoreDNS config)
- After cluster rebuild
- If CoreDNS deployment is recreated

Verified: Yes — CoreDNS on separate masters, DNS survives worker loss.

_____________________________________________________________________

[Risk Level] CRITICAL

Without this fix, CoreDNS can schedule on any nodes. If those nodes fail, the
entire cluster loses DNS and all self-healing breaks down.

_____________________________________________________________________

[References]
- TS-K8S-043 — NoExecute taint not applied (related eviction issue)
- disaster-recovery/worker-2of3-down.md — DR test where issue was discovered
- ansible/dev/playbooks/k8s/coredns_ha.yml — Ansible playbook for CoreDNS HA
- kubernetes/docs/manual-operation.txt — manual command reference
