# Proxmox VM/LXC Backup Validation
# Date: 2026-04-11
# Result: PASS

---

## Scope

Complete Proxmox backup of all VMs/LXCs before DR testing begins.
Validate vzdump snapshot-mode backup is non-disruptive to running workloads.

---

## Pre-Test Checklist

**VMs to backup:**
- [x] 1001 (freeipa)
- [x] 1010 (k8s-master1)
- [x] 1011 (k8s-master2)
- [x] 1012 (k8s-master3)
- [x] 1020 (k8s-worker1)
- [x] 1021 (k8s-worker2)
- [x] 1022 (k8s-worker3)

**LXCs to backup:**
- [x] 2001 (ansible)
- [x] 2002 (local-runner)
- [x] 2003 (ex-nginx)
- [x] 2004 (vault1)
- [x] 2005 (vault2)
- [x] 2006 (vault3)

---

## pve-dev Backup

**Proxmox Backup Job:**
- Start Time: Apr 11 14:11:36
- End Time: Apr 11 14:21:25
- Duration: ~10 minutes
- Storage: nas-dev-data
- Status: OK

**VMs Backed Up:**

| VMID | Name | Status |
|------|------|--------|
| 1001 | freeipa | OK |
| 1010 | k8s-master1 | OK |
| 1011 | k8s-master2 | OK |
| 1012 | k8s-master3 | OK |
| 1020 | k8s-worker1 | OK |
| 1021 | k8s-worker2 | OK |
| 1022 | k8s-worker3 | OK |
| 9000 | rocky10-golden-image | OK (shutdown - TF template) |
| 9001 | rocky10-golden-template | OK (shutdown - TF template) |

**LXCs Backed Up:**

| CTID | Name | Status |
|------|------|--------|
| 2001 | ansible | OK |
| 2002 | local-runner | OK |
| 2003 | ex-nginx | OK |
| 2004 | vault1 | OK |
| 2005 | vault2 | OK |
| 2006 | vault3 | OK |
| 9010 | rocky10-lxc-golden | OK (shutdown - TF template) |

**Evidence:**
```bash
root@pve-dev:~# ls -lh /mnt/pve/nas-dev-data/dump/ | grep 2026_04_11

# LXCs (427M-1.2G each)
vzdump-lxc-2001-2026_04_11-14_18_45.tar.zst  427M
vzdump-lxc-2002-2026_04_11-14_19_00.tar.zst  1.2G
vzdump-lxc-2003-2026_04_11-14_19_32.tar.zst  290M
vzdump-lxc-2004-2026_04_11-14_19_44.tar.zst  452M
vzdump-lxc-2005-2026_04_11-14_19_59.tar.zst  451M
vzdump-lxc-2006-2026_04_11-14_20_14.tar.zst  456M
vzdump-lxc-9010-2026_04_11-14_21_15.tar.zst  223M

# VMs (1.4G-6.6G each)
vzdump-qemu-1001-2026_04_11-14_11_36.vma.zst  1.6G
vzdump-qemu-1010-2026_04_11-14_12_50.vma.zst  3.5G
vzdump-qemu-1011-2026_04_11-14_13_44.vma.zst  3.6G
vzdump-qemu-1012-2026_04_11-14_14_33.vma.zst  3.3G
vzdump-qemu-1020-2026_04_11-14_15_15.vma.zst  6.6G
vzdump-qemu-1021-2026_04_11-14_16_26.vma.zst  6.2G
vzdump-qemu-1022-2026_04_11-14_17_32.vma.zst  6.3G
vzdump-qemu-9000-2026_04_11-14_20_30.vma.zst  1.4G
vzdump-qemu-9001-2026_04_11-14_20_52.vma.zst  1.4G
```

---

## pve-prod Backup

**Proxmox Backup Job:**
- Start Time: Apr 11 12:19:28
- End Time: Apr 11 12:29:37
- Duration: ~10 minutes
- Storage: nas-prod-data
- Status: OK

**VMs Backed Up:**

| VMID | Name | Status |
|------|------|--------|
| 1001 | freeipa | OK |
| 1010 | k8s-master1 | OK |
| 1011 | k8s-master2 | OK |
| 1012 | k8s-master3 | OK |
| 1020 | k8s-worker1 | OK |
| 1021 | k8s-worker2 | OK |
| 1022 | k8s-worker3 | OK |
| 9000 | rocky10-golden-image | OK (shutdown - TF template) |
| 9001 | rocky10-golden-template | OK (shutdown - TF template) |

**LXCs Backed Up:**

| CTID | Name | Status |
|------|------|--------|
| 2001 | ansible | OK |
| 2002 | local-runner | OK |
| 2003 | ex-nginx | OK |
| 2004 | vault1 | OK |
| 2005 | vault2 | OK |
| 2006 | vault3 | OK |
| 9010 | rocky10-lxc-golden | OK (shutdown - TF template) |

**Evidence:**
```bash
root@pve-prod:~# ls -lh /mnt/pve/nas-prod-data/dump/ | grep 2026_04_11

# LXCs
vzdump-lxc-2001-2026_04_11-12_26_49.tar.zst  326M
vzdump-lxc-2002-2026_04_11-12_27_03.tar.zst  1.2G
vzdump-lxc-2003-2026_04_11-12_27_38.tar.zst  265M
vzdump-lxc-2004-2026_04_11-12_27_49.tar.zst  424M
vzdump-lxc-2005-2026_04_11-12_28_03.tar.zst  591M
vzdump-lxc-2006-2026_04_11-12_28_19.tar.zst  424M
vzdump-lxc-9010-2026_04_11-12_29_28.tar.zst  223M

# VMs
vzdump-qemu-1001-2026_04_11-12_19_28.vma.zst  1.7G
vzdump-qemu-1010-2026_04_11-12_20_38.vma.zst  3.0G
vzdump-qemu-1011-2026_04_11-12_21_28.vma.zst  3.3G
vzdump-qemu-1012-2026_04_11-12_22_17.vma.zst  3.4G
vzdump-qemu-1020-2026_04_11-12_23_10.vma.zst  6.3G
vzdump-qemu-1021-2026_04_11-12_24_27.vma.zst  5.6G
vzdump-qemu-1022-2026_04_11-12_25_37.vma.zst  5.9G
vzdump-qemu-9000-2026_04_11-12_28_33.vma.zst  1.5G
vzdump-qemu-9001-2026_04_11-12_29_01.vma.zst  1.5G
```

**Notes:**
- Golden images (9000, 9001, 9010) are shutdown templates used for Terraform provisioning
- Both environments backed up successfully before DR testing begins
- Dev has double backups (10:52 + 14:11) due to mid-backup crash incident (TS-PVE-015)
- Total backup size: ~35GB dev, ~30GB prod

---

## Live Backup Resilience (Observed 2026-04-13)

**Finding:** Proxmox snapshot-mode backup is **non-disruptive** to running VMs and Kubernetes workloads.

**Test Context:**
- During Task 4 pre-backup (vzdump snapshot mode)
- Observed "lock/suspend" phase on worker2 and worker3
- MariaDB pod on worker3, WordPress pods on worker1/worker2

**Evidence:**
```bash
# All nodes remained Ready during backup lock phase
[root@k8s-master1 ~]# kubectl get nodes -o wide
NAME                    STATUS   ROLES           AGE   VERSION
k8s-master1.lab.local   Ready    control-plane   16d   v1.35.3
k8s-master2.lab.local   Ready    control-plane   16d   v1.35.3
k8s-master3.lab.local   Ready    control-plane   16d   v1.35.3
k8s-worker1.lab.local   Ready    <none>          16d   v1.35.3
k8s-worker2.lab.local   Ready    <none>          16d   v1.35.3
k8s-worker3.lab.local   Ready    <none>          16d   v1.35.3

# Pods accessible during backup
[root@k8s-master1 ~]# kubectl exec -it wordpress-6d5cdf8c64-nwnn7 -n apps -- bash
# Successfully entered pod during worker1 backup

[root@k8s-master1 ~]# kubectl exec -it mariadb-0 -n database -- bash
# Successfully entered pod during worker3 backup
```

**Verified:**
- WordPress web UI remained accessible (login + browsing)
- MariaDB connections uninterrupted
- No pod restarts during backup
- Node status never changed from Ready

**Conclusion:** Proxmox vzdump snapshot mode is safe for production use during business hours. The brief "lock" phase does not disrupt running VMs or their workloads.

---

## Result: PASS

- Both environments backed up successfully
- Vzdump snapshot mode non-disruptive to running workloads
- Total duration: ~10 minutes per environment
