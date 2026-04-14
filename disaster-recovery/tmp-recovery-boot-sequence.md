# Full Recovery Boot Sequence
# Date: -
# Result: NOT TESTED

---

## Scope

Power everything back on after graceful shutdown. Document correct boot order.

---

## Boot Order

1. NAS/NFS storage
2. Proxmox host
3. FreeIPA (DNS/identity)
4. Vault LXCs (secrets)
5. K8s masters (control plane)
6. K8s workers (app pods)

---

## Steps

1. Power on NAS, wait for NFS exports available
2. Power on Proxmox
3. Mount NFS on Proxmox
4. Start FreeIPA VM
5. Start Vault LXCs (will auto-unseal via AWS KMS)
6. Start K8s masters (etcd will form quorum)
7. Start K8s workers (pods will schedule)
8. Verify all services healthy

---

## Commands

```bash
# 1. Verify NAS ready
showmount -e 10.0.40.120

# 2-3. Proxmox boots, mount NFS
mount -a

# 4. Start IPA
qm start <ipa-vmid>
# Wait for IPA ready
ssh root@ipa 'ipactl status'

# 5. Start Vault
pct start <vault1-ctid>
pct start <vault2-ctid>
pct start <vault3-ctid>
# Wait for auto-unseal
ssh root@vault1 'vault status'

# 6. Start K8s masters
qm start <master1-vmid>
qm start <master2-vmid>
qm start <master3-vmid>
# Wait for etcd quorum
kubectl get nodes

# 7. Start K8s workers
qm start <worker1-vmid>
qm start <worker2-vmid>
qm start <worker3-vmid>

# 8. Verify
kubectl get nodes
kubectl get pods -A
curl -I https://wordpress.lab.local
```

---

## Potential Issues

- IPA VM: May fail if NFS external disk not ready
- Worker pods: May fail if NFS not restored before scheduling
- Vault: Should auto-unseal, but verify

---

## TODO

- [ ] Document exact VMIDs/CTIDs
- [ ] Test full boot sequence
- [ ] Measure total recovery time
- [ ] Create runbook
