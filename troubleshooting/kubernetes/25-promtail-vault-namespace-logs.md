# TS-K8S-025 | 2026-04-11 | PLACEHOLDER

## 1. Context
- System: Promtail / Loki / Vault
- Environment: k8s-dev cluster
- Related components: Promtail DaemonSet, Vault namespace, Loki
- Discovered during: DR Task 1 - Pod Kill testing
- Related Cases:
  - DR Task 1 RESULTS — Pod kill testing where issue was observed

---

## 2. Issue

**Symptom:** Promtail not collecting logs from Vault namespace during DR testing.

**Status:** NOT YET INVESTIGATED

**Placeholder:** This case was identified during DR Task 1 pod kill testing but has not been fully investigated yet.

---

## 3. Analysis

TODO: Investigation pending

---

## 4. Root Cause

TODO: Pending investigation

---

## 5. Solution

TODO: Pending investigation

---

## 6. Solution Risk

TODO: Pending investigation

---

## 7. Impact After Fix

TODO: Pending investigation

---

## 8. Notes

### Discovery context

During DR Task 1 pod kill testing, it was observed that Promtail was not collecting logs from the Vault namespace. This needs further investigation to determine:

1. Is this a configuration issue?
2. Is Vault namespace excluded from Promtail scraping?
3. Are there permission issues preventing log collection?

### Next steps

- [ ] Check Promtail configuration for namespace exclusions
- [ ] Verify Promtail can access Vault pod logs
- [ ] Check if Vault pods have special log configurations
- [ ] Review Loki for any Vault namespace logs

---

## 9. Workaround

None documented yet.
