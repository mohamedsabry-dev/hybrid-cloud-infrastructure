# IPA Domain Down
# Date: -
# Result: NOT TESTED

---

## Scope

Stop FreeIPA server. Test DNS/auth dependencies.

---

## Steps

1. Stop IPA server (VM shutdown or service stop)
2. Check: K8s worker-to-master communication (IP-based or DNS?)
3. Check: Vault cluster (certs signed by IPA)
4. Check: Ansible runner connectivity
5. Check: SSH access to nodes
6. Document: IPA restore procedure

---

## Commands

```bash
# Stop IPA
ssh root@ipa 'ipactl stop'
# Or: qm stop <ipa-vmid>

# Check K8s (should use IPs, not DNS)
kubectl get nodes
cat /etc/hosts  # On any K8s node

# Check Vault
ssh root@vault1 'vault status'

# Check SSH still works (local accounts)
ssh root@k8s-worker1 'hostname'

# Restore IPA
ssh root@ipa 'ipactl start'
# Or: qm start <ipa-vmid>
```

---

## Expected Behavior

| Service | Expected |
|---------|----------|
| K8s cluster | UP (uses IPs via /etc/hosts) |
| Vault | UP (certs already issued) |
| SSH | UP (local accounts work) |
| New cert issuance | BLOCKED |
| Ansible (if using LDAP) | May fail |

---

## Dependencies to Check

- [ ] K8s uses IPs or DNS for internal comms?
- [ ] Check /etc/hosts on all nodes
- [ ] Vault certs - expiry time?
- [ ] Ansible inventory - hostnames or IPs?

---

## TODO

- [ ] Document IPA dependencies
- [ ] Execute test
- [ ] Document IPA restore procedure
