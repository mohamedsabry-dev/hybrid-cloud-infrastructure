# Ansible layer — design notes and reasoning

Why the Ansible side of this project is structured the way it is. Reads as a narrative, not a runbook — for the playbook map, group topology, shared architecture, and navigation see [`README.md`](README.md).

---

## Why dev and prod are kept as separate folders

I chose to keep `dev/` and `prod/` as two fully separate folders, rather than using a single codebase with env tags or flags to switch between environments. This was a deliberate decision I made while building the project.

**Reason:** I was learning Ansible at the same time I was building this infrastructure (the same applies to the rest of the stack — Terraform, Kubernetes, etc.). Having dev and prod fully separated meant I could freely change, rewrite, or experiment inside `dev/` without any risk of it leaking into `prod/` by accident. During a learning phase, that safety mattered more to me than the usual DRY / single-source-of-truth argument.

**Trade-off:** yes, this means some files are duplicated between `dev/` and `prod/`. I am aware of that. Once I am more comfortable with Ansible and the prod side has stabilized, I may consolidate into a single role set driven by `group_vars/{env}.yml`. For now, the split stays — it let me move fast on dev without fear of breaking prod.

The same approach is applied across the rest of the repo (`terraform/`, `kubernetes/`, `.github/`) — dev and prod live side-by-side as separate trees, not merged behind a single variable. Same reasoning spelled out in [`../terraform/DESIGN.md`](../terraform/DESIGN.md).
