# CI/CD Infrastructure Playbooks (PoC v1 — archived)

> **Archived PoC v1 material.** This folder was the start of Jenkins-based CI/CD
> for the VMware PoC. Only the Jenkins install playbook was written before I
> shut the PoC down and rebuilt on GitHub Actions instead. The plans below are
> preserved as a record of what I had scoped at the time, NOT an active roadmap.
> See [`../../../README.md`](../../../README.md) for the retirement story —
> "Jenkins felt old" was one of the ten reasons I stopped.

---

## What's actually here

| File | Purpose |
|------|---------|
| `01-install_jenkins.yml` | Installs Jenkins master on the target VM |

Only one playbook was completed before the PoC was retired. Everything below
this line is the **original scoping plan** for follow-up playbooks that were
never written.

---

## Original scope (not implemented)

**Target VMs (PoC v1):**
- jenkins-master: 10.0.20.196

### Planned playbook categories (none beyond 01 completed)

- **Installation & Setup** — Jenkins master install (done as `01-install_jenkins.yml`), plugin management, agent nodes, build tools
- **Configuration Management** — job DSL, pipeline libraries, credentials via Vault, webhooks
- **Integration** — Git, container registry, Kubernetes deploys, Slack, Vault
- **Security** — access control, RBAC, secret scanning, artifact signing
- **Ops & Maintenance** — Jenkins home backup, plugin updates, build cleanup, tuning

### Planned naming convention

```
cicd-[NN]-[platform]-[description].yml
```

### Where these concerns went in the current project

- CI/CD moved from Jenkins to **GitHub Actions** — see `/.github/workflows/` and `/github/`.
- Secrets integration moved to OIDC-based AWS Secrets Manager fetching — see `/github/variables-secrets.md`.
- Kubernetes deploys moved to **Flux CD** (GitOps) — see `/kubernetes/`.
