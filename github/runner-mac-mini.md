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
| OS | macOS (Darwin 25.2.0) |
| Architecture | ARM64 (Apple Silicon) |
| Machine | Mac Mini |
| Runner Version | v2.331.0 |
| Working Directory | ~/WorkSpace/actions-runner/_work |
| Cache Directory | ~/WorkSpace/actions-runner/_cache |

**Benefits:**
- Future on-premises deployment needs local access
- Self-hosted runner avoids GitHub-hosted runner limitations
- Local provider mirror speeds up Terraform init (no internet download)

---

## Runner Labels

| Label | Description |
|-------|-------------|
| `self-hosted` | Identifies as self-hosted runner |
| `macOS` | Operating system |
| `ARM64` | CPU architecture |

**Workflow Usage:**
```yaml
runs-on: [self-hosted, macOS, ARM64]
# or simply:
runs-on: macOS
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

## Installation Steps

### Step 1: Install Dependencies

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install python@3.14 node terraform ansible awscli sshpass
brew install --cask docker powershell
```

### Step 2: Download and Install GitHub Actions Runner

```bash
# Create runner directory
mkdir -p ~/WorkSpace/actions-runner && cd ~/WorkSpace/actions-runner

# Download latest runner (ARM64)
curl -o actions-runner-osx-arm64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-osx-arm64-2.331.0.tar.gz

# Extract
tar xzf ./actions-runner-osx-arm64.tar.gz
```

### Step 3: Configure Runner with Repository Token

```bash
# Get token from: GitHub Repo > Settings > Actions > Runners > New self-hosted runner

# Configure runner with labels
./config.sh --url https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure \
  --token YOUR_RUNNER_TOKEN \
  --labels self-hosted,macOS,ARM64 \
  --name Mohameds-Mac-mini
```

### Step 4: Setup Runner as Auto-Start Service (launchd)

```bash
# Install as service
./svc.sh install

# Start the service
./svc.sh start

# Check status
./svc.sh status
```

---

## Validation

| Check | Command/Action | Expected |
|-------|----------------|----------|
| Runner Status | GitHub > Settings > Actions > Runners | Shows "Idle" |
| Service Running | `./svc.sh status` | "Running" |
| Auto-start Test | Reboot Mac, check runner status | Auto-starts |
| Workflow Test | Run sample workflow | Executes OK |
