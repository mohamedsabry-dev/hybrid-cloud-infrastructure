Skill 5 — Kubernetes (11 questions)
====================================

Format: Standard questions only. Project examples are ammunition.
Your kubeadm HA cluster, Flux GitOps, Vault agent injection, NFS CSI,
remediation pod, etcd backup chain, HAProxy/Keepalived VIP, Calico CNI,
troubleshooting cases — inject when the bridge is earned.

---

1. Explain Kubernetes architecture — what runs where and why.

   Coverage check:
   - control plane: API server, scheduler, controller-manager, etcd
   - worker node: kubelet, kube-proxy, container runtime
   - static pods (how control plane components run)
   - kubeconfig and authentication to API server
   - what happens from kubectl apply to running container (full flow)
   - kubeadm bootstrap (init/join, certificates, stacked vs external etcd)
   - control plane HA patterns

2. What are Deployments, StatefulSets, DaemonSets, Jobs — when do you use each?

   Coverage check:
   - Deployment — stateless, rolling updates, ReplicaSet management
   - StatefulSet — stable identity, ordered startup/shutdown, persistent storage
   - DaemonSet — one pod per node, monitoring agents, log shippers
   - Job / CronJob — one-off and scheduled batch work
   - init containers, sidecar containers
   - liveness probe vs readiness probe vs startup probe
   - restart policies (Always, OnFailure, Never)

3. How does networking work in Kubernetes?

   Coverage check:
   - pod-to-pod communication (flat network, every pod gets an IP)
   - CNI plugins (Calico, Flannel, Cilium — what they do)
   - Services: ClusterIP, NodePort, LoadBalancer — when each
   - Ingress and Ingress controllers
   - NetworkPolicy — restricting pod-to-pod traffic
   - DNS (CoreDNS — service discovery, pod DNS, headless services)
   - kube-proxy modes (iptables, IPVS)

4. How does storage work in Kubernetes?

   Coverage check:
   - PersistentVolume (PV), PersistentVolumeClaim (PVC)
   - StorageClass, dynamic provisioning
   - access modes (ReadWriteOnce, ReadOnlyMany, ReadWriteMany)
   - reclaim policies (Retain, Delete)
   - CSI drivers
   - ConfigMaps and Secrets (non-persistent config injection)
   - volumeClaimTemplates in StatefulSets

5. How does the scheduler decide where to place a pod?

   Coverage check:
   - resource requests and limits (CPU, memory)
   - what happens when a container exceeds memory limit (OOMKilled)
   - nodeSelector
   - node affinity / anti-affinity
   - pod affinity / anti-affinity
   - taints and tolerations
   - PriorityClasses and preemption
   - topology spread constraints

6. A pod is stuck — debug CrashLoopBackOff, Pending, and Unknown states.

   Coverage check:
   - CrashLoopBackOff: kubectl logs (previous), describe, exec, exit code
   - Pending: insufficient resources, unschedulable, PVC not bound, taints
   - Unknown/NodeLost: node not reporting, kubelet down, network partition
   - ImagePullBackOff: registry auth, image name, network to registry
   - kubectl describe, kubectl get events, kubectl logs --previous
   - escalation: crictl, journalctl -u kubelet, node-level debugging
   - certificate expiry symptoms

7. What is etcd? How do you back it up and what happens when quorum is lost?

   Coverage check:
   - distributed key-value store, stores all cluster state
   - Raft consensus — leader election, log replication
   - quorum (N/2 + 1) — 3 nodes tolerate 1 failure, 5 tolerate 2
   - etcdctl snapshot save/restore
   - what happens when quorum is lost (API server read-only, no new scheduling)
   - single-node vs multi-node recovery paths
   - encryption at rest for etcd data
   - why etcd needs fast disk (latency-sensitive, fsync)

8. Explain RBAC and security in Kubernetes.

   Coverage check:
   - Role vs ClusterRole, RoleBinding vs ClusterRoleBinding
   - ServiceAccounts and token mounting
   - least privilege for pods
   - Pod Security Standards (Restricted, Baseline, Privileged)
   - SecurityContext (runAsNonRoot, readOnlyRootFilesystem, capabilities)
   - secrets management (K8s Secrets are base64 not encrypted by default)
   - API server audit logging
   - admission webhooks (validating, mutating)

9. What is Helm and why would you use it?

   Coverage check:
   - chart structure (templates, values, Chart.yaml)
   - values files and overrides
   - release management (install, upgrade, rollback)
   - Helm hooks (pre-install, post-upgrade)
   - chart repositories
   - when Helm vs raw manifests vs Kustomize

10. What is GitOps? How does it differ from traditional CI/CD?

    Coverage check:
    - pull-based reconciliation (cluster pulls from git, not pushed to)
    - git as single source of truth
    - drift detection and auto-remediation
    - Flux vs ArgoCD (both CNCF, Flux lighter, Argo has UI)
    - dependency ordering (infrastructure before apps)
    - health checks and readiness gates
    - how to handle secrets in GitOps (sealed secrets, external secrets, Vault)

11. How do you upgrade a Kubernetes cluster?

    Coverage check:
    - kubeadm upgrade plan / apply
    - control plane upgrade first, then workers
    - drain / cordon / uncordon
    - version skew policy (kubelet can be 1 minor behind API server)
    - testing upgrade in dev before prod
    - certificate renewal during upgrade
    - CNI and addon compatibility
    - rollback strategy if upgrade fails
