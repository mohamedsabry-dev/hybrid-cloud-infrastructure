DR Test: ETCD Single Node Failure & Recovery
Date: 2026-04-11
Result: PASS
_____________________________________________________________________

[Info]
Domain: etcd / Kubernetes / Raft Quorum
Environment: DEV — 3 masters (kubeadm, etcd as static pods)
Triggered by: Need to verify etcd quorum survives single node loss
  and test recovery via cluster sync (not S3 restore)

_____________________________________________________________________

[Planned Scope]

Stop etcd on one master, verify 2/3 quorum holds. Then escalate:
delete etcd data entirely, recover the node by removing and re-adding
as a new member. This tests the cluster sync path — single node
recovery where the node downloads data from the healthy cluster.

Note: in kubeadm clusters, etcd runs as a static pod. Stop it by
moving the manifest (`mv /etc/kubernetes/manifests/etcd.yaml /tmp/`),
not systemctl.

_____________________________________________________________________

[Pre-State]

All 3 masters healthy, etcd 3/3 members started. Target: master3
(10.0.61.12, member ID d52dc5d621c3892f).

_____________________________________________________________________

[Test 1.1 — Stop etcd on master3 (quorum test)]

Action:
  ```
  mv /etc/kubernetes/manifests/etcd.yaml /tmp/
  ```

What happened:
  2/3 quorum maintained — cluster kept operating. master3 went NotReady
  (lost local API server → etcd connection). Workers briefly showed
  NotReady for ~5 seconds during failover, then self-healed.

  ```
  etcdctl endpoint health --cluster
  https://10.0.61.10:2379 is healthy: took = 7.9ms
  https://10.0.61.11:2379 is healthy: took = 8.4ms
  https://10.0.61.12:2379 is unhealthy: context deadline exceeded
  ```

  Resource impact on surviving masters: memory jumped ~80% → ~88%.
  kubectl commands had 2-3s latency during failover. Remediation pod
  rescheduled from master3 to master1.

What this tells me:
  Same quorum math as Vault Raft — 2/3 = operational but fragile
  (failure tolerance drops to 0). Memory spike on survivors matters —
  masters need headroom for failover scenarios.

_____________________________________________________________________

[Test 1.2 — Delete etcd data and recover via cluster sync]

Why this test: stopping etcd is clean — what if the data is gone?

Action:
  ```
  rm -rf /var/lib/etcd
  ```
  Then recover by removing the broken member and re-adding as new:
  ```
  # From healthy master:
  etcdctl member remove d52dc5d621c3892f
  etcdctl member add k8s-master3.lab.local --peer-urls=https://10.0.61.12:2380
  # New member ID: e0a1c396a5ca70ba (different from original — expected)

  # On master3: verify initial-cluster-state=existing in manifest, then:
  mv /tmp/etcd.yaml /etc/kubernetes/manifests/
  ```

What happened:
  etcd on master3 started, synced data from cluster leader, rejoined
  as healthy member. All 3 endpoints healthy again.

  Node stayed NotReady after etcd recovered — required kubelet restart:
  ```
  systemctl restart kubelet
  ```
  After that, master3 went Ready, all 6 nodes healthy.

What this tells me:
  Single node data loss = cluster sync recovery, not S3 restore. The
  node downloads everything from the leader. S3 restore is only for
  full cluster failure (all 3 etcd nodes dead). Key gotchas:
  - `--initial-cluster-state=existing` must be set before rejoining
  - Member ID changes on re-add (normal)
  - Kubelet restart often needed after etcd recovery

_____________________________________________________________________

[Recovery]

  Full cluster healthy: 3/3 etcd members, 6/6 nodes Ready, all pods
  Running. Total test duration ~25 minutes.

_____________________________________________________________________

[Findings]

1. 2/3 etcd quorum = operational. Same pattern as Vault Raft — majority
   is enough but failure tolerance drops to 0. Workers briefly blipped
   NotReady (~5s) during failover, then self-healed.

2. Single node recovery uses cluster sync, not S3 restore. Remove the
   dead member, re-add it, restore the manifest with
   `initial-cluster-state=existing`. The node syncs from leader.

3. Memory headroom on masters matters. Surviving masters jumped ~8%
   during failover (80% → 88%). In production, don't run masters at
   capacity or failover itself can OOM.

4. Kubelet restart is often needed after etcd recovery. Node may stay
   NotReady even with healthy etcd — kubelet lost its API server
   connection and doesn't always reconnect cleanly.

5. If the etcd.yaml manifest itself is lost: copy from another master
   (edit node-specific IPs), or regenerate via `kubeadm init phase etcd
   local`, or restore from Proxmox backup. All three paths work.

_____________________________________________________________________

[References]

- etcd-backup-s3-validation.md — S3 backup pipeline (for full cluster restore)
- master-2of3-down.md — master node failure (broader scope)
- troubleshooting/kubernetes/ — related TS cases for etcd recovery
