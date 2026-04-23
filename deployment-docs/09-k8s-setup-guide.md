# Kubernetes HA Cluster - Initial Setup Guide (DEV)

Note: If you face issues during deployment, check the troubleshooting/ folder
for the related technology section. Most common issues have been documented there.
Relevant folders: troubleshooting/kubernetes/, troubleshooting/identity/

---

## Overview

This guide covers the complete setup of a 6-node Kubernetes HA cluster (3 masters + 3 workers) running on Proxmox VMs, integrated with FreeIPA for domain trust, and FluxCD for GitOps deployments.

---

## Prerequisites

Before starting K8s deployment:

### AWS Secrets Manager (CRITICAL)

All GitHub workflows depend on secrets stored in AWS Secrets Manager.
These must be created and populated BEFORE any infrastructure deployment.

See: aws-secrets-setup-guide.txt

Required secrets for Kubernetes:
- dev/proxmox/terraform-token
- dev/ansible/ssh-public-key
- dev/golden-image/vm-root-password
- dev/super_bot/keytab

GitHub Secrets also required:
- GH_ADMIN_PAT_FLUX (for FluxCD)
- GH_USERNAME

### Other Prerequisites

1. FreeIPA must be running and functional (see freeipa-initial-setup-guide.txt)
2. super_bot keytab must exist in AWS Secrets Manager (dev/super_bot/keytab)

---

## Phase 1: Golden VM Template Creation

### 1.1 Deploy Base VM

Terraform Path: terraform/dev/proxmox/vms/golden-image/

GitHub Workflow: .github/workflows/dev-golden-full-setup.yml

Note: The VM job has its own gate lock to prevent accidental re-runs.

### 1.2 Bootstrap the Golden Image

After Terraform completes, run the bootstrap script inside the VM:

Script Path: proxmox/golden_templates/golden-vm-setup.sh

  # SSH into the VM and run:
  ./golden-vm-setup.sh

### 1.3 Create Template Image

1. Shutdown the VM
2. Copy to a new VM ID
3. Convert to template
4. Save to NAS storage for reuse

---

## Phase 2: Deploy Kubernetes Infrastructure

### 2.1 Deploy 3 Master VMs

Terraform Path: terraform/dev/proxmox/vms/k8s_masters/

GitHub Workflow: .github/workflows/dev-k8s-full-setup.yml

Gate Lock: DEV_INFRA_K8S_MASTERS_LOCK (set to 'true' to skip, remove or set 'false' to run)

Job 1 (deploy-masters) creates 3 VMs for the control plane.

### 2.2 Deploy 3 Worker VMs

Terraform Path: terraform/dev/proxmox/vms/k8s_workers/

Gate Lock: DEV_INFRA_K8S_WORKERS_LOCK (set to 'true' to skip, remove or set 'false' to run)

Job 2 (deploy-workers) creates 3 VMs for workloads.

**Worker Dual-NIC Configuration:**

Workers have two network interfaces for NAS storage access:

| Interface | VLAN | IP Range      | Purpose                    |
|-----------|------|---------------|----------------------------|
| Primary   | 64   | 10.0.64.10-12 | K8s service network        |
| Secondary | 40   | 10.0.40.201-203 | NAS storage mount (NFS)  |

The storage network (VLAN 40) allows workers to mount NFS volumes from NAS (10.0.40.120)
for persistent storage without routing through the service network.

---

## Phase 3: FreeIPA Domain Integration

Run the following Ansible playbooks IN SEQUENCE after K8s VMs are deployed and FreeIPA is functional:

Playbook Directory: ansible/dev/playbooks/freeipa/

  cd ansible/dev/

  # Step 1: Register hosts in FreeIPA
  ansible-playbook -i inventory/inventory.ini playbooks/freeipa/add_hosts_to_ipa.yml

  # Step 2: Configure domain settings
  ansible-playbook -i inventory/inventory.ini playbooks/freeipa/domain_config.yml

  # Step 3: Add DNS records
  ansible-playbook -i inventory/inventory.ini playbooks/freeipa/add_dns_records.yml

For more details on each playbook, see: ansible/dev/playbooks/freeipa/README.md

### 3.1 Manual: Generate and Store Keytab

After domain integration:

1. Generate keytab for 'super_bot' service account on FreeIPA
2. Base64 encode and store in AWS Secrets Manager: dev/super_bot/keytab

---

## Phase 4: Kubernetes Cluster Setup

### 4.1 Run K8s Setup Workflow

GitHub Workflow: .github/workflows/dev-k8s-full-setup.yml

Gate Lock: DEV_SVC_K8S_CLUSTER_SETUP (set to 'true' to skip, remove or set 'false' to run)

Job 3 (deploy-k8s-cluster) performs the following playbooks in sequence:

  cd ansible/dev/

  # 1. Pre-setup - Base configuration for K8s nodes
  ansible-playbook -i inventory/inventory.ini playbooks/common/pre_setup.yml --limit k8s

  # 2. NTP configuration
  ansible-playbook -i inventory/inventory.ini playbooks/common/ntp.yml --limit k8s

  # 3. K8s setup - Prerequisites, containerd, kubeadm, HAProxy+Keepalived
  ansible-playbook -i inventory/inventory.ini playbooks/k8s/k8s_setup.yml

  # 4. K8s init - Initialize cluster, Calico CNI, join nodes
  ansible-playbook -i inventory/inventory.ini playbooks/k8s/k8s_init.yml

  # 5. Important tools - Helm, calicoctl
  ansible-playbook -i inventory/inventory.ini playbooks/k8s/k8s_important_tools.yml

  # 6. Flux setup - Bootstrap FluxCD for GitOps
  ansible-playbook -i inventory/inventory.ini playbooks/k8s/flux_setup.yml

### 4.2 What Each Playbook Does

**k8s_setup.yml:**
- Disables swap, firewalld, sets SELinux to permissive
- Loads kernel modules (overlay, br_netfilter)
- Sets sysctl params (bridge-nf-call-iptables, ip_forward)
- Installs containerd with SystemdCgroup driver
- Installs kubeadm, kubelet, kubectl (v1.35)
- Configures HAProxy + Keepalived for HA (VIP: 10.0.61.100)

**k8s_init.yml:**
- Runs kubeadm init on master1 (control-plane-endpoint: 10.0.61.100:16443)
- Installs Calico CNI (v3.31.4, pod CIDR: 10.244.0.0/16)
- Configures Calico IP autodetection for multi-NIC nodes
- Joins additional masters and workers to cluster
- Sets up kubeconfig for kubectl access

**k8s_important_tools.yml:**
- Installs Helm package manager
- Installs calicoctl CLI

**flux_setup.yml:**
- Installs Flux CLI
- Bootstraps Flux with GitHub repository

For more details, see: ansible/dev/playbooks/k8s/README.md

### 4.3 HA Architecture Details

K8s HA uses HAProxy + Keepalived on master nodes:

  VIP: 10.0.61.100 (k8s.lab.local)
  HAProxy frontend: 16443 (load balancer)
  K8s API backend: 6443 (actual API server)

  Flow: kubectl -> VIP:16443 -> HAProxy -> master1/2/3:6443

Priority: k8s-master1 (101) > k8s-master2 (100) > k8s-master3 (99)

kubeadm init command used:
  kubeadm init \
    --control-plane-endpoint=10.0.61.100:16443 \
    --upload-certs \
    --pod-network-cidr=10.244.0.0/16

### 4.4 GitHub Token for Flux

FluxCD requires a GitHub Personal Access Token (PAT) to sync with the repository.

Required secrets in GitHub Actions:
- GH_ADMIN_PAT_FLUX - GitHub PAT with repo access
- GH_USERNAME - GitHub username

The workflow exports these as environment variables:
- GH_TOKEN -> gh_admin_pat_token_flux
- GH_USER -> gh_username

Flux bootstrap configuration:
- Repository: hybrid-cloud-infrastructure
- Branch: dev
- Path: ./kubernetes/dev/flux

### 4.5 DNS Configuration

Ensure FreeIPA DNS has an A record:
- k8s.lab.local -> 10.0.61.100 (VIP)

This allows kubectl and workloads to connect to the K8s API via the VIP.

---

## Phase 5: Post-Installation Verification

### 5.1 Verify Cluster Status

SSH to any master node:

  ssh root@k8s-master1.lab.local

  export KUBECONFIG=/etc/kubernetes/admin.conf

  # Check all nodes are Ready
  kubectl get nodes

  # Check system pods
  kubectl get pods -n kube-system

  # Check Calico status
  calicoctl node status

### 5.2 Verify Flux Status

  kubectl get pods -n flux-system
  flux get all

### 5.3 Verify HA

  # Check HAProxy is running
  systemctl status haproxy

  # Check Keepalived is running
  systemctl status keepalived

  # Check VIP assignment
  ip addr show eth0 | grep 10.0.61.100

---

## Summary - File Reference

| Component              | Path                                              |
|------------------------|---------------------------------------------------|
| Golden VM Template TF  | terraform/dev/proxmox/vms/golden-image/           |
| K8s Masters TF         | terraform/dev/proxmox/vms/k8s_masters/            |
| K8s Workers TF         | terraform/dev/proxmox/vms/k8s_workers/            |
| Golden VM Bootstrap    | proxmox/golden_templates/golden-vm-setup.sh       |
| Golden Setup Workflow  | .github/workflows/dev-golden-full-setup.yml       |
| K8s Setup Workflow     | .github/workflows/dev-k8s-full-setup.yml          |
| FreeIPA Playbooks      | ansible/dev/playbooks/freeipa/                    |
| K8s Playbooks          | ansible/dev/playbooks/k8s/                        |
| K8s Setup Playbook     | ansible/dev/playbooks/k8s/k8s_setup.yml           |
| K8s Init Playbook      | ansible/dev/playbooks/k8s/k8s_init.yml            |
| K8s Tools Playbook     | ansible/dev/playbooks/k8s/k8s_important_tools.yml |
| Flux Setup Playbook    | ansible/dev/playbooks/k8s/flux_setup.yml          |
| HAProxy Template       | ansible/dev/playbooks/k8s/templates/haproxy.cfg.j2 |
| Keepalived Template    | ansible/dev/playbooks/k8s/templates/keepalived.conf.j2 |
| Kubeconfig Task        | ansible/dev/playbooks/k8s/tasks/setup-kubeconfig.yml |
| K8s Masters Group Vars | ansible/dev/inventory/group_vars/k8s_masters.yml  |
| Flux Path              | kubernetes/dev/flux/                              |

---

## AWS Secrets Reference

| Secret                             | Purpose                          |
|------------------------------------|----------------------------------|
| dev/proxmox/terraform-token        | Proxmox API credentials          |
| dev/ansible/ssh-public-key         | SSH key for VM access            |
| dev/golden-image/vm-root-password  | VM root password                 |
| dev/super_bot/keytab               | Kerberos keytab (base64)         |

---

## GitHub Secrets Reference

| Secret                | Purpose                          |
|-----------------------|----------------------------------|
| GH_ADMIN_PAT_FLUX     | GitHub PAT for FluxCD            |
| GH_USERNAME           | GitHub username for Flux         |

---

## Ansible Vault Encrypted Variables

Location: ansible/dev/inventory/group_vars/k8s_masters.yml

| Variable                 | Purpose                              |
|--------------------------|--------------------------------------|
| k8s_keepalived_auth_pass | Keepalived authentication password   |

Note: Decrypt with ansible-vault or use vault password file configured in ansible.cfg

---

## Configuration Summary

| Component       | Value                          |
|-----------------|--------------------------------|
| K8s Version     | v1.35                          |
| Container Runtime | containerd (SystemdCgroup)   |
| CNI             | Calico v3.31.4                 |
| Pod CIDR        | 10.244.0.0/16                  |
| VIP             | 10.0.61.100                    |
| HAProxy Port    | 16443                          |
| API Port        | 6443                           |
| SELinux         | Permissive                     |
| Firewalld       | Disabled                       |

---
