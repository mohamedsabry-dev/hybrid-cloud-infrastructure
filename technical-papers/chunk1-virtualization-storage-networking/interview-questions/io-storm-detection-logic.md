IO Storm Watchdog — Detection Logic, Source Identification, and Automated Response
====================================================================================

Question:
  You mentioned an IO storm watchdog script on your Proxmox host.
  Walk me through the detection logic. How do you identify which VM
  is causing the storm? Why don't you just look for the VM with the
  highest IO? What happens after detection?

---

The problem:

  6 k8s VMs + FreeIPA share one NVMe (no per-VM IO isolation).
  When one VM saturates the NVMe (etcd compaction, heavy pod, runaway
  process), all other VMs start waiting for IO. Cluster-wide slowdown.
  This happened in TS-PVE-017 — 8-hour investigation, all VMs hung.

  After that incident, IO throttle limits were applied per VM via
  Terraform. But throttles don't prevent storms — they limit blast
  radius. A VM can still hit its limit and cause cascading pressure.

---

The counter-intuitive detection:

  The VM causing the storm has LOW IO pressure, not high.

  IO pressure = how much time the VM is WAITING for IO.
  Victims are waiting → high IO pressure.
  Source is not waiting → its IO is going through → low IO pressure.
  The source is the one hogging the NVMe while everyone else queues.

  But low IO alone doesn't mean "source." FreeIPA might have low IO
  because it's barely doing anything. So the script also checks CPU:
    Low IO + high CPU = actively working hard + IO going through
    Low IO + low CPU = just idle, not involved

---

Rule 1 — IO storm (system-wide cascade):

  Every 30 seconds:
    1. Read IO pressure for all 7 VMs via pvesh API
    2. Count victims: IO pressure > 15% = suffering
    3. If 3+ victims → system-wide distress confirmed
    4. Find source: loop k8s VMs, look for IO < 2% AND CPU > 40%
    5. Track suspect in state file — if same VM hits 4 consecutive
       checks (2 min sustained) → confirmed source
    6. qm reset <vmid> → collect evidence snapshot → email alert
    7. 3-min cooldown → 4 clean recovery checks → recovery email

  Safety: one clean check (victim_count drops below 3) resets all
  suspects. Prevents acting on transient spikes.

  Why 4 checks (2 min): a single spike could be vzdump starting,
  etcd snapshot, or normal burst. 2 minutes of sustained pattern
  means something is genuinely stuck.

---

Rule 2 — CPU stuck (contained storm):

  Fires ONLY when Rule 1 didn't trigger (no system-wide distress).

  Scenario: IO throttle is working — other VMs are fine. But one VM
  is stuck at CPU > 300% (4 vCPUs near max). The throttle contained
  the blast to just that VM, but the VM itself is dead — spinning in
  a loop, not recovering.

  Same pattern: 4 consecutive checks → reset → cooldown → verify.

  Why 300%: each vCPU can do 100%. 4 vCPUs = 400% max. At 300%+
  sustained for 2 minutes, the VM is burning 3+ cores doing nothing
  useful — it's stuck, not just busy.

---

Why two separate rules:

  Rule 1: "the whole cluster is suffering, find who's causing it"
    → system-wide IO pressure, source has low IO + high CPU

  Rule 2: "one VM is stuck but everyone else is fine"
    → IO throttle contained the blast, but the source VM is dead

  They can't both fire. Rule 2 only runs when Rule 1's condition
  (3+ victims) is false. Different failure modes, same response.

---

Post-reset flow:

  After qm reset → VM reboots → kubelet starts → registers with API
  server → pods rescheduled → cluster stabilizes.

  Script waits 3 min cooldown (don't check during VM boot — readings
  would be meaningless). Then 4 clean checks (2 more min). If all
  clean → sends recovery email with readings. If still bad → logs
  warning but doesn't reset again (avoids reset loop).

---

What the evidence email contains:

  - Which VM was reset and why
  - IO pressure + CPU reading that triggered it
  - How long the pattern was sustained
  - Snapshot of ALL VMs' IO readings at time of reset
  - Expected recovery time (~7 min for cluster stabilization)

---

Related:
  TS-PVE-017: the original 8-hour IO storm investigation that led to
    building this watchdog + applying per-VM IO throttle limits
  TS-PVE-023: daemon vs cron misconfiguration (same script category)
