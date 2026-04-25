# Prometheus Setup Issues

**Case ID**: APPLICATION-001
**Date**: 2025-2026 (Initial deployment)
**Severity**: High
**Status**: Resolved
**Category**: Application / Monitoring / Prometheus

---

## Problem Summary

During Prometheus deployment via Ansible on Rocky Linux 10, two critical issues prevented the service from starting:

1. **Port 9090 Conflict**: Cockpit service (default web console in RHEL-based distributions) was already bound to TCP port 9090, preventing Prometheus from starting
2. **YAML Configuration Parsing Failure**: prometheus.yml configuration file had indentation errors causing service startup failures

**Impact**: Monitoring stack unavailable until both issues resolved.

---

## Environment

**Component**: Prometheus + Grafana Monitoring Stack
**Target OS**: Rocky Linux 10
**Deployment Method**: Ansible Playbook
**Target VM**: Monitor VM (10.0.20.186)
**Services**:
- Prometheus: Port 9090 (web UI and data ingestion)
- Grafana: Port 3000 (visualization)
- Node Exporter: Port 9100 (metrics exporter)

**VM Specifications**:
- Memory: 8GB
- CPU: 4 vCPU
- Disk: 90GB OS + 40GB data
- FQDN: monitor.home.lab

---

## Issue 1: Cockpit Port Conflict (TCP 9090)

### Problem Description

**Error Message**:
```
bind: address already in use
```

**Root Cause**:
Red Hat-based distributions (Rocky, Alma, RHEL, Fedora) ship with **Cockpit** (the web-based server management console) pre-installed and enabled by default. Cockpit listens on TCP port 9090, the same default port used by Prometheus.

When Prometheus attempted to start, it tried to bind to `0.0.0.0:9090` but failed because Cockpit's socket service (`cockpit.socket`) was already holding that port.

### Investigation Steps

```bash
# Check Prometheus service status
sudo systemctl status prometheus
# Result: Failed to bind address

# Check Prometheus logs
sudo journalctl -u prometheus --no-pager | tail -n 20
# Result: bind: address already in use

# Identify process using port 9090
sudo ss -tlnp | grep :9090
# Result: cockpit.socket listening on 0.0.0.0:9090

# Check Cockpit service status
sudo systemctl status cockpit.socket
# Result: active (listening)

# Check Cockpit logs
sudo journalctl -u cockpit --no-pager | tail -n 20
```

### Resolution

**Decision**: Disable Cockpit permanently and reclaim port 9090 for Prometheus.

**Rationale**:
- Prometheus monitoring is critical infrastructure
- Cockpit is redundant (we use SSH for server management)
- Alternative: Change Prometheus port (not ideal - breaks convention)

**Commands Executed**:
```bash
# Stop Cockpit socket service immediately
sudo systemctl stop cockpit.socket

# Disable Cockpit from starting at boot
sudo systemctl disable cockpit.socket

# Mask Cockpit to prevent accidental re-enabling
sudo systemctl mask cockpit.socket

# Restart Prometheus service
sudo systemctl restart prometheus

# Verify Prometheus started successfully
sudo systemctl status prometheus
# Result: active (running)

# Verify Prometheus logs
sudo journalctl -u prometheus --no-pager | tail -n 20
# Result: Server is ready to receive web requests
```

### Verification

```bash
# Confirm port 9090 now owned by Prometheus
sudo ss -tlnp | grep :9090
# Result: prometheus listening on 0.0.0.0:9090

# Access Prometheus web UI
curl -I http://localhost:9090
# Result: HTTP/200 OK

# Check targets status
curl http://localhost:9090/targets
# Result: All targets showing State: UP
```

**Result**: Prometheus successfully started and began scraping metrics from all configured endpoints (k8s-master, k8s-workers, vault nodes, etc.).

---

## Issue 2: YAML Configuration Parsing Failure

### Problem Description

**Error Message**:
```
did not find expected key
mapping values are not allowed here
```

**Root Cause**:
The `prometheus.yml` configuration file had **inconsistent indentation** in the `scrape_configs` block. YAML is strictly whitespace-sensitive, and the error was caused by:

1. **Mixing tabs and spaces** in the same file
2. **Incorrect indentation levels** for child elements
3. **Misaligned list items** (dash `-` not aligned with parent key)

This occurred when using Ansible's `block` directive to insert the scrape configuration, which can inadvertently add extra spaces or tabs depending on how the playbook is written.

### Investigation Steps

```bash
# Check Prometheus service status
sudo systemctl status prometheus
# Result: Failed to start

# Check Prometheus logs
sudo journalctl -u prometheus --no-pager | tail -n 20
# Result: yaml: did not find expected key

# Validate YAML syntax
sudo cat /etc/prometheus/prometheus.yml
# Visual inspection: Indentation appears inconsistent

# Use YAML linter to identify exact error
yamllint /etc/prometheus/prometheus.yml
# Result: Line 23: wrong indentation (expected 2 spaces, got 4)
```

### Incorrect YAML Example

```yaml
scrape_configs:
  - job_name: 'linux_nodes'
      static_configs:    #  Wrong indentation (4 spaces instead of 2)
      - targets:         #  Dash not aligned
        - '10.0.20.100:9100'
          - '10.0.20.101:9100'  #  Mixed indentation
```

### Resolution

**Standardization**: Rewrote the configuration file with strict 2-space indentation (no tabs).

**Correct YAML Syntax**:
```yaml
scrape_configs:
  - job_name: 'linux_nodes'     # Level 1: Base key
    static_configs:             # Level 2: Indented 2 spaces
      - targets:                # Level 3: List item (dash aligned under 's' in static_configs)
          - '10.0.20.100:9100'  # Level 4: Indented 2 more spaces
          - '10.0.20.101:9100'
          - '10.0.20.102:9100'
```

**Ansible Playbook Fix**:
```yaml
# Before (caused indentation issues)
- name: Configure Prometheus scrape targets
  blockinfile:
    path: /etc/prometheus/prometheus.yml
    block: |
      scrape_configs:
        - job_name: 'linux_nodes'
          static_configs:
            - targets:
                - '10.0.20.100:9100'

# After (proper indentation control)
- name: Configure Prometheus scrape targets
  ansible.builtin.template:
    src: prometheus.yml.j2
    dest: /etc/prometheus/prometheus.yml
    mode: '0644'
  notify: restart prometheus
```

### Validation Steps

```bash
# Validate YAML syntax with yamllint
yamllint /etc/prometheus/prometheus.yml
# Result: No errors

# Validate Prometheus config with built-in tool
promtool check config /etc/prometheus/prometheus.yml
# Result: SUCCESS: /etc/prometheus/prometheus.yml is valid

# Restart Prometheus
sudo systemctl restart prometheus

# Verify service started
sudo systemctl status prometheus
# Result: active (running)
```

**Result**: Configuration file parsed successfully, Prometheus started without errors.

---

## Complete Resolution Timeline

### Timeline

| Time | Action | Result |
|------|--------|--------|
| T+0 min | Initial Prometheus deployment via Ansible |  Failed to start |
| T+5 min | Investigated logs, found "bind: address already in use" | Port 9090 conflict identified |
| T+10 min | Stopped/disabled/masked cockpit.socket | Port 9090 freed |
| T+12 min | Restarted Prometheus |  Still failed (new error) |
| T+15 min | Investigated logs, found YAML parsing error | Indentation issue identified |
| T+20 min | Fixed prometheus.yml indentation, validated with yamllint | Syntax corrected |
| T+22 min | Restarted Prometheus |  Service started successfully |
| T+25 min | Verified all targets showing State: UP |  Metrics collection working |
| T+30 min | Configured Grafana data source |  Monitoring stack operational |

---

## Post-Resolution Configuration

### Prometheus Targets Verified

**Accessible at**: http://10.0.20.186:9090/targets

All endpoints showing **State: UP**:
- K8s Master: 10.0.20.x:9100
- K8s Worker-1: 10.0.20.x:9100
- K8s Worker-2: 10.0.20.x:9100
- K8s Worker-3: 10.0.20.x:9100
- Vault-1: 10.0.20.x:9100
- Vault-2: 10.0.20.x:9100
- Vault-3: 10.0.20.x:9100

### Grafana Integration

**Step 1: Access Grafana**
```
URL: http://10.0.20.186:3000
Default Login: admin / admin
```

**Step 2: Add Prometheus Data Source**
```
Configuration > Data Sources > Add data source > Prometheus
URL: http://localhost:9090
Click: Save & Test
Result:  Data source is working
```

**Step 3: Import Node Exporter Dashboard**
```
Create > Import > Dashboard ID: 1860
(Node Exporter Full - industry standard dashboard)
Select Prometheus data source
Click: Import
```

**Result**: Full monitoring dashboard showing:
- CPU usage for all VMs
- Memory (RAM) usage
- Disk I/O and network traffic
- System load and uptime

---

## Prevention Measures

### 1. Pre-Deployment Checks for Future Deployments

**Add to Ansible Playbook**:
```yaml
- name: Check if port 9090 is already in use
  ansible.builtin.shell: ss -tlnp | grep :9090
  register: port_check
  failed_when: false
  changed_when: false

- name: Stop Cockpit if present
  ansible.builtin.systemd:
    name: cockpit.socket
    state: stopped
    enabled: false
    masked: true
  when: port_check.rc == 0
```

### 2. YAML Validation in CI/CD

**Add to Ansible Playbook**:
```yaml
- name: Validate Prometheus config before deployment
  ansible.builtin.command: promtool check config /etc/prometheus/prometheus.yml
  register: config_check
  failed_when: config_check.rc != 0
```

### 3. Template-Based Configuration

**Best Practice**: Use Jinja2 templates instead of `blockinfile`:
- Better control over indentation
- Version-controlled configuration
- Easy to validate before deployment

### 4. Documentation Updates

**Added to Deployment Runbook**:
-  Rocky/RHEL systems: Check for Cockpit on port 9090
-  Always validate YAML with `yamllint` before applying
-  Use `promtool check config` before restarting service

---

## Lessons Learned

### What Went Wrong

1. **Assumption About Port Availability**:
   - Did not check for default services on target OS
   - Cockpit is enabled by default on RHEL-based distributions
   - Should have included port availability check in playbook

2. **YAML Indentation in Ansible**:
   - `blockinfile` module can introduce indentation issues
   - Manual editing after Ansible run broke automation
   - No pre-deployment YAML validation step

3. **Lack of Validation Steps**:
   - No `promtool check config` before service restart
   - No automated YAML linting in CI/CD pipeline

### What Went Right

1. **Comprehensive Logging**:
   - `journalctl` provided clear error messages
   - Port conflict immediately identifiable with `ss -tlnp`
   - YAML errors pinpointed with `yamllint`

2. **Clean Resolution**:
   - Cockpit permanently disabled (no future conflicts)
   - YAML standardized to 2-space indentation
   - Configuration validated with proper tools

3. **Documentation**:
   - Commands and resolution steps documented in Notes file
   - Grafana setup guide added for future reference

### Key Takeaways

1. **Always Check Default Services**:
   - RHEL/Rocky/CentOS: Cockpit on 9090
   - Ubuntu: Apache/Nginx may occupy 80/443
   - Add port availability checks to deployment automation

2. **YAML Requires Strict Validation**:
   - Use `yamllint` for all YAML files
   - Use `promtool check config` for Prometheus configs
   - Prefer templates over blockinfile for complex configs

3. **Automation Should Be Idempotent**:
   - Ansible playbook should handle Cockpit cleanup automatically
   - Should not require manual intervention for known issues

---

## Related Issues

- **PLATFORM-011**: FreeIPA Time Sync Clock Skew (monitoring dependencies)
- **PLATFORM-016**: ESXi Master AutoProtect Snapshot Performance Degradation (monitoring this via Prometheus)

---

## References

### Documentation

- [Prometheus Configuration Documentation](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Prometheus Port Configuration](https://prometheus.io/docs/prometheus/latest/getting_started/#configuring-prometheus)
- [Cockpit Documentation](https://cockpit-project.org/guide/latest/listen.html)
- [YAML Specification](https://yaml.org/spec/1.2/spec.html)

### Tools Used

```bash
# Port investigation
ss -tlnp | grep :9090
lsof -i :9090

# YAML validation
yamllint /etc/prometheus/prometheus.yml
promtool check config /etc/prometheus/prometheus.yml

# Service management
systemctl status prometheus
journalctl -u prometheus --no-pager
```

### Grafana Resources

- **Node Exporter Dashboard ID**: 1860 (most popular, 50M+ downloads)
- **Prometheus URL**: http://10.0.20.186:9090
- **Grafana URL**: http://10.0.20.186:3000

---

## Appendix: Command Reference

### Complete Resolution Commands

```bash
# Issue 1: Cockpit Port Conflict
sudo journalctl -u prometheus --no-pager | tail -n 20
sudo journalctl -u cockpit --no-pager | tail -n 20
sudo systemctl stop cockpit.socket
sudo systemctl disable cockpit.socket
sudo systemctl mask cockpit.socket
sudo systemctl restart prometheus
sudo journalctl -u prometheus --no-pager | tail -n 20
sudo systemctl status prometheus

# Issue 2: YAML Validation
yamllint /etc/prometheus/prometheus.yml
promtool check config /etc/prometheus/prometheus.yml
sudo systemctl restart prometheus
sudo systemctl status prometheus

# Verification
curl http://localhost:9090/targets
curl -I http://10.0.20.186:9090
```

### Grafana Setup (Post-Resolution)

```
1. Access: http://10.0.20.186:3000
2. Login: admin / admin
3. Configuration > Data Sources > Add data source > Prometheus
4. URL: http://localhost:9090
5. Save & Test
6. Create > Import > Dashboard ID: 1860
7. Select Prometheus data source
8. Import
```

---

**Document Version**: 1.0
**Last Updated**: 2026-01-02
**Next Review**: After any Prometheus deployment or upgrade
**Document Owner**: Infrastructure Team
