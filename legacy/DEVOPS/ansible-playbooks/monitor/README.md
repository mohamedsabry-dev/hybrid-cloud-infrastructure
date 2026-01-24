# Monitoring Setup - Ansible Playbooks

Ansible playbooks for deploying and managing Prometheus monitoring infrastructure using Node Exporter.

---

## Table of Contents

1. [Overview](#overview)
2. [Playbooks](#playbooks)
3. [Prerequisites](#prerequisites)
4. [Usage](#usage)
5. [Architecture](#architecture)
6. [Troubleshooting](#troubleshooting)
7. [Related Documentation](#related-documentation)

---

## Overview

This collection automates the deployment of **Node Exporter** on all infrastructure hosts and configures **Prometheus** to scrape metrics from them.

**What Gets Deployed:**
- Node Exporter v1.7.0 on all managed hosts
- Firewall rules (firewalld) restricting Node Exporter access to Prometheus server only
- Dynamic Prometheus configuration based on Ansible inventory
- Automated validation of connectivity between Prometheus and Node Exporter endpoints

**Target Environment:**
- Prometheus Server: `10.0.20.186` (monitor.home.lab)
- Monitored Hosts: All hosts in Ansible inventory (K8s cluster, Vault, Jenkins, Ansible, etc.)

---

## Playbooks

### 01-node_exporter-setup.yml

**Purpose:** Install and secure Node Exporter on all hosts

**What it does:**
1. Creates a dedicated `node_exporter` system user (no shell, no home directory)
2. Downloads Node Exporter v1.7.0 from GitHub releases
3. Installs binary to `/usr/local/bin/node_exporter`
4. Creates systemd service for automatic startup
5. Configures firewalld to **only allow Prometheus IP (10.0.20.186)** on port 9100
6. Starts and enables Node Exporter service

**Key Variables:**
```yaml
node_exporter_version: "1.7.0"
prometheus_ip: "10.0.20.186"
arch: "linux-amd64"
```

**Firewall Security:**
- Only Prometheus server (10.0.20.186) can access Node Exporter port 9100
- All other IPs are blocked by default
- Uses firewalld rich rules (RedHat/CentOS)

**Usage:**
```bash
cd /03-AUTOMATION/ansible-playbooks/monitor
ansible-playbook 01-node_exporter-setup.yml
```

**Expected Runtime:** 2-3 minutes per host

---

### 02-validate_node_exporter.yml

**Purpose:** Validate Node Exporter installation and Prometheus connectivity

**What it does:**
1. **Local Check:** Verifies Node Exporter service is active
2. **Port Check:** Confirms port 9100 is listening locally
3. **Remote Check:** Tests if Prometheus server can connect to each Node Exporter endpoint
4. **Report:** Displays connectivity status for each host

**How the Remote Test Works:**
- Executes `wait_for` module **FROM** Prometheus server
- **TARGETING** each Node Exporter host on port 9100
- Simulates actual Prometheus scrape connectivity

**Usage:**
```bash
ansible-playbook 02-validate_node_exporter.yml
```

**Expected Output:**
```
Target: k8s-master.home.lab | Local Service: ✅ UP | Prometheus Connection: ✅ SUCCESS
Target: vault-01.home.lab   | Local Service: ✅ UP | Prometheus Connection: ✅ SUCCESS
```

**Failure Example:**
```
Target: jenkins.home.lab | Local Service: ✅ UP | Prometheus Connection: ❌ BLOCKED (Check Firewall)
```

**Troubleshooting Failed Connections:**
- Check firewalld rules: `firewall-cmd --list-all`
- Verify Prometheus IP is allowed: `firewall-cmd --list-rich-rules`
- Test manually from Prometheus: `curl http://<target-host>:9100/metrics`

---

### 03-update_prometheus.yml

**Purpose:** Update Prometheus configuration with all targets from Ansible inventory

**What it does:**
1. Generates Prometheus configuration from Jinja2 template (`prometheus.yml.j2`)
2. Deploys configuration to `/etc/prometheus/prometheus.yml`
3. Validates configuration using `promtool check config`
4. Restarts Prometheus service to apply changes

**Key Features:**
- **Dynamic Target Discovery:** Automatically adds all hosts from `groups['all']` to Prometheus scrape targets
- Uses `ansible_host` variable from inventory for IP resolution
- Scrape interval: 15 seconds (configurable in template)

**Template Logic:**
```jinja2
- targets:
{% for host in groups['all'] %}
  - '{{ hostvars[host]["ansible_host"] | default(host) }}:9100'
{% endfor %}
```

**Usage:**
```bash
ansible-playbook 03-update_prometheus.yml
```

**When to Run:**
- After adding new hosts to Ansible inventory
- After running `01-node_exporter-setup.yml` on new hosts
- When changing scrape intervals or job configurations

**Post-Deployment Verification:**
```bash
# Check Prometheus targets
curl http://10.0.20.186:9090/api/v1/targets | jq '.data.activeTargets[] | {job, instance, health}'

# Or view in Prometheus UI
http://10.0.20.186:9090/targets
```

---

## Prerequisites

### Ansible Controller

**Required Collections:**
```bash
ansible-galaxy collection install ansible.posix
ansible-galaxy collection install community.general
```

**Inventory Requirements:**
- Prometheus server must be defined as `monitor.home.lab` in inventory
- All hosts to monitor must be in `groups['all']`
- Each host must have `ansible_host` variable set to its IP address

**Example Inventory:**
```ini
[monitor]
monitor.home.lab ansible_host=10.0.20.186

[k8s_cluster]
k8s-master.home.lab ansible_host=10.0.20.181
k8s-worker-1.home.lab ansible_host=10.0.20.182

[vault]
vault-01.home.lab ansible_host=10.0.20.191

[all:vars]
ansible_user=veeam@home.lab
ansible_become=yes
```

### Target Hosts

**Operating System:**
- RedHat/CentOS/Rocky Linux (firewalld support)
- For Ubuntu/Debian: Uncomment UFW section in `01-node_exporter-setup.yml`

**Services Required:**
- firewalld (for CentOS/RHEL)
- systemd

**Connectivity:**
- SSH access from Ansible controller
- User with sudo privileges
- Port 9100 available (not used by other services)

---

## Usage

### Initial Setup (New Infrastructure)

**Step 1: Install Node Exporter on all hosts**
```bash
cd /03-AUTOMATION/ansible-playbooks/monitor
ansible-playbook 01-node_exporter-setup.yml
```

**Step 2: Validate Installation**
```bash
ansible-playbook 02-validate_node_exporter.yml
```

**Step 3: Update Prometheus Configuration**
```bash
ansible-playbook 03-update_prometheus.yml
```

**Step 4: Verify in Prometheus UI**
```
http://10.0.20.186:9090/targets
```
All targets should show status: **UP**

---

### Adding New Hosts

When adding new infrastructure hosts:

1. **Add to Ansible Inventory:**
   ```ini
   [new_hosts]
   jenkins.home.lab ansible_host=10.0.20.196
   ```

2. **Install Node Exporter on new host only:**
   ```bash
   ansible-playbook 01-node_exporter-setup.yml --limit jenkins.home.lab
   ```

3. **Validate new host:**
   ```bash
   ansible-playbook 02-validate_node_exporter.yml --limit jenkins.home.lab
   ```

4. **Update Prometheus to include new target:**
   ```bash
   ansible-playbook 03-update_prometheus.yml
   ```

5. **Check Prometheus targets:**
   ```bash
   # New host should appear in target list
   curl http://10.0.20.186:9090/api/v1/targets | grep jenkins
   ```

---

### Removing Hosts

When decommissioning hosts:

1. **Stop Node Exporter on target host:**
   ```bash
   ansible <hostname> -m systemd -a "name=node_exporter state=stopped enabled=no" --become
   ```

2. **Remove from Ansible inventory**

3. **Regenerate Prometheus config:**
   ```bash
   ansible-playbook 03-update_prometheus.yml
   ```

---

## Architecture

### Monitoring Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Prometheus Server                        │
│                    (10.0.20.186)                            │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Prometheus                                          │  │
│  │  - Scrapes metrics every 15s                         │  │
│  │  - Stores time-series data                           │  │
│  │  - Config: /etc/prometheus/prometheus.yml           │  │
│  └────────┬─────────────────────────────────────────────┘  │
│           │                                                 │
│           │ Scrape HTTP :9100/metrics                      │
│           ├─────────────────────────────────────────────────┼──> K8s Master (10.0.20.181)
│           │                                                 │
│           ├─────────────────────────────────────────────────┼──> K8s Worker-1 (10.0.20.182)
│           │                                                 │
│           ├─────────────────────────────────────────────────┼──> Vault-01 (10.0.20.191)
│           │                                                 │
│           ├─────────────────────────────────────────────────┼──> Jenkins (10.0.20.196)
│           │                                                 │
│           └─────────────────────────────────────────────────┼──> Ansible (10.0.20.185)
│                                                             │
└─────────────────────────────────────────────────────────────┘

Each Target Host:
┌────────────────────────────────────┐
│  Node Exporter Service             │
│  - Port: 9100                      │
│  - User: node_exporter             │
│  - Binary: /usr/local/bin/         │
│  - Service: systemd managed        │
│  - Firewall: Only 10.0.20.186      │
└────────────────────────────────────┘
```

### Security Model

**Network Security:**
- Firewalld rich rules restrict port 9100 to Prometheus IP only
- No authentication on Node Exporter (secured via firewall)
- Metrics endpoint is read-only

**Service Security:**
- Node Exporter runs as dedicated system user (no shell, no home)
- Binary owned by node_exporter:node_exporter
- Minimal privileges (no sudo required)

**Prometheus Access:**
- Only Prometheus server (10.0.20.186) can scrape metrics
- All other IPs blocked by firewalld

---

## Troubleshooting

### Common Issues

#### 1. Node Exporter Service Not Starting

**Symptoms:**
```
failed: [hostname] => {"msg": "Service is in failed state"}
```

**Diagnosis:**
```bash
ssh <hostname>
systemctl status node_exporter
journalctl -u node_exporter -n 50
```

**Common Causes:**
- Binary not executable: `chmod +x /usr/local/bin/node_exporter`
- User doesn't exist: `id node_exporter`
- Port 9100 already in use: `ss -tlnp | grep 9100`

**Fix:**
```bash
# Re-run setup playbook
ansible-playbook 01-node_exporter-setup.yml --limit <hostname>
```

---

#### 2. Prometheus Cannot Connect (Firewall Blocked)

**Symptoms:**
```
Prometheus Connection: ❌ BLOCKED (Check Firewall)
```

**Diagnosis:**
```bash
# On target host
firewall-cmd --list-rich-rules

# Should see:
rule family="ipv4" source address="10.0.20.186" port port="9100" protocol="tcp" accept
```

**Fix:**
```bash
# Manually add rule
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.20.186" port port="9100" protocol="tcp" accept'
firewall-cmd --reload

# Or re-run playbook
ansible-playbook 01-node_exporter-setup.yml --limit <hostname>
```

---

#### 3. Prometheus Config Validation Failed

**Symptoms:**
```
fatal: [monitor.home.lab]: FAILED! => {"cmd": "/usr/local/bin/promtool check config..."}
```

**Diagnosis:**
```bash
ssh monitor.home.lab
/usr/local/bin/promtool check config /etc/prometheus/prometheus.yml
```

**Common Causes:**
- YAML syntax error in template
- Invalid target format
- Missing required fields

**Fix:**
```bash
# Check template syntax
ansible-playbook 03-update_prometheus.yml --syntax-check

# Validate template rendering
ansible monitor.home.lab -m template -a "src=prometheus.yml.j2 dest=/tmp/test-prometheus.yml"
```

---

#### 4. Targets Show "DOWN" in Prometheus

**Diagnosis Steps:**

**A. Check if Node Exporter is running:**
```bash
ansible <hostname> -m shell -a "systemctl status node_exporter" --become
```

**B. Test local port:**
```bash
ansible <hostname> -m shell -a "curl -s http://localhost:9100/metrics | head -5"
```

**C. Test from Prometheus server:**
```bash
ssh monitor.home.lab
curl http://<target-ip>:9100/metrics
```

**D. Check firewall rules:**
```bash
ansible <hostname> -m shell -a "firewall-cmd --list-rich-rules" --become
```

**Fix Based on Diagnosis:**
- Node Exporter down: `systemctl restart node_exporter`
- Firewall blocking: Re-run `01-node_exporter-setup.yml`
- Network issue: Check routing/connectivity

---

#### 5. New Host Not Appearing in Prometheus

**Checklist:**

1. **Host in inventory?**
   ```bash
   ansible all --list-hosts | grep <hostname>
   ```

2. **Node Exporter installed?**
   ```bash
   ansible-playbook 02-validate_node_exporter.yml --limit <hostname>
   ```

3. **Prometheus config updated?**
   ```bash
   ssh monitor.home.lab
   grep <hostname> /etc/prometheus/prometheus.yml
   ```

4. **Prometheus reloaded?**
   ```bash
   ssh monitor.home.lab
   systemctl status prometheus
   ```

**Fix:**
```bash
# Update Prometheus config
ansible-playbook 03-update_prometheus.yml

# Force reload
ssh monitor.home.lab "systemctl restart prometheus"
```

---

### Manual Verification Commands

**Check all Node Exporter services:**
```bash
ansible all -m systemd -a "name=node_exporter" --become | grep "ActiveState"
```

**Test metrics endpoint from Prometheus:**
```bash
ansible monitor.home.lab -m shell -a "curl -s http://10.0.20.181:9100/metrics | head -10"
```

**View current Prometheus targets:**
```bash
curl -s http://10.0.20.186:9090/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.instance) - \(.health)"'
```

**Check firewall rules on all hosts:**
```bash
ansible all -m shell -a "firewall-cmd --list-rich-rules | grep 9100" --become
```

---

## Related Documentation

### Infrastructure Documentation

- **[DR Documentation](../../../00-DOCUMENTATION/01-Infrastructure-Layer/DR/README.md)** - Disaster recovery procedures
- **[Compute Resources](../../../00-DOCUMENTATION/01-Infrastructure-Layer/Compute/)** - VM specifications and compute layer
- **[Network Configuration](../../../00-DOCUMENTATION/01-Infrastructure-Layer/Network/)** - Network topology and IP addressing

### Monitoring Stack

- **Prometheus Documentation:** https://prometheus.io/docs/
- **Node Exporter Metrics:** https://github.com/prometheus/node_exporter#enabled-by-default
- **Grafana Dashboards:** (See monitoring server documentation)

### Troubleshooting Reference

> **Note:** Troubleshooting cases documentation is planned for:
> `00-DOCUMENTATION/05-Troubleshooting/application/`
>
> When created, this will include:
> - Common monitoring issues and resolutions
> - Prometheus alerting troubleshooting
> - Node Exporter metrics interpretation
> - Performance tuning guidelines

### Related Ansible Playbooks

- **[OS Services](../os-services/)** - User account management (veeam@home.lab, veeam_emergency)
- **[Vault Automation](../../scripts/)** - Vault integration scripts

---

## Files in This Directory

```
monitor/
├── README.md                          # This file
├── 01-node_exporter-setup.yml         # Install Node Exporter on all hosts
├── 02-validate_node_exporter.yml      # Validate installation and connectivity
├── 03-update_prometheus.yml           # Update Prometheus configuration
└── prometheus.yml.j2                  # Jinja2 template for Prometheus config
```

---

## Maintenance

### Regular Tasks

**Weekly:**
- Verify all targets are UP in Prometheus UI
- Check Node Exporter service health: `ansible all -m systemd -a "name=node_exporter"`

**Monthly:**
- Review firewall rules for accuracy
- Update Node Exporter version if security patches released
- Test validation playbook: `ansible-playbook 02-validate_node_exporter.yml`

**After Infrastructure Changes:**
- New hosts added: Run full setup sequence (Steps 1-4 above)
- Hosts decommissioned: Update Prometheus config (Step 3)
- IP address changes: Update inventory + re-run `03-update_prometheus.yml`

### Upgrading Node Exporter

1. **Update version variable in `01-node_exporter-setup.yml`:**
   ```yaml
   node_exporter_version: "1.8.0"  # Example new version
   ```

2. **Test on single host:**
   ```bash
   ansible-playbook 01-node_exporter-setup.yml --limit ansible.home.lab
   ```

3. **Verify metrics still work:**
   ```bash
   ansible-playbook 02-validate_node_exporter.yml --limit ansible.home.lab
   ```

4. **Roll out to all hosts:**
   ```bash
   ansible-playbook 01-node_exporter-setup.yml
   ```

---

## Quick Reference

**Install monitoring on new host:**
```bash
ansible-playbook 01-node_exporter-setup.yml --limit <hostname>
ansible-playbook 02-validate_node_exporter.yml --limit <hostname>
ansible-playbook 03-update_prometheus.yml
```

**Check all targets status:**
```bash
curl http://10.0.20.186:9090/targets
```

**Restart Node Exporter:**
```bash
ansible <hostname> -m systemd -a "name=node_exporter state=restarted" --become
```

**View Prometheus config:**
```bash
ansible monitor.home.lab -m shell -a "cat /etc/prometheus/prometheus.yml" --become
```

---

**Last Updated:** 2026-01-03
**Maintained By:** Infrastructure Team
**Prometheus Version:** Compatible with Prometheus 2.x
**Node Exporter Version:** 1.7.0
