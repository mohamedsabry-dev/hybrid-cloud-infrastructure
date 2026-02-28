# GitHub Actions Self-Hosted Runner Setup Guide

**Date:** 2026-02-28
**Target:** LXC Container (Rocky Linux)

---

## Automated Setup (Recommended)

Use the workflow `dev-svc-gh-local_runner.yml` to automatically set up the runner.

### Prerequisites

1. **Secret**: `DEV_GH_RUNNER_TOKEN` - Fresh token from Settings > Actions > Runners
2. **Variables**: `DEV_GH_RUNNER_NAME` = `dev-local-runner`, `DEV_GH_RUNNER_LABELS` = `dev-local-runner`

### Trigger

Push to the workflow file or run manually via workflow_dispatch.

---

## Manual Setup (Reference)

### Step 1: Get Runner Token from GitHub

1. Go to repo > **Settings** > **Actions** > **Runners**
2. Click **New self-hosted runner**
3. Select **Linux** and **x64**
4. Copy the token (valid for ~1 hour)

---

### Step 2: Dev Runner Setup

```bash
# SSH into dev local_runner
ssh root@10.0.63.20

# Create runner user
useradd -m runner

# Create and setup directory
mkdir -p /opt/actions-runner
cd /opt/actions-runner

# Download runner
curl -o actions-runner-linux-x64-2.331.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-linux-x64-2.331.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-2.331.0.tar.gz

# Set ownership
chown -R runner:runner /opt/actions-runner

# Copy root SSH keys to runner user (for SSH to other LXCs)
mkdir -p /home/runner/.ssh
cp /root/.ssh/id_ed25519 /root/.ssh/id_ed25519.pub /home/runner/.ssh/
chown -R runner:runner /home/runner/.ssh
chmod 600 /home/runner/.ssh/id_ed25519

# Switch to runner user and configure
su - runner
cd /opt/actions-runner
./config.sh --unattended --replace \
  --url https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure \
  --token YOUR_TOKEN \
  --name dev-local-runner \
  --labels dev-local-runner \
  --work _work
```

Install service (as root):

```bash
exit
cd /opt/actions-runner
./svc.sh install runner
./svc.sh start
./svc.sh status
```

---

### Step 3: Prod Runner Setup

```bash
# SSH into prod local_runner
ssh root@10.0.53.20

# Create runner user
useradd -m runner

# Create and setup directory
mkdir -p /opt/actions-runner
cd /opt/actions-runner

# Download runner
curl -o actions-runner-linux-x64-2.331.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-linux-x64-2.331.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-2.331.0.tar.gz

# Set ownership
chown -R runner:runner /opt/actions-runner

# Copy root SSH keys to runner user
mkdir -p /home/runner/.ssh
cp /root/.ssh/id_ed25519 /root/.ssh/id_ed25519.pub /home/runner/.ssh/
chown -R runner:runner /home/runner/.ssh
chmod 600 /home/runner/.ssh/id_ed25519

# Switch to runner user and configure
su - runner
cd /opt/actions-runner
./config.sh --unattended --replace \
  --url https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure \
  --token YOUR_TOKEN \
  --name prod-local-runner \
  --labels prod-local-runner \
  --work _work
```

Install service (as root):

```bash
exit
cd /opt/actions-runner
./svc.sh install runner
./svc.sh start
./svc.sh status
```

---

## Using in Workflows

```yaml
# Dev workflows
runs-on: dev-local-runner

# Prod workflows
runs-on: prod-local-runner

# Mac mini (for gh CLI authenticated operations)
runs-on: mac-mini
```

---

## Service Commands

```bash
cd /opt/actions-runner
./svc.sh status    # Check status
./svc.sh stop      # Stop runner
./svc.sh start     # Start runner
./svc.sh uninstall # Remove service
```

---

## Troubleshooting

**Token expires quickly** - Generate a new token immediately before running.

**"Invalid configuration provided for token"** - Token is expired or invalid.

**"A runner exists with the same name"** - Use `--replace` flag in config.sh.

**Runner registers with wrong name** - Use GitHub Actions expressions `${{ vars.VAR_NAME }}` directly instead of shell variables `${VAR_NAME}`.

**Orphaned config (runner exists locally but not on GitHub):**
```bash
rm -f /opt/actions-runner/.runner /opt/actions-runner/.credentials /opt/actions-runner/.credentials_rsaparams
```

**"Session conflict" error** - Delete the conflicting runner from GitHub UI.

**svc.sh "Must run from runner root"** - Run from inside the directory:
```bash
cd /opt/actions-runner && ./svc.sh start
```

**Runner can't SSH to other LXCs** - Copy root's SSH keys to runner user:
```bash
cp /root/.ssh/id_ed25519* /home/runner/.ssh/
chown runner:runner /home/runner/.ssh/id_ed25519*
chmod 600 /home/runner/.ssh/id_ed25519
```

---

## Runner Reference

| Environment | IP Address | Runner Name | Label |
|-------------|------------|-------------|-------|
| Dev | 10.0.63.20 | dev-local-runner | dev-local-runner |
| Prod | 10.0.53.20 | prod-local-runner | prod-local-runner |
| Mac Mini | local | Mohameds-Mac-mini | mac-mini |
