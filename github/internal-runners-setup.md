# GitHub Actions Self-Hosted Runner Setup Guide

**Date:** 2026-02-23
**Target:** LXC Container (Rocky Linux)

---

## Step 1: Get Runner Token from GitHub

1. Go to repo → **Settings** → **Actions** → **Runners**
2. Click **New self-hosted runner**
3. Select **Linux** and **x64**
4. Copy the token (valid for ~1 hour)

---

## Step 2: Dev Runner Setup

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

# Switch to runner user
su - runner
cd /opt/actions-runner

# Configure
./config.sh --url https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure --token YOUR_TOKEN
```

Enter:
- **Runner name:** `dev-local-runner`
- **Labels:** `dev-local-runner`
- **Work folder:** Enter (default)

Install service:

```bash
exit
cd /opt/actions-runner
./svc.sh install runner
./svc.sh start
./svc.sh status
```

---

## Step 3: Prod Runner Setup

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

# Switch to runner user
su - runner
cd /opt/actions-runner

# Configure
./config.sh --url https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure --token YOUR_TOKEN
```

Enter:
- **Runner name:** `prod-local-runner`
- **Labels:** `prod-local-runner`
- **Work folder:** Enter (default)

Install service:

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

## Runner Reference

| Environment | IP Address | Runner Name | Label |
|-------------|------------|-------------|-------|
| Dev | 10.0.63.20 | dev-local-runner | dev-local-runner |
| Prod | 10.0.53.20 | prod-local-runner | prod-local-runner |


  # Add runner to sudoers with no password                                                                      
  echo "runner ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/runner
  chmod 440 /etc/sudoers.d/runner 