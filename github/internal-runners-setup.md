# GitHub Actions Self-Hosted Runner Setup Guide

**Target:** LXC Container (Rocky Linux)

---

## Automated Setup (Recommended)

Use `{env}-local-runner-full-setup.yml` to set up the runner automatically.

### Prerequisites

1. **Secret**: `{ENV}_GH_RUNNER_TOKEN` — fresh token from Settings > Actions > Runners (expires ~1 hour, generate immediately before running)
2. **Variables**: `{ENV}_GH_RUNNER_NAME` = `{env}-local-runner`, `{ENV}_GH_RUNNER_LABELS` = `{env}-local-runner`

### Jobs

| # | Job | What it does |
|---|-----|--------------|
| 1 | Deploy Local Runner LXC | Terraform creates the LXC |
| 2 | Setup GitHub Actions Runner | Registers runner service |
| 3 | Install Runner Tools | AWS CLI, etc. via Ansible |

Open all three lock variables (`{ENV}_INFRA_LOCAL_RUNNER_LOCK`, `{ENV}_SVC_GH_RUNNER_LOCK`, `{ENV}_SVC_LOCAL_RUNNER_TOOLS_LOCK`) to run the full setup in one pass.

---

## Environment Reference

| Setting | DEV | PROD |
|---------|-----|------|
| Host IP | 10.0.63.20 | 10.0.53.20 |
| Runner Name | dev-local-runner | prod-local-runner |
| Label | dev-local-runner | prod-local-runner |
| SSH Target | `root@10.0.63.20` | `root@10.0.53.20` |

---

## Manual Setup (Reference)

Steps are identical for both environments — substitute the correct IP and runner name from the table above.

### 1. Get Runner Token

Repo > **Settings** > **Actions** > **Runners** > **New self-hosted runner** > Linux x64 > copy token (valid ~1 hour).

### 2. Install and Configure

```bash
ssh root@<RUNNER_IP>

useradd -m runner
mkdir -p /opt/actions-runner && cd /opt/actions-runner

curl -o actions-runner-linux-x64-2.331.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-linux-x64-2.331.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.331.0.tar.gz
chown -R runner:runner /opt/actions-runner

mkdir -p /home/runner/.ssh
cp /root/.ssh/id_ed25519 /root/.ssh/id_ed25519.pub /home/runner/.ssh/
chown -R runner:runner /home/runner/.ssh
chmod 600 /home/runner/.ssh/id_ed25519

su - runner
cd /opt/actions-runner
./config.sh --unattended --replace \
  --url https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure \
  --token YOUR_TOKEN \
  --name <RUNNER_NAME> \
  --labels <RUNNER_LABEL> \
  --work _work
```

### 3. Install Service (as root)

```bash
cd /opt/actions-runner
./svc.sh install runner
./svc.sh start
./svc.sh status
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

| Error | Fix |
|-------|-----|
| "Invalid configuration provided for token" | Token expired — generate fresh |
| "A runner exists with the same name" | `--replace` flag handles this |
| Runner registers with wrong name | Use `${{ vars.VAR }}` not `${VAR}` in SSH commands |
| Orphaned config (local but not on GitHub) | `rm -f .runner .credentials .credentials_rsaparams` |
| "Session conflict" | Delete runner from GitHub UI first |
| "Must run from runner root" | `cd /opt/actions-runner && ./svc.sh start` |
| Runner can't SSH to other LXCs | Copy root's SSH keys to runner user (see step 2) |
