Skill 15 — Backup & DR (6 questions)
======================================

Format: Standard questions only. Project examples are ammunition.
Your etcd backup pipeline (CronJob→Vault→AWS STS→S3), Proxmox vzdump
retention change story, quorum loss recovery, Vault Raft rebuild,
FreeIPA→Vault→K8s circular dependency break, 17 DR test scenarios,
remediation pod auto-recovery — inject when the bridge is earned.

---

1. What is RPO and RTO? How do you determine them for a system?

   Coverage check:
   - RPO (Recovery Point Objective) — how much data loss is acceptable
   - RTO (Recovery Time Objective) — how long downtime is acceptable
   - MTTR (Mean Time To Recovery)
   - how RPO drives backup frequency
   - how RTO drives architecture (hot/warm/cold, automation level)
   - cost vs recovery speed tradeoff
   - different RPO/RTO for different components in same system

2. Explain your backup strategy — what, how, and how often.

   Coverage check:
   - full vs incremental vs differential backups
   - 3-2-1 rule (3 copies, 2 media types, 1 offsite)
   - GFS rotation scheme (Grandfather-Father-Son)
   - backup retention policies
   - crash-consistent vs application-consistent backups
   - database backup considerations (quiesce, dump vs snapshot)
   - backup monitoring and alerting (did it run? did it succeed? is it growing?)
   - immutable backups (ransomware protection)

3. How do you test your disaster recovery plan?

   Coverage check:
   - tabletop exercise (walk through on paper)
   - component-level test (restore one service)
   - full simulation (restore everything, validate)
   - regular schedule for DR tests
   - documenting results and gaps found
   - validating backup integrity before you need it
   - chaos testing (intentionally break things to verify recovery)

4. A restore failed. How do you troubleshoot?

   Coverage check:
   - is the backup file intact? (checksum, size, corruption)
   - version mismatch (backup from version X, restoring to version Y)
   - permissions and access (can the restore tool reach the backup location?)
   - space (enough disk for restore?)
   - dependency order (restore database before application)
   - partial restore vs full restore options
   - fallback to older backup if latest is corrupted

5. What's the difference between hot, warm, and cold DR sites?

   Coverage check:
   - hot site: fully running, real-time replication, instant failover
   - warm site: infrastructure ready, data periodically synced, hours to activate
   - cold site: empty infrastructure, backups only, days to activate
   - cost vs recovery time tradeoff
   - failover vs failback procedures
   - cross-region replication (cloud context)
   - active-active vs active-passive

6. Walk me through a cascading failure — how does one component failure
   affect dependent systems, and how do you recover in the right order?

   Coverage check:
   - dependency mapping (what depends on what)
   - recovery order matters (DNS before auth before secrets before apps)
   - circular dependency detection and breaking
   - what still works when master nodes are down
   - data consistency during partial recovery
   - communication during cascading failures
   - post-recovery validation (don't declare victory too early)
