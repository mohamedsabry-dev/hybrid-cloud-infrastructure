update
Runners

Add new self-hosted runner · mohamedsabry-dev/hybrid-cloud-infrastructure

Add new self-hosted runner · mohamedsabry-dev/hybrid-cloud-infrastructure

Adding a self-hosted runner requires that you download, configure, and execute the GitHub Actions Runner. If you do not already have an existing volume licensing agreement for your GitHub purchases, by downloading and configuring the GitHub Actions Runner, you agree to the GitHub Customer Agreement.

Runner image

macOS

Architecture ARM

Download

# Create a folder
$ mkdir actions-runner && cd actions-runner

# Download the latest runner package
$ curl -o actions-runner-osx-arm64-2.331.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-osx-arm64-2.331.0.tar.gz

# Optional: Validate the hash
$ echo "6f56ce368b09041f83c5ded4d0fb83b08d9a28e22300a2ce5cb1ed64e67ea47c actions-runner-osx-arm64-2.331.0.tar.gz" | shasum -a 256 -c

# Extract the installer
$ tar xzf ./actions-runner-osx-arm64-2.331.0.tar.gz

Configure

# Create the runner and start the configuration experience
$ ./config.sh --url https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure --token B4YOKZ6UQAYGQTNLUMAB3F3JN7TJA

# Last step, run it!
$ ./run.sh

---

## Dependencies Installation

Before running workflows, ensure all required tools are installed on the runner.

### Prerequisites

Install Homebrew (if not already installed):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

---

### 1. Python 3

```bash
brew install python@3
```

Verify installation:

```bash
python3 --version
```

---

### 2. Docker Desktop

Download and install Docker Desktop for Mac from:
https://www.docker.com/products/docker-desktop/

Or install via Homebrew:

```bash
brew install --cask docker
```

Verify installation:

```bash
docker --version
```

> **Note:** After installation, open Docker Desktop to complete setup and start the Docker daemon.

---

### 3. PowerShell

```bash
brew install --cask powershell
```

Verify installation:

```bash
pwsh --version
```

---

### 4. AWS CLI

```bash
brew install awscli
```

Verify installation:

```bash
aws --version
```

Configure AWS credentials:

```bash
aws configure
```

---

### 5. Terraform

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

Verify installation:

```bash
terraform --version
```

---

### 6. Ansible

```bash
brew install ansible
```

Verify installation:

```bash
ansible --version
```

---

## Verification

Run the following script to verify all dependencies are installed:

```bash
echo "=== Checking Dependencies ==="
echo "Python 3: $(python3 --version 2>/dev/null || echo 'NOT INSTALLED')"
echo "Docker: $(docker --version 2>/dev/null || echo 'NOT INSTALLED')"
echo "PowerShell: $(pwsh --version 2>/dev/null || echo 'NOT INSTALLED')"
echo "AWS CLI: $(aws --version 2>/dev/null || echo 'NOT INSTALLED')"
echo "Terraform: $(terraform --version 2>/dev/null | head -1 || echo 'NOT INSTALLED')"
echo "Ansible: $(ansible --version 2>/dev/null | head -1 || echo 'NOT INSTALLED')"
echo "=== Done ==="
```

---

## Installed Versions (Reference)

| Tool | Version |
|------|---------|
| Python 3 | 3.14.2 |
| Docker Desktop | 29.1.3 |
| PowerShell | 7.5.4 |
| AWS CLI | 2.33.4 |
| Terraform | 1.14.3 |
| Ansible | 2.20.1 |

**Environment:** macOS (Darwin 25.2.0) - ARM64 (Apple Silicon)

---

## Service Auto Start Configuration

### Option A: User Service (Required for iOS/GUI Testing)

Use when running iOS Simulator, UI tests, or GUI applications.

```bash
cd ~/actions-runner
./svc.sh install
./svc.sh start
./svc.sh status  # Verify runner is active
```

> **Note:** Requires Automatic Login enabled. Go to System Settings → Users & Groups → Login Options.

### Option B: System Service (Backend/CLI Only)

Use when running backend tests, scripts, or Docker builds.

```bash
cd ~/actions-runner
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status  # Verify runner is active
```

---

## Label Assignment

1. Navigate to Repository Settings → Actions → Runners
2. Click on your Mac Mini runner name
3. Click the ⚙️ Settings icon
4. Under Labels, add:
   - `mac-mini`
   - `m2-chip` (or `intel` if applicable)
   - `production` or `staging`
   - `macos-14` (or your macOS version)
5. Click Save

---

## macOS System Configuration

### Prevent Sleep (Critical)

```bash
sudo pmset -c sleep 0
sudo pmset -c displaysleep 10
sudo pmset -c disksleep 0
```

Or via GUI: System Settings → Energy Saver → Enable "Prevent computer from sleeping automatically"

### Disable Automatic Updates (Recommended)

System Settings → Software Update → Uncheck "Automatically keep my Mac up to date"

---

## Service Management Commands

```bash
# Check status
./svc.sh status

# Stop service
./svc.sh stop

# Restart service
./svc.sh stop && ./svc.sh start

# Uninstall service
./svc.sh uninstall

# View logs (system service)
sudo launchctl list | grep actions.runner
```

---

## Troubleshooting

### Runner not starting after reboot
- Verify Automatic Login is enabled
- Check service status: `./svc.sh status`
- Review logs: `log show --predicate 'subsystem == "com.apple.launchd"' --last 30m`

### Workflows not picking up runner
- Verify labels match workflow `runs-on` configuration
- Check runner status in GitHub UI (should show green dot)
- Ensure Mac Mini is awake and network connected

### Permission issues
- User service: Run all `svc.sh` commands without `sudo`
- System service: Run all `svc.sh` commands with `sudo`