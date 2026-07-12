Skill 7 — Terraform (7 questions)
==================================

Format: Standard questions only. Project examples are ammunition.
Your 2-tier IAM split, S3+DynamoDB backend bootstrap, dev/prod tree
separation, lifecycle ignore_changes on secrets, golden VM template
protection, mixed-region prod, Proxmox provider quirks — inject when earned.

---

1. What is Terraform state and why is it important?

   Coverage check:
   - state file maps config to real-world resources
   - how Terraform uses state for plan/apply decisions
   - sensitive data in state (why state must be secured)
   - terraform state list, show, mv, rm
   - state as source of truth vs cloud reality

2. How do you manage Terraform in a team — backends, locking, concurrent access?

   Coverage check:
   - remote backend (S3 + DynamoDB for AWS)
   - state locking — prevents concurrent applies
   - lock info and force-unlock
   - encryption at rest for state
   - backend configuration and initialization
   - terraform_remote_state data source for cross-module references

3. How do you handle secrets in Terraform?

   Coverage check:
   - sensitive variables (sensitive = true)
   - never commit .tfvars with secrets
   - Vault integration, SSM Parameter Store, Secrets Manager
   - secrets still appear in state file (backend encryption matters)
   - lifecycle { ignore_changes } to avoid overwriting externally-managed secrets

4. How do you manage multiple environments — dev, staging, prod?

   Coverage check:
   - workspaces vs directory separation (pros/cons of each)
   - separate state files per environment
   - variable files per environment (.tfvars)
   - preventing cross-environment state access
   - when workspace isolation is not enough (separate backends)

5. What is drift and how does Terraform detect and handle it?

   Coverage check:
   - drift = real resource differs from state
   - terraform plan shows drift
   - terraform refresh / refresh-only plan
   - terraform import (bringing existing resources under management)
   - import block (v1.5+)
   - resource lifecycle rules (prevent_destroy, create_before_destroy, ignore_changes)
   - what happens when you remove a resource from .tf but it exists in AWS

6. How do you structure Terraform code — modules, variables, expressions?

   Coverage check:
   - root module vs child modules
   - module sources (local, registry, git)
   - input variables, output values
   - count vs for_each (when to use each, index shift problems with count)
   - data sources vs resources
   - depends_on (implicit vs explicit dependencies)
   - locals for computed values
   - provider configuration, version constraints, aliases
   - provisioners as last resort (local-exec, remote-exec, null_resource)

7. Your state file is corrupted or locked. How do you recover?

   Coverage check:
   - identifying the problem (state shrunk, empty, locked, desync)
   - force-unlock (when safe, when dangerous)
   - restoring from S3 versioning
   - terraform import to rebuild state
   - terraform state pull / push
   - preventing corruption (locking, no cancelled mid-apply workflows)
   - state backup before destructive operations
