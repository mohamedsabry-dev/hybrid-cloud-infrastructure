# Mac Mini Workstation Setup

**Machine:** Mac Mini (Apple Silicon ARM64)
**Role:** Self-hosted GitHub Actions runner + local development

---

## Quick Reference

| Component | Location/Command |
|-----------|------------------|
| GitHub Runner | `~/WorkSpace/actions-runner` |
| Provider Mirror | `~/.terraform.d/providers-mirror` |
| Route Service | `com.local.route10` |
| SSH Config | `~/.ssh/config` |

---

## 1. Install Dependencies

```bash
# Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Required tools
brew install python node terraform ansible awscli sshpass
brew install --cask docker powershell
```

| Tool | Purpose |
|------|---------|
| Python | Automation scripts |
| Docker | Container builds |
| AWS CLI | AWS resource management |
| Terraform | Infrastructure provisioning |
| Ansible | Configuration management |
| Node.js | GitHub Actions runner |
| PowerShell | VMware/Windows automation |
| sshpass | SSH password auth for LXC provisioning |

---

## 2. GitHub Actions Runner

### Install Runner

```bash
# Create runner directory
mkdir -p ~/WorkSpace/actions-runner && cd ~/WorkSpace/actions-runner

# Download latest runner (ARM64)
curl -o actions-runner-osx-arm64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-osx-arm64-2.331.0.tar.gz

# Extract
tar xzf ./actions-runner-osx-arm64.tar.gz
```

### Configure Runner

```bash
# Get token from: GitHub Repo > Settings > Actions > Runners > New self-hosted runner

./config.sh --url https://github.com/<ORG>/<REPO> \
  --token YOUR_RUNNER_TOKEN \
  --labels self-hosted,macOS,ARM64,mac-mini \
  --name Mac-Mini-Runner
```

### Setup Auto-Start Service

```bash
./svc.sh install
./svc.sh start
./svc.sh status
```

### Runner Labels

| Label | Usage |
|-------|-------|
| `mac-mini` | `runs-on: mac-mini` (recommended) |
| `self-hosted` | Identifies as self-hosted |
| `macOS` | Operating system |
| `ARM64` | CPU architecture |

---

## 3. Terraform Provider Mirror

Local cache speeds up `terraform init` (no internet download).

```bash
# Create mirror directory
mkdir -p ~/.terraform.d/providers-mirror

# Mirror required providers
terraform providers mirror -platform=linux_amd64 ~/.terraform.d/providers-mirror
terraform providers mirror -platform=darwin_arm64 ~/.terraform.d/providers-mirror
```

**Mirrored Providers:**
- hashicorp/aws
- bpg/proxmox
- hashicorp/external

**Usage in workflows:** Runner automatically uses mirror via `.terraformrc`

---

## 4. SSH Configuration

Copy template to `~/.ssh/config`:

```bash
cat ssh-wg/ssh-config-template >> ~/.ssh/config
```

**Template contents:**
```
Host wg-dev
    HostName <DEV_EIP>
    User ec2-user
    IdentityFile ~/WorkSpace/vpn-key-pair-dev.pem

Host wg-prod
    HostName <PROD_EIP>
    User ec2-user
    IdentityFile ~/WorkSpace/vpn-key-pair-prod.pem

Host github.com
    Hostname ssh.github.com
    Port 443
    User git
```

---

## 5. Internal Network Route (10.x)

Persistent route to reach on-premises 10.x networks via local gateway.

> **Note:** The `10.0.0.0/8` route is now configured one hop up — at the ISP router level — pointing to the MikroTik router (previously the ER605). The custom route script below is no longer needed on the Mac Mini in the current setup, but is kept here as a reference or fallback for situations where the ISP router can't hold the route (e.g. emergency local runs, different ISP hardware, or when the MikroTik is being rebuilt).

### Install

```bash
cd workstation/route-setup
sudo ./install-route.sh
```

### What It Does

1. Installs `/usr/local/bin/add-route.sh`
2. Creates launchd service `com.local.route10`
3. Adds route `10.0.0.0/8` via gateway on boot

### Verify

```bash
# Check route exists
netstat -rn | grep "^10"

# Check service
launchctl list | grep route10
```

### Uninstall

```bash
sudo launchctl unload /Library/LaunchDaemons/com.local.route10.plist
sudo rm /Library/LaunchDaemons/com.local.route10.plist
sudo rm /usr/local/bin/add-route.sh
```

---

## 6. Validation Checklist

| Check | Command | Expected |
|-------|---------|----------|
| Runner Status | GitHub > Settings > Actions > Runners | "Idle" |
| Service Running | `./svc.sh status` | "Running" |
| Route Active | `netstat -rn \| grep "^10"` | Shows 10.0.0.0/8 |
| SSH to WG | `ssh wg-dev` | Connects |
| Terraform | `terraform version` | Shows version |
| Docker | `docker ps` | No errors |

---

## Files in This Directory

```
workstation/
├── README.md                            # This setup guide
├── route-setup/                         # Persistent route to 10.0.0.0/8 (fallback — see §5)
│   ├── README.md                        # Local overview
│   ├── add-route.sh                     # Route add script (called by launchd)
│   ├── install-route.sh                 # Installer for persistent route
│   └── com.local.route10.plist          # launchd service definition
└── ssh-wg/                              # SSH config templates for VPN hosts
    ├── README.md                        # Local overview
    └── ssh-config-template              # SSH config entries for wg-dev / wg-prod / GitHub:443
```
