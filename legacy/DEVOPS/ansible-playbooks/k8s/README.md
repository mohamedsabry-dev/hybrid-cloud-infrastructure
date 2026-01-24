# Kubernetes Cluster Playbooks

## Overview
Ansible playbooks for managing Kubernetes cluster nodes and base OS configuration.

**Target VMs:**
- k8s-master: 10.0.20.181
- k8s-worker-1: 10.0.20.182
- k8s-worker-2: 10.0.20.183
- k8s-worker-3: 10.0.20.187

## Playbook Categories

### Node Management
- Node preparation (kernel modules, sysctl settings)
- Node join/remove operations
- Node drain and cordon
- OS package updates

### Infrastructure
- Container runtime (containerd/CRI-O) management
- Network plugin prerequisites
- Storage provisioner setup
- Load balancer configuration

### Operations
- Cluster health checks
- Certificate rotation
- Backup etcd (master node)
- Log collection and rotation

### Security & Compliance
- Kernel hardening
- SELinux/AppArmor policies
- File integrity monitoring
- Security patches deployment

## Naming Convention
```
k8s-[NN]-[category]-[description].yml

Examples:
- k8s-01-prepare-nodes.yml
- k8s-02-install-containerd.yml
- k8s-03-configure-network.yml
- k8s-04-backup-etcd.yml
- k8s-05-update-certificates.yml
```

## Usage
```bash
# Run against all K8s nodes
ansible-playbook -i ../inventory k8s-01-prepare-nodes.yml

# Run against master only
ansible-playbook -i ../inventory k8s-XX-playbook.yml --limit k8s-master

# Run against workers only
ansible-playbook -i ../inventory k8s-XX-playbook.yml --limit k8s_workers
```

## Important Notes
- OS-level configuration only (not K8s manifests/helm charts)
- Coordinate with kubectl operations for cluster changes
- Always drain nodes before maintenance
- Test on worker-3 first for non-critical changes
- Master node changes require extra caution

## Related Documentation
- Kubernetes docs: `/DC-K8s/02-INFRASTRUCTURE/kubernetes/`
- Network configuration: `/DC-K8s/03-AUTOMATION/network/`
- Disaster recovery: `/DC-K8s/05-TROUBLESHOOTING/kubernetes/`

## Scope
This folder contains playbooks for:
- Operating system configuration
- Node-level services
- Kubernetes dependencies

For Kubernetes application deployments, see:
- `/DC-K8s/03-AUTOMATION/k8s-manifests/`
- `/DC-K8s/03-AUTOMATION/helm-charts/`
