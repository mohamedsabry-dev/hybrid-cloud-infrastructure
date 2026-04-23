# Mac Mini Workstation

**Machine:** Mac Mini (Apple Silicon ARM64)
**Role:** Self-hosted GitHub Actions runner + local development + operator workstation for the hybrid-cloud platform.

This folder holds everything specific to the Mac Mini's role in the platform:
setup guides for the runner and the dev tooling, persistent-route configuration
for reaching on-prem networks, and SSH config templates for VPN + GitHub.

---

## Files in this folder

```
workstation/
├── README.md                                # This file — scope + navigation
├── github-runner-setup-guide.txt            # Install + configure the self-hosted runner
├── terraform-provider-mirror-guide.txt      # Local Terraform provider cache
├── route-setup/                             # Persistent route to 10.0.0.0/8 (fallback)
│   ├── README.md                            # Folder scope
│   ├── route-setup-guide.txt                # Install / verify / uninstall commands
│   ├── add-route.sh                         # Route add script (used by launchd)
│   ├── install-route.sh                     # Installer for persistent route
│   └── com.local.route10.plist              # launchd service definition
└── ssh-wg/                                  # SSH config for VPN + GitHub
    ├── README.md                            # Folder scope + usage
    └── ssh-config-template                  # SSH config entries (append to ~/.ssh/config)
```

---

## What lives here (by concern)

| Concern | File / folder |
|---------|---------------|
| GitHub Actions runner install | [`github-runner-setup-guide.txt`](github-runner-setup-guide.txt) |
| Terraform provider mirror | [`terraform-provider-mirror-guide.txt`](terraform-provider-mirror-guide.txt) |
| Persistent 10.x route (fallback) | [`route-setup/`](route-setup/) |
| SSH config for VPN + GitHub | [`ssh-wg/`](ssh-wg/) |
| Local `kubectl` / `flux diff` access | [`../kubernetes/docs/local-kubectl-flux-setup.md`](../kubernetes/docs/local-kubectl-flux-setup.md) |

---

## Core dependencies installed on this machine

Tooling expected on the Mac Mini for the runner + operator workflows:

- Terraform, Ansible, AWS CLI, Docker, Node.js, Python, PowerShell, sshpass
- kubectl, flux, kustomize, kubeconform (for pre-push validation — see kubectl/flux guide)

Installed via `brew`. The specific install line lives in each guide where needed.

---

## Related

- [`../github/runner-mac-mini.md`](../github/runner-mac-mini.md) — why the runner is self-hosted on the Mac Mini; tool rationale
- [`../github/variables-secrets.md`](../github/variables-secrets.md) — GitHub secrets + variables consumed by workflows
- [`../deployment-docs/03-github-setup-guide.md`](../deployment-docs/03-github-setup-guide.md) — GitHub-side setup (OIDC, secrets, runner registration)
- [`../deployment-docs/00-network-setup-guide.md`](../deployment-docs/00-network-setup-guide.md) — router-level network + routing
- [`../kubernetes/docs/local-kubectl-flux-setup.md`](../kubernetes/docs/local-kubectl-flux-setup.md) — full kubectl + flux pre-push validation setup
