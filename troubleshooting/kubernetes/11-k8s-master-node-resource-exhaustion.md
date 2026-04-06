# Kubernetes Master Node Resource Exhaustion

## Problem Summary
Kubernetes master node becomes unresponsive due to memory exhaustion, causing kubectl commands to hang and control plane components to fail.

## Symptoms

### kubectl commands hang indefinitely
```bash
$ kubectl get pods -n monitoring
# Command hangs, no response
^C
$ kubectl get helmrelease -n monitoring
# Command hangs, no response
^C
```

### Container runtime becomes unresponsive
```bash
$ journalctl -u kubelet -f
Apr 05 20:10:50 k8s-master1.lab.local kubelet[1825]: E0405 20:10:50.759597 1825 log.go:32] "Status from runtime service failed" err="rpc error: code = DeadlineExceeded desc = context deadline exceeded"
Apr 05 20:10:50 k8s-master1.lab.local kubelet[1825]: E0405 20:10:50.759653 1825 kubelet.go:3115] "Container runtime sanity check failed" err="rpc error: code = DeadlineExceeded desc = context deadline exceeded"
Apr 05 20:10:50 k8s-master1.lab.local kubelet[1825]: E0405 20:10:50.761182 1825 kubelet.go:2525] "Skipping pod synchronization" err="container runtime is down"
```

## Root Cause
The master node has insufficient memory (1.7GB total, only 244MB available) to run Kubernetes control plane components (API server, etcd, controller-manager, scheduler) plus Flux controllers.

## Investigation Steps

### Step 1: Check system memory
```bash
$ free -h
               total        used        free      shared  buff/cache   available
Mem:           1.7Gi       1.4Gi        78Mi        42Mi       345Mi       244Mi
Swap:             0B          0B          0B
```
**Red flag:** Only 244MB available with no swap.

### Step 2: Check kubelet status
```bash
$ systemctl status kubelet
# May show active but with errors in journal
```

### Step 3: Check container runtime
```bash
$ crictl ps
# May timeout or show partial results
```

### Step 4: Check what's consuming memory
```bash
$ ps aux --sort=-%mem | head -20
```

### Step 5: Check for NFS issues (can compound the problem)
```bash
$ dmesg | grep -i nfs
[48792.209093] NFS: 10.0.40.120: lost 2 locks
[48853.649561] NFS: 10.0.40.120: lost 2 locks
# Repeated NFS lock losses indicate storage server issues
```

**Evidence from session:**
```bash
# Worker node kernel messages showed:
[49198.508336] traps: mysqld[280069] general protection fault ip:7f81f14bc898
[49259.133849] NFS: 10.0.40.120: lost 2 locks
```

## Solution

### Immediate Recovery

**1. Restart container runtime:**
```bash
$ systemctl restart containerd
# or for CRI-O:
$ systemctl restart crio
```

**2. If still unresponsive, restart kubelet:**
```bash
$ systemctl restart kubelet
```

**3. If cluster is severely degraded, reboot nodes:**
```bash
# Reboot one master at a time to maintain etcd quorum
$ reboot
```

**4. After reboot, verify cluster recovery:**
```bash
$ systemctl status kubelet containerd
$ crictl ps | grep -E "etcd|kube-api"
$ kubectl get nodes
```

### Permanent Fix

**1. Increase master node memory:**
- Minimum: 2GB RAM
- Recommended: 4GB RAM for control plane + Flux

**Terraform update (applied):**
```hcl
# terraform/dev/proxmox/vms/k8s_masters/variables.tf
variable "k8s_master1" {
  default = {
    # ...
    memory = 2560  # Increased from 2048 (+512MB)
    # ...
  }
}
# Same for k8s_master2 and k8s_master3
```

**2. Add swap (optional, not recommended for production):**
```bash
$ fallocate -l 2G /swapfile
$ chmod 600 /swapfile
$ mkswap /swapfile
$ swapon /swapfile
```

**3. Set resource limits for Flux controllers:**
```yaml
# In Flux kustomization, patch controller resources
patches:
  - patch: |
      - op: add
        path: /spec/template/spec/containers/0/resources
        value:
          limits:
            memory: 256Mi
          requests:
            memory: 128Mi
```

### Verify Worker Resources
```bash
$ ssh k8s-worker1 "free -h"
               total        used        free      shared  buff/cache   available
Mem:           2.4Gi       1.3Gi        97Mi        60Mi       1.3Gi       1.1Gi
# Workers have more headroom (1.1GB available)
```

## Minimum Resource Requirements

| Component | Minimum RAM | Recommended RAM |
|-----------|-------------|-----------------|
| Master Node | 2GB | 4GB |
| Worker Node | 2GB | 4GB+ |
| etcd | 512MB | 1GB |
| kube-prometheus-stack | 1GB | 2GB |

## Prevention
- Monitor node resources with Prometheus/Grafana
- Set up alerts for memory usage > 80%
- Use resource requests/limits on all workloads
- Schedule resource-heavy workloads (monitoring, logging) on workers only
- Consider dedicated infrastructure nodes for control plane
