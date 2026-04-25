Tests Planned for Later
=========================================================

1. Kubernetes full etcd backup restore (S3 → new cluster)
2. Auto-recovery & alerting for Proxmox compute resources (LXC, VMs)
3. Electricity down — full power loss, boot sequence validation
4. Abnormal pod restarts — investigate unexpected restart patterns
5. Mixed-impact simulation: 1 internal K8s component failure + Flux reconcile + app failure + worker degraded simultaneously
6. Repeat the API storm ticket + Flux reconcile loop under load
7. Repeat worker down test — observe eviction priority and pod scheduling under resource pressure
