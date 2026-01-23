# FreeIPA Identity Management Architecture

> **Complete identity and access management infrastructure for DC-K8s lab environment**

---

## Overview

**Domain:** home.lab
**Realm:** HOME.LAB
**IPA Server:** ipa.home.lab (10.0.20.184)
**Platform:** Rocky Linux 10

This document provides a comprehensive summary of the FreeIPA identity management structure based on the five-phase deployment playbooks (ipa-01 through ipa-05).

---

## Phase 1: Identity Structure (Users & Groups)

**Playbook:** `ipa-01-create-users-groups.yml`

### Group Hierarchy

#### 1. operators (K8s Operators - Restricted Sudo)
- **Purpose:** Day-to-day operations with limited privileges
- **Members:** operator1, operator2
- **Privileges:** SSH + restricted sudo (network tools + log reading)

#### 2. monitors (Monitoring Service Accounts)
- **Purpose:** Monitoring and observability agents
- **Members:** monitor1, monitor2
- **Privileges:** No shell/API access only (future)

#### 3. k8s_admins (Full K8s Cluster Admins)
- **Purpose:** Complete administrative control over K8s cluster
- **Members:** admin1, admin2
- **Privileges:** Full sudo access on K8s nodes

#### 4. ansible_admins (Ansible Controller Admins)
- **Purpose:** Manage and maintain Ansible automation controllers
- **Members:** ansible_admin
- **Privileges:** Full sudo access on controller nodes

#### 5. super_users (Admins with Super Privileges)
- **Purpose:** Automation accounts requiring universal access
- **Members:** super_ansible
- **Privileges:** Full sudo access everywhere + passwordless sudo (!authenticate)

#### 6. backup_admins (Backup Administrators)
- **Purpose:** Backup and recovery operations
- **Members:** veeam
- **Privileges:** Full sudo access on all backup servers

#### 7. vault_admins (Vault Access Admins)
- **Purpose:** Manage and maintain HashiCorp Vault infrastructure
- **Members:** vault_admin1, vault_admin2
- **Privileges:** Full sudo access on Vault servers

#### 8. cicd_admins (CI/CD Pipeline Admins)
- **Purpose:** Manage CI/CD infrastructure and pipelines
- **Members:** cicd_admin1, cicd_admin2
- **Privileges:** Full sudo access on CI/CD servers

### User Accounts

**CI/CD Admins:**
- cicd_admin1 (CICD Admin One)
- cicd_admin2 (CICD Admin Two)
- Default Password: "Change_Me" (must change on first login)

**Operators (Restricted Sudo):**
- operator1 (Op One)
- operator2 (Op Two)
- Default Password: "Change_Me" (must change on first login)

**Monitoring Accounts (No Shell):**
- monitor1 (Mon One)
- monitor2 (Mon Two)
- Default Password: "Change_Me" (API access planned)

**Administrative Accounts:**
- admin1 (Admin One) → k8s_admins group
- admin2 (Admin Two) → k8s_admins group
- ansible_admin (Ansible Admin) → ansible_admins group

**Super User Automation:**
- super_ansible (Super Ansible) → super_users group
- Uses keytab authentication, passwordless sudo

**Backup Accounts:**
- veeam (Backup Veeam) → backup_admins group

**Vault Admins:**
- vault_admin1 (Vault Admin One) → vault_admins group
- vault_admin2 (Vault Admin Two) → vault_admins group

---

## Phase 2: Host Organization (Host Groups)

**Playbook:** `ipa-02-create-hostgroups.yml`

### Host Group Structure

#### 1. management (General Infrastructure - Legacy)
**Purpose:** Core infrastructure services
**Members:**
- ipa.home.lab
- ansible.home.lab

#### 2. k8s (Kubernetes Cluster Nodes)
**Purpose:** All Kubernetes cluster components
**Members:**
- k8s-master.home.lab
- k8s-worker1.home.lab
- k8s-worker2.home.lab
- k8s-worker3.home.lab

#### 3. controllers (Ansible Automation Controllers)
**Purpose:** Ansible control plane nodes
**Members:**
- ansible.home.lab

#### 4. backup_servers (Backup Servers Group)
**Purpose:** All systems requiring backup agent access
**Members:**
- ipa.home.lab
- ansible.home.lab
- k8s-master.home.lab
- k8s-worker1.home.lab
- k8s-worker2.home.lab
- k8s-worker3.home.lab
- monitor.home.lab
- vault-01.home.lab
- vault-02.home.lab
- vault-03.home.lab
- jenkins-master.home.lab

#### 5. monitors (Monitoring Servers Group)
**Purpose:** Dedicated monitoring infrastructure
**Members:**
- monitor.home.lab

#### 6. vault_servers (Vault Servers Group)
**Purpose:** HashiCorp Vault cluster nodes
**Members:**
- vault-01.home.lab
- vault-02.home.lab
- vault-03.home.lab

#### 7. cicd_servers (CI/CD Servers Group)
**Purpose:** Continuous Integration/Delivery infrastructure
**Members:**
- jenkins-master.home.lab

---

## Phase 3: Access Control (HBAC Rules)

**Playbook:** `ipa-03-configure-hbac-rules.yml`

HBAC (Host-Based Access Control) defines **WHO** can access **WHICH** hosts via **WHAT** service.

### HBAC Rule Matrix

| Rule Name | User Groups | Host Groups | Service | Effect |
|-----------|-------------|-------------|---------|--------|
| allow_k8s_ssh | operators, k8s_admins | k8s | sshd | Operators and k8s admins can SSH into all K8s nodes |
| allow_controller_ssh | ansible_admins | controllers | sshd | Ansible admins can SSH into Ansible controller nodes |
| allow_automation_ssh | super_users | k8s, controllers, management, backup_servers, vault_servers, cicd_servers | sshd | Automation account has universal SSH access |
| allow_backup_ssh | backup_admins | backup_servers | sshd | Backup users can access all systems for backup operations |
| allow_vault_ssh | vault_admins | vault_servers | sshd | Vault admins can access Vault cluster nodes |
| allow_cicd_ssh | cicd_admins | cicd_servers | sshd | CI/CD admins can access Jenkins infrastructure |

### Testing HBAC Rules

Test user access to specific hosts using:
```bash
ipa hbactest --user=<username> --host=<hostname> --service=sshd
```

**Examples:**
```bash
ipa hbactest --user=operator1 --host=k8s-master.home.lab --service=sshd
ipa hbactest --user=ansible_admin --host=ansible.home.lab --service=sshd
ipa hbactest --user=super_ansible --host=k8s-master.home.lab --service=sshd
ipa hbactest --user=vault_admin1 --host=vault-01.home.lab --service=sshd
```

---

## Phase 4: Privilege Management (Sudo Rules)

**Playbook:** `ipa-04-configure-sudo-rules.yml`

### Sudo Command Definitions

**Network Troubleshooting Commands:**
- `/usr/sbin/ip a` (View IP addresses)
- `/usr/sbin/ip route` (View routing table)
- `/usr/bin/ping` (Test connectivity)
- `/usr/sbin/ss -tulpn` (View listening ports)

**Log & File Reading Commands:**
- `/usr/bin/tail` (View end of files)
- `/usr/bin/grep` (Search file contents)
- `/usr/bin/less` (Page through files)
- `/usr/bin/cat /var/log/messages` (Read system log)
- `/usr/bin/cat /var/log/syslog` (Read syslog)

### Sudo Command Groups

**1. ops_network**
- Description: Network Troubleshooting Commands
- Commands: `/usr/sbin/ip a`, `/usr/sbin/ip route`, `/usr/bin/ping`, `/usr/sbin/ss -tulpn`

**2. ops_logs**
- Description: Log Reading Commands
- Commands: `/usr/bin/tail`, `/usr/bin/grep`, `/usr/bin/less`, `/usr/bin/cat /var/log/messages`, `/usr/bin/cat /var/log/syslog`

### Sudo Rule Definitions

| Rule Name | User Groups | Host Groups | Commands | Password | Effect |
|-----------|-------------|-------------|----------|----------|--------|
| admin_k8s_full | k8s_admins | k8s | ALL | Required | K8s admins have complete sudo access on K8s nodes |
| admin_ansible_full | ansible_admins | controllers | ALL | Required | Ansible admins have complete sudo access on controllers |
| ops_k8s_restricted | operators | k8s, controllers | ops_network, ops_logs | Required | Operators can run limited diagnostic commands |
| super_automation_nopass | super_users | k8s, controllers, management, backup_servers, vault_servers, cicd_servers | ALL | **NOT REQUIRED** | Automation account has passwordless sudo everywhere |
| backup_users_full | backup_admins | backup_servers | ALL | Required | Backup users have complete access for operations |
| vault_users_full | vault_admins | vault_servers | ALL | Required | Vault admins have complete access to Vault nodes |
| cicd_users_full | cicd_admins | cicd_servers | ALL | Required | CI/CD admins have complete access to Jenkins |

---

## Phase 5: DNS Resolution Configuration

**Playbook:** `ipa-05-updane-dns-resolution.yml`

### DNS Hierarchy

- **Primary DNS:** IPA Server (10.0.20.184)
- **Secondary DNS:** pfSense Gateway (10.0.20.170)
- **Domain:** home.lab

**Configuration:**
- All VMs (except IPA) configured via nmcli
- Connection: ens33 (Ethernet)
- DNS Servers: IPA primary, pfSense fallback
- Search Domain: home.lab

This playbook ensures all infrastructure VMs resolve internal FQDNs correctly and use IPA as the authoritative DNS server for the home.lab domain.

---

## Security Architecture Summary

### Access Control Layers

1. **HBAC Rules** → Control SSH access (who can login where)
2. **Sudo Rules** → Control privilege escalation (what commands can be run)

### Privilege Tiers

**Tier 1 - Restricted Operations:**
- operators group: SSH + limited sudo (network + logs)

**Tier 2 - Monitoring (API Only):**
- monitors group: Future API-only access for monitoring agents

**Tier 3 - Domain Administrators:**
- k8s_admins: Full sudo on K8s nodes
- ansible_admins: Full sudo on controllers
- vault_admins: Full sudo on Vault servers
- cicd_admins: Full sudo on CI/CD servers

**Tier 4 - Infrastructure Automation:**
- super_users: Passwordless sudo everywhere (!authenticate)

**Tier 5 - Specialized Services:**
- backup_admins: Full access to backup servers

### Authentication Methods

- **Interactive Users:** Password-based (must change default "Change_Me")
- **Automation (super_ansible):** Keytab-based, passwordless sudo
- **Monitors:** API tokens (planned)

### Key Security Features

- Centralized user management (no local accounts needed)
- Group-based access control
- Host-based access control (HBAC)
- Granular sudo privilege assignment
- Audit trail for all authentication events
- Kerberos SSO integration
- LDAP-based user directory

---

## Deployment Sequence

Execute playbooks in this order:

1. **ipa-01-create-users-groups.yml** - Creates all user accounts and group structure
2. **ipa-02-create-hostgroups.yml** - Organizes hosts into logical groups
3. **ipa-03-configure-hbac-rules.yml** - Defines SSH access policies
4. **ipa-04-configure-sudo-rules.yml** - Defines privilege escalation policies
5. **ipa-05-updane-dns-resolution.yml** - Configures DNS resolution to use IPA as primary DNS

All playbooks require IPA admin password at runtime.

---

## Verification Commands

### Users and Groups

```bash
# List all groups
ipa group-find

# Show group membership
ipa group-show <groupname>

# List all users
ipa user-find

# Show user details
ipa user-show <username>
```

### Host Groups

```bash
# List host groups
ipa hostgroup-find

# Show host group members
ipa hostgroup-show <hostgroup>
```

### HBAC Rules

```bash
# List HBAC rules
ipa hbacrule-find

# Show HBAC rule details
ipa hbacrule-show <rulename>

# Test HBAC access
ipa hbactest --user=<user> --host=<host> --service=sshd
```

### Sudo Rules

```bash
# List sudo rules
ipa sudorule-find

# Show sudo rule details
ipa sudorule-show <rulename>

# List sudo commands
ipa sudocmd-find

# Show sudo command groups
ipa sudocmdgroup-show <groupname>
```

### DNS Configuration

```bash
# Verify DNS resolution
cat /etc/resolv.conf
```

---

## Infrastructure Hosts

**Total Hosts:** 12

### Core Infrastructure
- **ipa.home.lab** (10.0.20.184) - FreeIPA server, NTP source, Primary DNS
- **ansible.home.lab** - Automation controller

### Kubernetes Cluster
- **k8s-master.home.lab** - Control plane
- **k8s-worker1.home.lab** - Worker node
- **k8s-worker2.home.lab** - Worker node
- **k8s-worker3.home.lab** - Worker node

### Monitoring
- **monitor.home.lab** - Observability stack

### HashiCorp Vault Cluster
- **vault-01.home.lab** - Vault node 1
- **vault-02.home.lab** - Vault node 2
- **vault-03.home.lab** - Vault node 3

### CI/CD Infrastructure
- **jenkins-master.home.lab** - Jenkins master/controller

---

## NTP Time Synchronization

### NTP Hierarchy

- **Stratum 1:** Internet NTP pools (Cloudflare, Google)
- **Stratum 2:** ipa.home.lab (IPA server as central time source)
- **Stratum 3:** All VMs sync to ipa.home.lab

**Configuration Playbook:** `/Codes/Ansible-Playbooks/IPA/fix_ntp_to_ipa.yml`
**DNS Verification Playbook:** `/Codes/Ansible-Playbooks/IPA/check_ipa_dns.yml`

**Critical:** VMware Tools time sync must be DISABLED on all VMs to prevent conflicts with chrony/NTP. See [troubleshooting case 11](../05-TROUBLESHOOTING/cases/platform/11-FreeIPA-Time-Sync-Clock-Skew.txt).

---

## Legacy Account Information

### Bootstrap Account: sshadmin

- **Purpose:** Initial IPA setup and emergency access
- **Status:** Legacy/deprecated for normal operations
- **Script:** `/Codes/Bash-Scripts/sshadmin-config-clean.sh`
- **Migration Path:** Use super_ansible for automation instead

### Production Account: super_ansible

- **Purpose:** Production automation and orchestration
- **Authentication:** Keytab-based (no password)
- **Privileges:** Passwordless sudo everywhere
- **Group:** super_users

---

## Manual Operations Guide

Each playbook includes detailed manual CLI equivalents for all operations. This allows administrators to:
- Understand what automation is doing
- Manually adjust configurations when needed
- Troubleshoot issues
- Verify automation results

**Example pattern in playbooks:**
```bash
# Manual equivalent:
#   kinit admin
#   ipa user-add user1 --first=User --last=One --password
#   ipa group-add-member users --users=user1
```

---

## Infrastructure Component Integration

This section covers integrating non-Linux infrastructure components (ESXi, vCenter) with the FreeIPA domain for DNS resolution, NTP synchronization, and centralized management.

### ESXi Host Integration

ESXi hosts cannot join IPA domain directly (not Linux-based, no SSSD/Kerberos client support). However, they can be integrated for DNS resolution, NTP synchronization, and hostname management.

#### Registered ESXi Hosts

**Production Environment:**
- esxi-prod-01.home.lab (10.0.20.101) - Nested ESXi production
- esxi-dr-01.home.lab (10.0.20.102) - Nested ESXi DR

**Host Layer:**
- esxi-master.home.lab (10.0.20.100) - Master ESXi hypervisor

#### Integration Procedure

**Step 1: Add ESXi Hostname to IPA DNS**

```bash
# On IPA server (ipa.home.lab)
# Add DNS A records for ESXi hosts
ipa dnsrecord-add home.lab esxi-prod-01 --a-rec=10.0.20.101
ipa dnsrecord-add home.lab esxi-dr-01 --a-rec=10.0.20.102
ipa dnsrecord-add home.lab esxi-master --a-rec=10.0.20.100

# Verify DNS records
dig esxi-prod-01.home.lab
dig esxi-dr-01.home.lab
dig esxi-master.home.lab
```

**Step 2: Configure ESXi DNS Resolution**

Priority order for DNS servers on ESXi:
1. IPA Server (10.0.20.184) - Primary, authoritative for home.lab
2. pfSense Gateway (10.0.20.170) - Secondary, has external DNS upstream
3. Home Router (192.168.0.1) - Tertiary, external fallback
4. Google DNS (8.8.8.8) - Final fallback

```bash
# SSH to ESXi host
ssh root@esxi-prod-01.home.lab

# Remove any existing DNS servers
esxcli network ip dns server remove --server=8.8.8.8
esxcli network ip dns server remove --server=1.1.1.1

# Add DNS servers in priority order
esxcli network ip dns server add --server=10.0.20.184  # IPA
esxcli network ip dns server add --server=10.0.20.170  # pfSense
esxcli network ip dns server add --server=192.168.0.1  # Home router
esxcli network ip dns server add --server=8.8.8.8      # Google DNS

# Verify DNS server order
esxcli network ip dns server list

# Output should show:
#   DNSServers: 10.0.20.184, 10.0.20.170, 192.168.0.1, 8.8.8.8
```

**Step 3: Set ESXi Hostname and Domain**

```bash
# Set FQDN
esxcli system hostname set --fqdn=esxi-prod-01.home.lab

# Set DNS search domain
esxcli network ip dns search add --domain=home.lab

# Verify configuration
esxcli system hostname get
esxcli network ip dns search list
esxcli network ip dns server list

# Test DNS resolution
ping ipa.home.lab
ping google.com
```

**Step 4: Configure NTP Synchronization to IPA**

```bash
# Set IPA as NTP server
esxcli system ntp set --server=ipa.home.lab

# Enable NTP service
esxcli system ntp set --enabled=true

# Verify NTP configuration
esxcli system ntp get

# Output should show:
#   Enabled: true
#   Servers: ipa.home.lab
#   Time Service Enabled: true

# Wait 3-5 minutes for initial sync
# Check synchronization status
esxcli system ntp get

# When synced, output will show:
#   Time Synchronized: true

# Verify current time
date
```

**Step 5: Repeat for All ESXi Hosts**

Execute Steps 1-4 for:
- esxi-dr-01.home.lab (10.0.20.102)
- esxi-master.home.lab (10.0.20.100)

#### ESXi NTP Dependency Considerations

**Production/DR ESXi (Nested):**
- Primary NTP source: IPA (ipa.home.lab)
- No additional NTP sources configured
- Rationale: Fully dependent on internal infrastructure, appropriate for nested environment

**Master ESXi (Host Layer):**
- Primary NTP source: IPA (ipa.home.lab)
- Secondary/Tertiary sources: External NTP (Cloudflare 1.1.1.1, Google 8.8.8.8)
- Rationale: Boots before IPA VM; needs external fallback for time sync during cold start

**Configuration (Master ESXi Only):**
```bash
# Already has IPA as primary from Step 4
# Add external NTP sources as fallback
esxcli system ntp set --server=1.1.1.1
esxcli system ntp set --server=8.8.8.8

# Verify all NTP sources
esxcli system ntp get
```

**Gateway Configuration:**
- ESXi Master: Uses home router IP (192.168.0.1) - can reach external NTP
- Nested ESXi: Uses pfSense gateway (10.0.20.170) - internal routing only

#### Resource Allocation Notes

During infrastructure consolidation, IPA VM memory was reduced from 29GB to 27GB to balance resources between production and DR ESXi hosts (each allocated 27GB).

### vCenter Integration

vCenter Server integrated with IPA domain for DNS resolution, NTP synchronization, and internal network routing.

**vCenter Details:**
- Hostname: vcenter.home.lab
- Management IP: 10.0.20.89 (internal network)
- Backup IP: 192.168.0.101 (external access - removed after migration)

#### Network Configuration Changes

**Original Configuration:**
- eth0: 192.168.0.101 (home network, management, has gateway)
- eth1: 10.0.20.89 (internal network, no gateway)

**Final Configuration:**
- eth0: Removed (eliminated external network exposure)
- eth1: 10.0.20.89 (internal network, management, has gateway)
- Gateway: 10.0.20.170 (pfSense internal gateway)

**Migration Process:**
1. Changed default gateway from 192.168.0.1 → 10.0.20.170
2. Reconfigured management network to use internal interface
3. Updated DNS servers to IPA primary
4. Removed external network interface (eth0)
5. Verified firewall rules updated after NIC removal

See troubleshooting cases:
- [13-vCenter-Backup-Failure-After-IP-Change](../05-TROUBLESHOOTING/cases/platform/13-vCenter-Backup-Failure-After-IP-Change.md)
- [14-vSphere-Lifecycle-Manager-Plugin-Download-Error](../05-TROUBLESHOOTING/cases/platform/14-vSphere-Lifecycle-Manager-Plugin-Download-Error.md)
- [15-vCenter-Firewall-Invalid-Interface-Error](../05-TROUBLESHOOTING/cases/platform/15-vCenter-Firewall-Invalid-Interface-Error.md)

#### vCenter DNS Configuration

**Script Path:** vCenter VAMI configuration script
**Access:** `dcui` → Configure Management Network → DNS Configuration

**DNS Servers (Priority Order):**
1. 10.0.20.184 (IPA - Primary)
2. 10.0.20.170 (pfSense - Secondary)
3. 192.168.0.1 (Home router - Tertiary fallback)

**Configuration Steps:**
```bash
# Access vCenter CLI via SSH or DCUI
# Navigate to network configuration
# Option 4: DNS Configuration
# Set DNS servers: 10.0.20.184, 10.0.20.170, 192.168.0.1
# Remove: 127.0.0.1, 8.8.8.8
```

#### vCenter DNS Record Registration

```bash
# On IPA server
ipa dnsrecord-add home.lab vcenter --a-rec=10.0.20.89

# Verify
dig vcenter.home.lab

# Test from vCenter
ping vcenter.home.lab  # Should resolve to 10.0.20.89, not 127.0.0.1
```

**Critical:** Ensure `/etc/hosts` on vCenter resolves `vcenter.home.lab` to real IP (10.0.20.89), NOT localhost (127.0.0.1 or ::1). This is required for plugin downloads and internal service communication.

#### vCenter Hostname Configuration

```bash
# Via VAMI script or DCUI
# Set hostname: vcenter.home.lab
# Set domain: home.lab
```

#### Post-Configuration Validation

**Verification Checklist:**
- [ ] vCenter accessible via https://vcenter.home.lab
- [ ] vCenter accessible via https://10.0.20.89
- [ ] DNS resolution working (ping ipa.home.lab)
- [ ] Gateway routing through pfSense (10.0.20.170)
- [ ] Backup jobs successful (if configured)
- [ ] vSphere Client plugins loading correctly
- [ ] No external network interface (192.168.0.x) configured

**Configuration State:**
- Management network: Internal only (10.0.20.x)
- Gateway: pfSense internal gateway (10.0.20.170)
- Hostname: vcenter.home.lab
- DNS: IPA primary, pfSense secondary
- NTP: IPA server (ipa.home.lab)
- Access: Via internal network or NAT through pfSense

### IPA VM Migration Between ESXi Hosts

#### Migration Scenario

**Source:** Nested Production ESXi (10.0.20.101)
**Destination:** Master ESXi (10.0.20.100)

**Reason for Migration:**
Original design kept IPA inside nested layer for redundancy (cluster + HA). Strategy changed to single production + DR model, making IPA a core component better suited for the outer layer alongside NAS, pfSense, Veeam, and vCenter.

#### Migration Challenge: Security Policy Mismatch

**Issue:** Live migration (vMotion) failed due to virtual switch security policy mismatch between source and destination.

**Root Cause:**
- Production nested ESXi: Security features DISABLED (promiscuous mode, forged transmits, MAC address changes)
- Master ESXi: Security features ENABLED on internal vSwitch

**Live migration requires matching security policies between source and destination port groups.**

#### Solution: Temporary Security Policy Alignment

**Step 1: Enable Security Features on Source (Temporary)**

On production nested ESXi (10.0.20.101):
```
vSphere Client > Networking > Virtual Switches > Select internal vSwitch/Port Group
Security:
- Promiscuous Mode: Accept (temporary)
- Forged Transmits: Accept (temporary)
- MAC Address Changes: Accept (temporary)
```

**Step 2: Perform Live Migration**

vSphere Client > Select IPA VM > Migrate > Change compute resource only
- Select Master ESXi as destination
- Perform live vMotion

**Step 3: Restore Security Policies (Post-Migration)**

On production nested ESXi (10.0.20.101):
```
Revert to secure configuration:
- Promiscuous Mode: Reject
- Forged Transmits: Reject
- MAC Address Changes: Reject
```

#### Alternative: Shutdown Migration

**Simpler approach if live migration not required:**

```bash
# Shutdown IPA VM
# Migrate VM (cold migration - no security policy matching required)
# Power on IPA VM on destination host
```

**Note:** Shutdown migration bypasses security policy requirements entirely but introduces brief downtime.

### Infrastructure Component Summary

**Domain-Integrated Components:**
- ESXi Master (10.0.20.100) - DNS, NTP (with external fallback)
- ESXi Production (10.0.20.101) - DNS, NTP
- ESXi DR (10.0.20.102) - DNS, NTP
- vCenter (10.0.20.89) - DNS, NTP, full integration

**Non-Domain Components:**
- pfSense FW - Uses built-in BSD domain; not added to home.lab to avoid breaking existing config
- NAS Storage - Pending integration
- Veeam (Windows) - Pending integration

**Integration Benefits:**
- Centralized DNS resolution for all infrastructure
- Synchronized time across environment (critical for Kerberos, logs)
- Consistent hostname management
- Simplified troubleshooting (single DNS source of truth)

---

## Related Documentation

- **Main Project Overview:** [PROJECT-OVERVIEW.md](PROJECT-OVERVIEW.md)
- **Network Architecture:** [Design/02-Network-Architecture.md](Design/02-Network-Architecture.md)
- **Storage Architecture:** [Design/03-Storage-Architecture.md](Design/03-Storage-Architecture.md)
- **Troubleshooting Cases:** [../05-TROUBLESHOOTING/](../05-TROUBLESHOOTING/)

**Ansible Playbooks Location:** `/DC-K8s/Codes/Ansible-Playbooks/IPA/`
**Bash Scripts Location:** `/DC-K8s/Codes/Bash-Scripts/`
**Manual Commands Guide:** `/DC-K8s/Codes/Ansible-Playbooks/IPA/MANUAL-COMMANDS-GUIDE.txt`

---

**Last Updated:** January 2026
**Deployment Status:** Production (All 12 hosts enrolled + ESXi/vCenter infrastructure integrated)
