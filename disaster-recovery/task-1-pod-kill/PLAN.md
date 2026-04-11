# Task 1: Single Pod Kill

**Trigger:** Kill 1 pod for each critical component.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.
**Status:** IN PROGRESS (3 of 7 components tested)

---

### Scenario 1.1 — Single Pod Kill
Kill 1 pod for each critical component.

- Action: Kill pod (restart, recreate, force delete) for each:
  - [x] WordPress — 9s recovery, zero downtime
  - [x] MariaDB — 9s recovery, 5s app downtime, InnoDB crash recovery worked
  - [x] vault-agent-injector — 22s recovery, race condition found + FIX APPLIED
  - [ ] ingress-nginx
  - [ ] flux
  - [ ] prometheus
  - [ ] exporters
- Check: Pod restarts automatically
- Check: Service remains available (or recovers quickly)

**Critical Fix Applied:** vault-agent-injector `replicas: 2` with anti-affinity
- See: [RESULTS.md](RESULTS.md#race-condition-test--vault-injector--wordpress-simultaneous-delete)

→ Run checklist.

---

### Observation Checklist (run after every scenario):
- [x] WordPress accessible (browse + upload)
- [x] DB integrity (no duplicate conflicts, no orphaned transactions)
- [ ] Flux reconciliation status
- [x] Vault sealed/unsealed status
- [x] Pod scheduling and priority behavior
- [ ] Grafana: CPU, mem, pod restarts on remaining nodes
- [ ] Prometheus scraping targets reachable
