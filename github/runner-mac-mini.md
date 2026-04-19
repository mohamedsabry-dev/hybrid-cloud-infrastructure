# Mac Mini Self-Hosted Runner

| Setting | Value |
|---------|-------|
| Runner Name | Mohameds-Mac-mini |
| Location | ~/WorkSpace/actions-runner |
| Status | Active |

---

## Platform Information

| Setting | Value |
|---------|-------|
| OS | macOS (Darwin 25.3.0) |
| Architecture | ARM64 (Apple Silicon) |
| Machine | Mac Mini |
| Runner Version | v2.331.0 |
| Working Directory | ~/WorkSpace/actions-runner/_work |
| Cache Directory | ~/WorkSpace/actions-runner/_cache |

## Why I run Terraform on a self-hosted Mac Mini (not a GitHub-hosted runner)

GitHub-hosted runners can't reach my Proxmox host directly — Proxmox lives
on-premises behind a home router, not on the public internet. Anything that
needs to talk to the Proxmox API (Terraform for all the VMs and LXCs) has to
run from a machine that already sits on my home network. The Mac Mini is
that machine.

A few more reasons this turned out to be the right fit:

- **Local provider mirror.** Terraform providers (aws, bpg/proxmox, external)
  are cached at `$HOME/.terraform.d/providers-mirror` — roughly 650MB of AWS
  provider alone. Pulling from the mirror every `terraform init -upgrade` is
  instant. On a GitHub-hosted runner I would re-download them on every job.
- **No minute-billing pressure.** A 3-minute review-window sleep in every
  apply would burn paid minutes on a GitHub runner. On the Mac Mini it's
  free time, so the "pause and let me inspect the plan" pattern is cheap.
- **Split of concerns with the internal runners.** Mac Mini talks outward
  (AWS, GitHub, Proxmox API from outside) and handles Terraform. The
  `{env}-local-runner` LXCs talk inward (Ansible to the fleet). Two
  different network positions, two different runners. See
  `internal-runners-setup.md` for the internal side.

Trade-off: the Mac Mini has to stay powered on and online for CI to work.
Acceptable for my setup; would not be acceptable for a team environment.

---

## Runner Labels

| Label | Description |
|-------|-------------|
| `self-hosted` | Identifies as self-hosted runner |
| `macOS` | Operating system |
| `ARM64` | CPU architecture |
| `mac-mini` | Custom label for easy reference |

**Workflow Usage:**
```yaml
# Recommended (simple, clear)
runs-on: mac-mini

# Alternative (explicit labels)
runs-on: [self-hosted, macOS, ARM64]
```

---

## Installed Tools

### Dependencies

| Tool | Version | Purpose |
|------|---------|---------|
| Python | 3.14.2 | Automation scripts |
| Docker | 29.1.5 | Container builds |
| AWS CLI | 2.33.4 | AWS resource management |
| Terraform | 1.14.3 | Infrastructure provisioning |
| Ansible | 2.20.1 | Configuration management |
| Node.js | 25.4.0 | GitHub Actions runner |
| PowerShell | 7.5.4 | VMware/Windows automation |
| sshpass | 1.10 | SSH password authentication for LXC provisioning |

### Provider Mirror

Cached locally at `$HOME/.terraform.d/providers-mirror`

| Provider | Version | Size |
|----------|---------|------|
| hashicorp/aws | v6.28.0 | ~650MB |
| bpg/proxmox | v0.96.0 | - |
| hashicorp/external | v2.3.4 | - |

---

## Validation

| Check | Command/Action | Expected |
|-------|----------------|----------|
| Runner Status | GitHub > Settings > Actions > Runners | Shows "Idle" |
| Service Running | `./svc.sh status` | "Running" |
| Auto-start Test | Reboot Mac, check runner status | Auto-starts |
| Workflow Test | Run sample workflow | Executes OK |
