# Monitoring Infrastructure

Prometheus and Grafana monitoring stack.

## Structure

```
monitoring/
├── prometheus/
│   ├── terraform/          # Prometheus deployment
│   ├── configs/            # prometheus.yml, etc.
│   └── rules/              # Alert rules
├── grafana/
│   ├── terraform/          # Grafana deployment
│   ├── dashboards/         # Dashboard JSON
│   └── datasources/        # Datasource configs
├── docs/
└── troubleshooting-cases/
```

## Stack Components

| Component | Purpose |
|-----------|---------|
| Prometheus | Metrics collection |
| Grafana | Visualization |
| Alertmanager | Alert routing |
| Node Exporter | Host metrics |

## Dashboards

- Infrastructure Overview
- VMware vSphere
- Kubernetes Cluster
- Application Metrics

## Getting Started

```bash
# Deploy Prometheus
cd prometheus/terraform
terraform init && terraform apply

# Deploy Grafana
cd ../../grafana/terraform
terraform init && terraform apply
```

## Alert Routing

Alerts sent to:
- Slack
- Email
- PagerDuty (critical)
