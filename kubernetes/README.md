# Kubernetes Infrastructure

Kubernetes cluster configurations for on-premises and EKS.

## Structure

```
kubernetes/
├── terraform/              # K8s cluster deployment
│   ├── on-prem/            # On-prem K8s via Terraform
│   └── eks/                # AWS EKS cluster
├── ansible/                # K8s installation & config
│   ├── playbooks/
│   │   ├── cluster-bootstrap/
│   │   └── worker-join/
│   └── roles/
├── manifests/              # K8s YAML files
│   ├── on-prem/
│   │   ├── core/           # Core services
│   │   ├── monitoring/     # Monitoring stack
│   │   └── apps/           # Applications
│   └── eks/
├── helm-charts/            # Helm chart values
├── docs/
│   ├── cluster-architecture.md
│   ├── networking.md
│   └── storage.md
├── troubleshooting-cases/
└── scripts/
    ├── cluster-health.sh
    └── node-drain.sh
```

## Clusters

| Cluster | Type | Location | Purpose |
|---------|------|----------|---------|
| on-prem | kubeadm | VMware | Internal workloads |
| eks | EKS | AWS | Public-facing apps |

## Getting Started

```bash
# On-prem cluster bootstrap
cd ansible/playbooks/cluster-bootstrap
ansible-playbook -i inventory bootstrap.yml

# EKS cluster
cd terraform/eks
terraform init && terraform apply
```

## Documentation

- [Cluster Architecture](docs/cluster-architecture.md)
- [Networking](docs/networking.md)
- [Storage](docs/storage.md)
