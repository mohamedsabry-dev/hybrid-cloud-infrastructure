================================================================================
KUBERNETES HOMELAB — SELF-HEALING BLUEPRINT (UPDATED)
================================================================================


--------------------------------------------------------------------------------
LAYER 1 — POD LEVEL SELF-HEALING
--------------------------------------------------------------------------------

Failure type:
Pod stuck, frozen, crash looping, NFS mount hang, application deadlock. Node
appears healthy. Kubernetes reports Ready. Silent failure — the most dangerous
type because nothing rings an alarm automatically.

Detection mechanism:
Liveness probe configured on every pod spec. Probes every 30 seconds, times out
after 10 seconds, fails after 3 consecutive failures, then Kubernetes kills and
restarts the pod automatically.

Sequence:
  Pod liveness probe fails 3 consecutive times
    ↓
  Kubernetes kills pod automatically
    ↓
  Pod restarts on same or different node
    ↓
  If restart fixes it → silent recovery, no human needed
    ↓
  If pod keeps restarting → CrashLoopBackOff state
    ↓
  Prometheus detects high restart rate metric
    ↓
  Alertmanager fires → email notification to human

Guard conditions:
- Liveness probe timeout must be shorter than NFS timeo mount option —
  otherwise probe hangs before timing out, defeating the mechanism entirely
- initialDelaySeconds must be long enough for application startup — setting it
  too short causes healthy pods to be killed during boot

Prometheus alert rule:
Fire when restart count exceeds threshold within a time window. Catches
recurring failures that liveness probe alone cannot permanently fix.

Considerations:
- Every Deployment and StatefulSet must have liveness probe configured, no
  exceptions
- NFS mount options soft, timeo=30, retrans=3 must be set — hard mounts cause
  probes to hang indefinitely
- This layer requires zero external tooling — purely Kubernetes native
- Most silent failures resolve here without any human awareness


--------------------------------------------------------------------------------
LAYER 2 — NODE LEVEL SELF-HEALING
--------------------------------------------------------------------------------

SUB-LAYER 2A — WORKER NODE RECOVERY
-------------------------------------

Failure type:
Worker node goes offline, NotReady, or unresponsive at VM level. Kubernetes
cannot schedule pods on it. Physical intervention required via Proxmox API.


DETECTION — INDEPENDENT INTERNAL LOOP
--------------------------------------

The remediation pod runs its own internal detection loop every 2 minutes,
directly calling kubectl get nodes. This is the primary and only reliable
trigger. It has zero dependencies on Prometheus, Alertmanager, or any component
living on worker nodes.

Why Alertmanager webhook is NOT used as the trigger:
- Prometheus lives on a worker node
- If the worker is severely degraded, Prometheus may also be struggling
- If Prometheus is down, Alertmanager receives no alerts and fires nothing
- Alertmanager webhook as a trigger creates a dependency chain that breaks
  precisely when you need healing the most
- Conclusion: the remediation pod must be self-sufficient for detection

Alertmanager and Prometheus role in this layer:
- Prometheus and Alertmanager are used for human notification only, not for
  triggering automation
- The remediation pod sends email notifications directly via SMTP — independent
  of the entire Prometheus stack
- If Prometheus is healthy, it provides additional observability and dashboards
  but is never in the critical path of the healing trigger

Why 20 minutes:
Short enough to recover quickly, long enough to avoid false positives from brief
network blips, planned reboots, or backup Stop-mode windows.


GUARD CONDITIONS — VERIFIED BEFORE EVERY STEP
----------------------------------------------

- Exactly 1 worker NotReady — if 2 or 3 workers down simultaneously, stop
  everything immediately, send human alert only. Mass failure indicates a
  network or infrastructure issue, not a single VM issue. Destructive operations
  on multiple nodes simultaneously would make things significantly worse.
- All 3 masters healthy and etcd quorum intact before any Proxmox operation
- Each step must complete its full wait period and health check before
  escalating — no shortcuts under any circumstance


GRADUATED RECOVERY SEQUENCE
----------------------------

  Remediation pod internal loop detects worker NotReady > 20 minutes
    ↓
  Pod verifies guard conditions
    ↓
  Pod starts internal state machine — runs entirely to completion internally
  No external triggers needed between steps

Step 1 — Graceful reboot
  Proxmox API: POST /nodes/{node}/qemu/{vmid}/status/reboot
  Pod waits 5 minutes internally
  Pod checks kubectl get nodes — worker Ready?
  If Ready → log recovery, send email notification, exit state machine
  If NotReady → advance to Step 2

Step 2 — Hard reset
  Proxmox API: POST /nodes/{node}/qemu/{vmid}/status/reset
  Pod waits 5 minutes internally
  Pod checks worker Ready?
  If Ready → log recovery, send email notification, exit state machine
  If NotReady → advance to Step 3

Step 3 — Full power cycle
  Proxmox API: POST /nodes/{node}/qemu/{vmid}/status/stop
  Pod waits 30 seconds
  Proxmox API: POST /nodes/{node}/qemu/{vmid}/status/start
  Pod waits 5 minutes internally
  Pod checks worker Ready?
  If Ready → log recovery, send email notification, exit state machine
  If NotReady → advance to Step 4

Step 4 — Backup restore
  Proxmox API: POST /nodes/{node}/qemu/{vmid}/status/stop
  Proxmox API: restore latest backup to same VMID
  Proxmox API: POST /nodes/{node}/qemu/{vmid}/status/start
  Pod waits 5 minutes for VM to boot
    ↓
  Worker boots from backup disk
  Kubelet starts automatically
  Kubelet finds existing client certificate in /var/lib/kubelet/pki/
  Certificate still valid — signed by cluster CA, 1 year lifetime
  Kubelet reconnects to API server using existing certificate
  Worker rejoins cluster automatically
    ↓
  Pod polls kubectl get nodes every 30 seconds
  If worker Ready within 15 minutes → log recovery, send email, exit
  If not Ready after 15 minutes → send human escalation alert, stop automation


WHY NO BOOTSTRAP TOKEN NEEDED AT RESTORE
-----------------------------------------

Critical design note. The bootstrap join token is used exactly once — during the
very first time a worker joins the cluster. After that, kubeadm issues the
kubelet a client certificate signed by the cluster CA, stored at
/var/lib/kubelet/pki/ on the worker VM disk. This certificate has a 1-year
validity period and kubelet rotates it automatically before expiry via the CSR
API — no human intervention required.

Since the backup contains the full VM disk including that certificate directory,
the restored worker boots with a valid certificate already present. Kubelet
starts, finds the certificate, and reconnects to the API server automatically.
No token generation, no Vault write, no join command needed.

  Bootstrap token → used once at first join → discarded forever
  Kubelet certificate → lives on disk → survives backup and restore → auto-rotates

The only scenario requiring a fresh bootstrap token is provisioning a completely
new worker that has never joined the cluster before.


REMEDIATION POD SPECIFICATION
------------------------------

Placement:
Master nodes only. Two reasons: firewall only allows master VLAN to reach
Proxmox management on port 8006, and workers cannot be trusted to heal
themselves. Enforced via nodeSelector for control-plane label AND toleration for
control-plane taint. Both are required together — neither alone is sufficient.

Replicas:
2 replicas. Covers the realistic scenario of one master going down while etcd
still has quorum. 3 replicas give false confidence — if two masters go down,
etcd loses quorum, the Kubernetes API dies, and no pod can operate regardless
of replica count. 2 is the correct and sufficient number.

Priority:
Highest PriorityClass in the cluster. Guaranteed QoS — resource requests must
equal resource limits. This pod must never be evicted under memory or CPU
pressure, especially critical during failure scenarios when the cluster is
already degraded.

Storage:
Zero storage dependency. No PVC, no NFS, no persistent volume of any kind.
The pod is entirely stateless. If NFS is down during a failure, the remediation
pod must still function without any degradation. This is a hard requirement.

Architecture:
  Remediation Pod
  ├── ConfigMap → Python recovery script mounted at runtime
  ├── ServiceAccount → RBAC permission for kubectl node status reads only
  ├── Vault agent sidecar → injects Proxmox API token as file at runtime
  └── Python script → internal detection loop + state machine + SMTP email

Trigger model:
The pod runs a continuous internal loop — no webhook, no external trigger. The
loop polls kubectl get nodes every 2 minutes, tracks NotReady duration
internally, and self-triggers the recovery state machine when the threshold is
crossed. The state machine runs entirely inside the pod with internal waits
between steps. Alertmanager webhook was considered and rejected as the primary
trigger due to its dependency on Prometheus being healthy on worker nodes.

Secret handling:
Vault stores the Proxmox API token scoped to worker VMIDs only with minimum
required permissions: VM.PowerMgmt, VM.Backup, VM.Audit. Token never hardcoded
anywhere. Retrieved fresh at runtime via Kubernetes ServiceAccount Vault auth.

Email notification:
Sent directly from the Python script via SMTP. Does not depend on Alertmanager
or Prometheus. Notifications sent at: recovery started, each step attempted,
recovery success with which step resolved it and how long it took, Step 4
timeout requiring human intervention, guard condition failure requiring human
investigation.

Firewall rule:
Source: master VLAN only
Destination: Proxmox management IP
Port: 8006 TCP
Action: Allow
Workers have no route to Proxmox management by design.


BACKUP CONSIDERATIONS
---------------------

- Workers use Stop mode backup — VM shuts down cleanly during backup, disk-only
  snapshot, no memory state included, cleanest possible restore point
- Brief Stop mode downtime is acceptable — pods reschedule to other two workers
  during backup window, cluster stays healthy
- Stop mode backup suspend duration is far too short to trigger Kubernetes node
  eviction — eviction requires 40 seconds of missed heartbeat minimum, then
  another 5 minutes before pods are moved
- Restore always to same VMID — preserves Terraform state integrity, no state
  drift, no manual terraform import needed
- Template clone approach was considered and rejected — creates new VMID, breaks
  Terraform state, requires manual reconciliation every time
- Snapshot mode memory inclusion is a VM Snapshot feature only — Proxmox backup
  jobs via vzdump never include RAM regardless of mode selected, so this concern
  does not apply to scheduled backup jobs


NOTIFICATION STRATEGY
---------------------

All notifications sent directly from remediation pod via SMTP — no Alertmanager
dependency:

  Recovery loop trigger     → email: worker NotReady detected, recovery starting
  Each step attempt         → email: which step, which worker, timestamp
  Recovery success          → email: which step resolved it, total time elapsed
  Step 4 timeout            → email: escalation required, human must intervene
  Guard condition failure   → email: multiple workers down, do not automate,
                                     human must investigate


--------------------------------------------------------------------------------
SUB-LAYER 2B — MASTER NODE RECOVERY
--------------------------------------------------------------------------------

Status: Acknowledged as a design consideration. NOT implemented as automation.

Reasoning:
Masters fail extremely rarely in practice. Workers fail regularly — they run
actual workloads under constant resource pressure. Masters run only lightweight
control plane components and sit mostly idle by comparison. Automating master
recovery introduces significant risk — etcd quorum management, member removal
and rejoin, split-brain scenarios — without meaningful operational benefit for
a homelab environment.

Decision:
Master node failures at the single-node level are handled manually. The
graduated restart steps (graceful reboot, hard reset, power cycle) could
theoretically be applied to masters following the same Proxmox API pattern, but
this is left as a future consideration only.

The one hard rule: if two masters go down simultaneously, etcd loses quorum, the
Kubernetes API becomes unresponsive, and no internal automation can act. This
scenario escalates directly to human intervention and is the motivation for the
Layer 3 external monitoring design described below.

Future consideration only:
A Lambda function in AWS could theoretically reach Proxmox via WireGuard VPN
and attempt graduated restarts on masters when the cluster API is unreachable.
This has been thought through architecturally but will not be implemented. The
maintenance flag pattern in SSM Parameter Store would be required to prevent
false triggers during planned homelab shutdowns. CloudWatch Synthetics canary
pinging the cluster API endpoint would serve as the external detection mechanism.
SNS email notification to human is the only action that will actually be wired
up if this layer is ever partially implemented.


--------------------------------------------------------------------------------
FULL FAILURE MATRIX
--------------------------------------------------------------------------------

Scenario                           | Layer | Action
-----------------------------------|-------|----------------------------------
Pod stuck / NFS hang               |   1   | Liveness probe auto-restart
Pod crash loop recurring           |   1   | Prometheus alert, email to human
1 worker down, 2 workers healthy   |   2A  | Remediation pod graduated sequence
2+ workers down simultaneously     |   2A  | STOP — guard condition blocks auto
                                   |       | Direct SMTP email to human only
1 master down, quorum intact       |  N/A  | Manual intervention by human
2+ masters down, quorum lost       |  N/A  | Manual intervention by human
                                   |       | Future: CloudWatch SNS notification
NFS server down                    |  1+2A | Liveness probe restarts pods
                                   |       | Email to human for NFS server itself
WireGuard tunnel down              |  N/A  | External monitoring future scope


--------------------------------------------------------------------------------
IMPLEMENTATION ORDER
--------------------------------------------------------------------------------

Phase 1 — Immediate (this week)
Deploy Prometheus and Grafana via kube-prometheus-stack Helm chart. Configure
node-exporter DaemonSet with master tolerations to cover all 6 nodes. Add LXC
static scrape targets for Vault, FreeIPA, NGINX and other external nodes.
Configure Alertmanager for human notification emails. Add liveness probes to all
existing pod specs — WordPress, MariaDB, and any others currently missing them.
Move Alertmanager to master nodes — stateless, no PVC, nodeSelector and
toleration applied, high PriorityClass and Guaranteed QoS.

Phase 2 — Next
Write Python remediation script with internal detection loop and graduated
recovery state machine. Create dedicated ServiceAccount with minimum RBAC —
node read access only. Create Proxmox API token scoped to worker VMIDs with
minimum permissions. Write Vault policy for remediation ServiceAccount. Configure
firewall rule: master VLAN to Proxmox port 8006 only. Create ConfigMap
containing the script. Deploy remediation pod with nodeSelector, toleration,
PriorityClass, Guaranteed QoS, Vault agent sidecar, zero storage. Test each
graduated step in isolation against a deliberately downed worker. Verify guard
conditions block action when multiple workers are down simultaneously.

Phase 3 — Future consideration only
CloudWatch Synthetics canary pinging cluster API endpoint. SSM Parameter Store
maintenance mode flag. SNS topic for email notification when cluster unreachable.
No automated Proxmox remediation — human notification only.


--------------------------------------------------------------------------------
SINGLE PRINCIPLE THAT TIES EVERYTHING TOGETHER
--------------------------------------------------------------------------------

Every layer exists because the layer above it has a blind spot. Liveness probes
cannot fix broken VMs. The remediation pod cannot act when masters are gone.
Each layer is designed specifically for the failures the layer above cannot see.

The remediation pod's independence from Prometheus and Alertmanager is not an
optimization — it is a requirement. A healing system that depends on the health
of the components it is meant to protect is not a healing system. It is a false
sense of security.

================================================================================
END OF DOCUMENT
================================================================================