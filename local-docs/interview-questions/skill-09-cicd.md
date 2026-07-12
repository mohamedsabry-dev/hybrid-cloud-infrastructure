Skill 9 — CI/CD (6 questions)
==============================

Format: Standard questions only. Project examples are ammunition.
Your 31 GitHub Actions workflows, OIDC federation, plan-gate with
3-minute sleep, concurrency locks via repo vars, keytab transfer
pipeline, self-hosted runner setup, sshpass→key-based transition,
always()+||true cleanup — inject when the bridge is earned.

---

1. Walk me through a CI/CD pipeline you've built end-to-end.

   Coverage check:
   - trigger (push, PR, dispatch, schedule)
   - stages (lint, build, test, deploy)
   - artifact flow between stages
   - environment separation (dev, staging, prod)
   - approval gates and manual intervention points
   - pipeline as code (YAML in repo, not UI-configured)
   - caching and optimization (dependency cache, layer cache)
   - notifications on failure

2. What's the difference between continuous integration, delivery, and deployment?

   Coverage check:
   - CI — merge frequently, automated build + test
   - CD (delivery) — always deployable, manual trigger to production
   - CD (deployment) — fully automated to production
   - where most teams actually sit on this spectrum
   - prerequisites for full continuous deployment (test coverage, monitoring, rollback)

3. How do you handle secrets in a CI/CD pipeline?

   Coverage check:
   - never hardcode, never commit
   - platform secret stores (GitHub Secrets, GitLab CI Variables)
   - OIDC federation (eliminate long-lived credentials entirely)
   - masking in logs
   - secret rotation strategy
   - runtime secret injection vs build-time secrets
   - cleaning up secrets after use (kdestroy, file deletion)

4. What are deployment strategies — rolling, blue-green, canary?

   Coverage check:
   - rolling update (gradual replacement, some old + some new)
   - blue-green (two environments, switch traffic)
   - canary (small percentage first, monitor, expand)
   - recreate (all down, all up — simplest, has downtime)
   - tradeoffs (speed, risk, resource cost, rollback complexity)
   - how each integrates with load balancers and health checks
   - rollback mechanisms for each strategy
   - feature flags as alternative to deployment strategies

5. A deployment failed in production. How does your pipeline handle it?

   Coverage check:
   - automated rollback vs manual decision
   - health checks and readiness gates
   - monitoring integration (alerts trigger rollback?)
   - database migration rollback (forward-only vs reversible)
   - incident communication (who gets notified, how)
   - post-incident analysis (what broke, how to prevent)
   - GitOps rollback (revert the git commit)

6. What is GitOps and how does it differ from traditional push-based CI/CD?

   Coverage check:
   - push-based: CI pipeline pushes changes to target
   - pull-based: agent in target pulls from git (Flux, ArgoCD)
   - git as single source of truth
   - reconciliation loop and drift correction
   - benefits (audit trail, rollback = git revert, declarative)
   - challenges (secrets, database migrations, imperative operations)
   - when GitOps fits vs when push-based is better
