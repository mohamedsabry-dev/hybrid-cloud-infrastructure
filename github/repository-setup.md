# GitHub Repository Setup

**Repository:** hybrid-cloud-infrastructure
**Platform:** GitHub
**URL:** https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure

---

## Branch Strategy

| Branch | Purpose | Workflow Trigger |
|--------|---------|------------------|
| `main` | Clean merges only (no workflow) | None |
| `dev` | Development infrastructure deploys | Infrastructure-dev |
| `prod` | Production infrastructure deploys | Infrastructure-prod |
| `dev-security` | Development IAM/security changes | TerraformAdmin-dev |
| `prod-security` | Production IAM/security changes | TerraformAdmin-prod |

---

## Branch Protection

| Branch | Merge Approval | CI Checks | Audit Trail |
|--------|----------------|-----------|-------------|
| `main` | Required | Required | Enabled |
| `prod` | Required | Required | Enabled |
| `dev-security` | Required | - | Enabled |
| `prod-security` | Required | - | Enabled |

---

## Workflow

```
dev branch (push) ──► CI runs ──► PR to main ──► Approval ──► Merge
```
