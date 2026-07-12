Skill 2 — Troubleshooting / RCA (5 questions)
===============================================

Format: Standard questions only. Project examples are ammunition
you inject into answers to bait follow-ups — not separate questions.
Your 15 real incidents (etcd crash, Flux retry storm, USB flapping,
Grafana NFS corruption, Terraform state corruption, etc.) are what
you inject when answering these — not a checklist to recite.

---

1. Describe your troubleshooting methodology when something breaks.

   Coverage check:
   - structured approach (observe → hypothesize → test → confirm)
   - log-first vs metric-first decision
   - isolating layers (network vs disk vs app)
   - binary search / divide-and-conquer elimination
   - when to escalate vs keep digging
   - documenting findings as you go
   - reproducing intermittent issues

2. A production service is down. Walk me through your first 5 minutes.

   Coverage check:
   - triage (impact scope, who's affected, severity classification)
   - quick checks (process running? logs? disk? memory? network?)
   - rollback decision (was there a recent change?)
   - communication (who do you notify, when)
   - parallel vs sequential investigation
   - prioritizing when multiple things break simultaneously

3. A change worked in staging but broke production. How do you investigate?

   Coverage check:
   - environment diff (config, data volume, scale, network topology)
   - feature flags, dependency versions
   - DNS/endpoints differences
   - load patterns and traffic shape
   - database state drift
   - "what's different" systematic checklist
   - staging-vs-prod trust assumptions

4. How do you distinguish between a network issue, a disk issue,
   and an application issue?

   Coverage check:
   - layer isolation technique
   - tools per layer (ping/traceroute vs iostat/dmesg vs logs/strace)
   - symptoms that cross layers (app timeout from disk IO from network storage)
   - following the dependency chain across integrated systems
   - resource exhaustion patterns (connection pools, file descriptors, disk)

5. How do you perform root cause analysis and write a post-mortem?

   Coverage check:
   - 5-whys technique
   - timeline reconstruction
   - contributing factors vs root cause (not always one thing)
   - blameless culture
   - action items (prevent vs detect vs mitigate)
   - post-mortem structure (summary, impact, timeline, root cause, actions)
   - sharing findings / preventing recurrence
