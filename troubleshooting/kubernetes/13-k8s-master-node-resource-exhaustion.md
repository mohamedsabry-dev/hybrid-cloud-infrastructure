# TS-K8S-013 | 2026-04-05 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes
Sub-techs: Kubernetes control plane, kubelet, containerd, etcd, memory exhaustion,
           Flux controllers, NFS storage, Terraform VM resources
Environment: DEV k8s-dev cluster | Proxmox virtualization | k8s-master1/2/3
Re-opened: No

_____________________________________________________________________

[Issue Description]
Kubernetes master node becomes unresponsive due to memory exhaustion. kubectl
commands hang indefinitely, control plane components fail.

  kubectl get pods -n monitoring  → hangs, no response
  kubectl get helmrelease -n monitoring → hangs, no response

  journalctl -u kubelet:
  E0405 20:10:50 kubelet: Status from runtime service failed:
  rpc error: code = DeadlineExceeded desc = context deadline exceeded
  E0405 20:10:50 kubelet: Container runtime sanity check failed
  E0405 20:10:50 kubelet: Skipping pod synchronization: container runtime is down

Impact: complete control plane unavailability. Cannot manage workloads,
deploy applications, or monitor cluster state.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked system memory on master node first.

Command:
  free -h

Output:
  Mem:   total 1.7Gi   used 1.4Gi   free 78Mi   available 244Mi
  Swap:  0B

Only 244MB available, no swap. Red flag — control plane components running
with critically low memory headroom.

Checked kubelet and container runtime:
  systemctl status kubelet → active but errors in journal
  crictl ps → timeout / partial results

Checked top memory consumers:
  ps aux --sort=-%mem | head -20

Checked for NFS issues compounding the problem:
  dmesg | grep -i nfs
  Output:
    [48792.209093] NFS: 10.0.40.120: lost 2 locks
    [48853.649561] NFS: 10.0.40.120: lost 2 locks
    (repeated)

Worker node kernel messages also showed:
  [49198.508336] traps: mysqld[280069] general protection fault
  [49259.133849] NFS: 10.0.40.120: lost 2 locks

Checked worker node memory for comparison:
  ssh k8s-worker1 "free -h"
  Output: Mem total 2.4Gi, available 1.1Gi — workers have adequate headroom.

Memory exhaustion on master caused:
  1. containerd becoming unresponsive
  2. kubelet failing health checks
  3. API server stopping responses
  4. All kubectl commands hanging

NFS lock losses on workers compounded the problem — additional cluster stress.


# Suspected Root Cause
Master node has insufficient memory (1.7GB total, 244MB available) to run
Kubernetes control plane components (API server, etcd, controller-manager,
scheduler) plus Flux controllers simultaneously. No swap configured.


# More Checks Notes:
N/A — memory exhaustion confirmed from free -h and kubelet errors.


# Suspected Solution
Immediate: restart containerd and kubelet. If severely degraded, reboot master.
Permanent: increase master node memory via Terraform.


# Test
Restarted containerd, restarted kubelet, verified cluster recovery.
Applied Terraform memory increase to all 3 masters (+512MB each).

Command:
  systemctl status kubelet containerd
  crictl ps | grep -E "etcd|kube-api"
  kubectl get nodes

Result: PASS — master nodes responsive, kubectl commands executing normally,
no more context deadline exceeded errors in kubelet logs.

_____________________________________________________________________

[Final Root Cause]
Master nodes had insufficient memory (1.7GB total) to sustain Kubernetes control
plane components plus Flux controllers under load. Memory exhaustion caused
containerd to become unresponsive — kubelet failed health checks, API server
stopped responding, all kubectl commands hung indefinitely. No swap configured
meant no fallback. NFS lock losses on worker nodes added additional stress.

_____________________________________________________________________

[Final Solution]

Immediate recovery (in order):
  # 1. Restart container runtime
  systemctl restart containerd

  # 2. If still unresponsive, restart kubelet
  systemctl restart kubelet

  # 3. If severely degraded, reboot — one master at a time (maintain etcd quorum)
  reboot

  # 4. Verify after recovery
  systemctl status kubelet containerd
  crictl ps | grep -E "etcd|kube-api"
  kubectl get nodes

Permanent fix — increase master node memory in Terraform:
  terraform/dev/proxmox/vms/k8s_masters/variables.tf:
    memory = 2560   # increased from 2048 (+512MB) on all 3 masters

Minimum resource requirements:
  Master node    2GB minimum   4GB recommended
  Worker node    2GB minimum   4GB+ recommended
  etcd           512MB min     1GB recommended
  kube-prometheus-stack  1GB min  2GB recommended (schedule on workers only)

Optional: set resource limits on Flux controllers to prevent unbounded growth:
  patches:
    - patch: |
        - op: add
          path: /spec/template/spec/containers/0/resources
          value:
            limits:
              memory: 256Mi
            requests:
              memory: 128Mi

IMPORTANT — rebooting masters: never reboot more than one master at a time
in a 3-node cluster. Rebooting two simultaneously loses etcd quorum.

Verified: Yes

_____________________________________________________________________

[Risk Level] MEDIUM
Note: Restarting containerd/kubelet causes temporary pod disruption on that node.
Terraform memory changes require VM restart. Always reboot masters one at a time.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Notes:
  1. Always provision adequate resources for control plane nodes — 2GB minimum,
     4GB recommended when running Flux controllers alongside control plane
  2. Memory pressure on masters affects entire cluster availability immediately
  3. Monitor master node resources separately from worker nodes
  4. NFS issues can cascade into broader cluster instability
  5. Schedule resource-heavy workloads (monitoring, logging) on workers only
  6. No swap on K8s nodes is recommended by default but leaves zero fallback
     under memory pressure

Commands reference:
  free -h                                  check memory usage
  systemctl status kubelet containerd      check service status
  crictl ps                                list containers via CRI
  journalctl -u kubelet -f                 follow kubelet logs
  dmesg | grep -i nfs                      check for NFS issues
  ps aux --sort=-%mem | head -20           top memory consumers

Related files:
  terraform/dev/proxmox/vms/k8s_masters/variables.tf