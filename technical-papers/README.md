Technical Papers
================

Each paper traces one scenario end-to-end through every layer it touches —
kernel, network, virtualization, switch, k8s, app, whatever the flow crosses.

Organized by scenario, not by domain.
Splitting by domain breaks the story. The value is the vertical cut.

This matches how interview questions work:
"walk me through what happens when..."

Papers:
  - nfs-vm-read-trace.md         — NFS read on a VM: app → kernel → wire → NAS and back
  - nfs-k8s-pv-trace.md          — NFS on k8s: PV/PVC lifecycle, kubelet mount, pod creation
  - proxmox-storage-layer.md     — hypervisor storage: LVM thin pool, NFS mounts, VM I/O paths
  - web-request-aws-to-pod.md   — web request: AWS EC2 → VPN → MikroTik → Proxmox → k8s → pod and back
  - oidc-terraform-trust-chain.md — OIDC trust chain: GitHub Actions → AWS STS → IAM roles → Terraform → Proxmox
  - ansible-kerberos-fleet-deployment.md — Ansible deployment: GitHub → runner → Kerberos keytab → FreeIPA fleet
  - vault-unseal-kms-chain.md — Vault operations: FreeIPA TLS certs, KMS auto-unseal chain, LDAP human auth
  - k8s-pod-creation-chain.md — pod creation: API server gates → webhook → scheduler → vault injection → probes → traffic
  - flux-gitops-reconciliation.md — Flux GitOps: 7-step reconciliation, dependency ordering, prune, drift correction
  - coredns-resolution-chain.md — CoreDNS: 3 query types happy path, FreeIPA failure cascade, hosts plugin fix

Summary traces (compressed arrow-format) live in summary-traces/.


target 20 techniocal paper, the env can spit up to 17 i think and i may add 3 from the applied jobs or based on market gaps or needs in shaa allah 