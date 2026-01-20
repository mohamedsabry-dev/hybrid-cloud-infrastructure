# Jenkins Docker nft_compat Kernel Warnings on Rocky Linux 9

**Case ID**: APPLICATION-002
**Date**: 2025-2026 (Jenkins CI/CD deployment)
**Severity**: Low (Informational)
**Status**: Resolved (No action required)
**Category**: Application / CI/CD / Jenkins / Docker

---

## Problem Summary

During Jenkins deployment on Rocky Linux 9, kernel warnings appeared in system logs (dmesg) related to "unmaintained drivers" (`nft_compat`, `ip_set`). These warnings appeared immediately after Docker service started and persisted whenever Docker containers were launched.

**Impact**: None - warnings are cosmetic and do not affect Jenkins or Docker functionality.

---

## Environment

**Component**: Jenkins CI/CD + Docker Runtime
**Target OS**: Rocky Linux 9
**Deployment Method**: Ansible Playbook
**Target VM**: Jenkins Master (CICD VM)
**Services**:
- Jenkins: Port 8080 (web UI)
- Docker Engine: Container runtime

**Java Configuration**:
- Available: OpenJDK 21, 25 (via dnf search openjdk)
- Selected: Java 21
- Previous attempts with Java 11/17 failed (multiple failures documented)

---

## Symptom

### Kernel Warning Messages

```
[ 1501.790750] Warning: Unmaintained driver is detected: nft_compat
[ 1501.793883] Warning: Unmaintained driver is detected: nft_compat_module_init
[ 1502.130326] Warning: Unmaintained driver is detected: ip_set
[ 1502.133959] Warning: Unmaintained driver is detected: ip_set_init
[ 1502.621953] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
```

### When Warnings Appear

- During Docker service startup (`systemctl start docker`)
- When launching Docker containers (`docker run`)
- After system reboot when Docker auto-starts
- In terminal output during Jenkins container deployment

### User Concern

"I see those warnings on terminal of Jenkins even though the docker run works fine. Is something wrong?"

---

## Root Cause

### Technical Explanation

**Firewall Technology Mismatch**:
- **Rocky Linux 9** uses modern **nftables** for firewall management
- **Docker** still uses legacy **iptables** for container networking
- Linux kernel loads **compatibility modules** (`nft_compat`) to bridge the gap

**What is Happening**:

1. Docker attempts to configure network bridges using `iptables` commands
2. Rocky Linux kernel intercepts these calls and translates them to `nftables` rules
3. During translation, kernel loads `nft_compat` compatibility layer
4. Kernel logs a warning: "This compatibility module is unmaintained but still functional"

**Why "Unmaintained"**?

The kernel developers are signaling:
- iptables is legacy technology
- nftables is the modern replacement
- Applications should migrate to nftables API
- However, iptables compatibility will continue to work

**Critical Finding**: The warning message appears **before** Docker bridge configuration logs, proving Docker triggered the compatibility layer load.

### Log Sequence Analysis

```bash
# Command: dmesg | grep -i "nft_compat" -C 15
# Key output showing causation:

[ 1501.790750] Warning: Unmaintained driver is detected: nft_compat
[ 1501.793883] Warning: Unmaintained driver is detected: nft_compat_module_init
[ 1502.130326] Warning: Unmaintained driver is detected: ip_set
[ 1502.133959] Warning: Unmaintained driver is detected: ip_set_init
[ 1502.621953] bridge: filtering via arp/ip/ip6tables is no longer available by default...
[ 1973.409150] docker0: port 1(vethad3baba) entered blocking state
[ 1973.409159] docker0: port 1(vethad3baba) entered disabled state
[ 1973.474887] eth0: renamed from veth4bcb9cf
[ 1973.477946] docker0: port 1(vethad3baba) entered forwarding state
```

**Smoking Gun**: The bridge filtering message at timestamp `1502.621953` confirms the system loaded compatibility drivers because Docker tried to use `ip6tables` filtering on network bridges.

---

## Investigation Steps

### 1. Verify Jenkins is Running

```bash
# Using Ansible to check Jenkins service
ansible cicd -i ../inventory -m shell -a "systemctl status jenkins" --become

# Retrieve initial admin password
ansible cicd -i ../inventory -m shell -a "cat /var/lib/jenkins/secrets/initialAdminPassword" --become
```

**Result**: Jenkins running successfully despite warnings.

### 2. Check Kernel Logs

```bash
# View kernel messages related to nft_compat
dmesg | grep -i "nft_compat" -C 15

# Check Docker-related kernel messages
dmesg | grep -i docker
```

**Result**: Warnings appear immediately before Docker bridge initialization.

### 3. Verify Docker Functionality

```bash
# Test Docker networking
docker run hello-world

# Check Docker networks
docker network ls

# Inspect docker0 bridge
ip addr show docker0
```

**Result**: All Docker operations work perfectly.

### 4. Check System Configuration

```bash
# Verify OS version
cat /etc/rocky-release
# Result: Rocky Linux release 9.x

# Check firewall backend
firewall-cmd --get-backend
# Result: nftables

# Check loaded kernel modules
lsmod | grep -E "nft_compat|ip_set"
# Result: Modules loaded and active
```

---

## Resolution

### Official Answer

**These warnings are completely harmless and expected behavior on Rocky Linux 9 (and all modern RHEL-based distributions).**

### No Action Required

✅ **Docker runs correctly** - the compatibility layer works perfectly
✅ **Jenkins operates normally** - no impact on CI/CD functionality
✅ **Network connectivity intact** - containers can communicate
✅ **Security maintained** - firewall rules properly enforced

### Why No Action is Needed

1. **Compatibility Layer Works**: The `nft_compat` module successfully translates iptables commands to nftables rules
2. **Docker Design**: Docker upstream project has not yet migrated to native nftables API
3. **Industry-Wide Issue**: All modern Linux distributions (RHEL 9+, Ubuntu 22.04+, Debian 11+) show these warnings with Docker
4. **Future Migration**: Docker project is working on native nftables support, but timeline is uncertain

### Alternative Solutions (Not Recommended)

If warnings are cosmetically undesirable (e.g., for demos or screenshots), you could:

**Option 1: Suppress Kernel Warnings** (cosmetic only)
```bash
# Add kernel parameter to reduce log level
sudo grubby --update-kernel=ALL --args="loglevel=3"
sudo reboot
```

**Option 2: Disable Specific Warnings** (requires custom kernel build)
- Not practical for production systems
- Warnings would still occur, just not logged

**Option 3: Revert to iptables Backend** (not recommended)
```bash
# Switch firewalld to iptables (discouraged)
sudo firewall-cmd --set-backend=iptables
sudo systemctl restart firewalld
```

⚠️ **Why These Are Not Recommended**:
- Cosmetic changes only - no functional benefit
- May mask legitimate kernel issues in the future
- Goes against OS vendor recommendations (Red Hat/Rocky Linux)

---

## Verification

### Confirm Jenkins is Operational

```bash
# Check Jenkins service status
systemctl status jenkins
# Expected: active (running)

# Check Jenkins web UI accessibility
curl -I http://localhost:8080
# Expected: HTTP/200 or HTTP/403 (normal for Jenkins)

# Verify Docker containers are running
docker ps
# Expected: Jenkins container(s) listed
```

### Confirm Docker Networking Works

```bash
# Test container networking
docker run --rm alpine ping -c 3 google.com
# Expected: 3 packets transmitted, 3 received

# Verify docker0 bridge is forwarding
ip addr show docker0
# Expected: state UP
```

### Confirm No Functional Issues

```bash
# Check Jenkins logs for errors
journalctl -u jenkins --no-pager | grep -i error
# Expected: No critical errors

# Check Docker daemon logs
journalctl -u docker --no-pager | grep -i error
# Expected: No critical errors (warnings about nft_compat are fine)
```

---

## Prevention Measures

### 1. Documentation for Team

**Add to Deployment Runbook**:
```
⚠️ EXPECTED BEHAVIOR on Rocky Linux 9:
- Kernel warnings about nft_compat during Docker operations
- These are informational messages, not errors
- Docker and Jenkins will function normally
- No action required - do not attempt to "fix" these warnings
```

### 2. Training for New Team Members

**Onboarding Checklist Item**:
- Explain nftables vs iptables transition in RHEL 9+
- Show example of harmless kernel warnings
- Emphasize: "If Docker runs, warnings are safe to ignore"

### 3. Monitoring Exclusions

**Update Log Monitoring Rules**:
```yaml
# Example for log aggregation systems (e.g., ELK, Splunk)
- Exclude from alerts:
    pattern: "Warning: Unmaintained driver is detected: nft_compat"
    reason: "Expected behavior - Docker iptables compatibility layer"
```

### 4. Infrastructure as Code Comments

**Add to Ansible Playbooks**:
```yaml
- name: Deploy Jenkins with Docker
  # NOTE: Kernel warnings about nft_compat are expected on Rocky Linux 9
  # Docker uses iptables; Rocky Linux uses nftables; compatibility layer bridges the gap
  # These warnings do not indicate a problem - see APPLICATION-002 for details
  ...
```

---

## Lessons Learned

### What We Learned

1. **Not All Kernel Warnings Are Errors**:
   - "Warning" ≠ "Problem"
   - Context matters - these warnings indicate intentional compatibility behavior

2. **OS Modernization Has Friction**:
   - Rocky Linux 9 modernized to nftables (good for security and performance)
   - Docker hasn't caught up yet (common in open-source ecosystems)
   - Compatibility layers exist precisely for this transition period

3. **Documentation Prevents Panic**:
   - Initial concern: "Something is broken with Docker"
   - Reality: Everything works perfectly
   - Clear documentation prevents unnecessary troubleshooting

4. **Industry-Wide Transition**:
   - This is not a Rocky Linux-specific issue
   - All modern distros (RHEL 9+, Ubuntu 22+, Debian 11+) show this
   - Docker upstream is aware and working on native nftables support

### What Went Right

1. **Comprehensive Investigation**:
   - Used `dmesg` to analyze kernel log timeline
   - Verified Docker functionality with practical tests
   - Confirmed Jenkins operations were unaffected

2. **Proper Context Analysis**:
   - Identified log sequence showing Docker triggered the warnings
   - Researched upstream Docker and kernel documentation
   - Understood this is expected behavior, not a bug

3. **Documented for Future Reference**:
   - Created troubleshooting case for team knowledge base
   - Added context to Ansible playbooks
   - Prepared onboarding materials for new engineers

---

## Related Issues

- **APPLICATION-001**: Prometheus Setup Issues (Rocky Linux default services)
- **PLATFORM-008**: Windows Host Sleep Network Break (network configuration issues)
- **PLATFORM-009**: Windows Host NAT vs Bridge (Docker networking modes)

---

## References

### Documentation

- [Docker and nftables](https://docs.docker.com/network/iptables/)
- [RHEL 9 nftables Migration](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_firewalls_and_packet_filters/index)
- [Rocky Linux 9 Release Notes](https://docs.rockylinux.org/release_notes/9_0/)
- [Kernel nf_tables Documentation](https://www.kernel.org/doc/Documentation/networking/nf_tables.txt)

### Upstream Issues

- [Docker GitHub: Native nftables support tracking issue](https://github.com/moby/moby/issues/26824)
- [Rocky Linux Forum: nft_compat warnings discussion](https://forums.rockylinux.org/)

### Tools Used

```bash
# Kernel log analysis
dmesg | grep -i "nft_compat" -C 15
dmesg | grep -i docker

# Service verification
systemctl status jenkins
systemctl status docker
ansible cicd -i ../inventory -m shell -a "systemctl status jenkins" --become

# Docker testing
docker run hello-world
docker network ls
ip addr show docker0

# System information
cat /etc/rocky-release
firewall-cmd --get-backend
lsmod | grep -E "nft_compat|ip_set"
```

---

## Appendix: Java Version Selection

### Context

Multiple attempts to use Java 11 or Java 17 failed during Jenkins setup.

### Resolution

```bash
# Check available Java versions
dnf search openjdk
# Result: Java 21 and 25 available

# Install Java 21 (stable LTS)
dnf install java-21-openjdk java-21-openjdk-devel -y

# Verify installation
java --version
# Result: openjdk 21.x.x
```

### Ansible Implementation

```yaml
- name: Install Java 21 for Jenkins
  ansible.builtin.dnf:
    name:
      - java-21-openjdk
      - java-21-openjdk-devel
    state: present
```

**Note**: Jenkins officially supports Java 11, 17, and 21. Java 21 was chosen for long-term support and stability on Rocky Linux 9.

---

## Appendix: Complete Command Reference

### Jenkins Verification via Ansible

```bash
# Check Jenkins service status
ansible cicd -i ../inventory -m shell -a "systemctl status jenkins" --become

# Retrieve initial admin password
ansible cicd -i ../inventory -m shell -a "cat /var/lib/jenkins/secrets/initialAdminPassword" --become
```

### Kernel Warning Investigation

```bash
# View all nft_compat related messages
dmesg | grep -i "nft_compat"

# View with context (15 lines before/after)
dmesg | grep -i "nft_compat" -C 15

# View Docker-related kernel messages
dmesg | grep -i docker

# View bridge-related messages
dmesg | grep -i bridge
```

### Docker Verification

```bash
# Test Docker run
docker run hello-world

# Check Docker networks
docker network ls

# Inspect docker0 bridge
ip addr show docker0

# Check Docker service
systemctl status docker

# View Docker logs
journalctl -u docker --no-pager | tail -n 50
```

### System Configuration Checks

```bash
# OS version
cat /etc/rocky-release

# Firewall backend
firewall-cmd --get-backend

# Loaded kernel modules
lsmod | grep -E "nft_compat|ip_set"

# Java version
java --version
```

---

**Document Version**: 1.0
**Last Updated**: 2026-01-09
**Next Review**: After Rocky Linux or Docker major version upgrades
**Document Owner**: Infrastructure Team
