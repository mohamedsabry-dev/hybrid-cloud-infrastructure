# Troubleshooting

**Cross-Cutting Concern - Common Issues, Solutions, and Lessons Learned**

This section contains troubleshooting guides, common issues, and lessons learned across all layers of the infrastructure.

---

## Overview

This troubleshooting guide covers:
- Common issues by layer
- Root cause analysis
- Step-by-step solutions
- Lessons learned from mistakes
- Best practices to avoid issues

---

## Structure

### Common Issues by Layer

#### Layer 0: Infrastructure Foundation

**vCenter Connectivity Problems:**
- [01 - Installation Stage 2 Hang](cases/platform/01-vCenter-Installation-Stage2-Hang.md) - DNS resolution failure during installation
- [02 - SSO Authentication Error](cases/platform/02-vCenter-Authentication-Error-SSO.md) - Alias whitelist configuration
- [03 - Lifecycle Manager Depot Error](cases/platform/03-vCenter-Lifecycle-Manager-Depot-Error.md) - Deprecated update URLs
- [04 - Certificate Browser Errors](cases/platform/04-vCenter-Certificate-Browser-Error.md) - Cache and trust store issues
- [05 - Certificate Manager Failures](cases/platform/05-vCenter-Certificate-Manager-Replace-Failed.md) - Service health and disk space
- [06 - API SSL Verification Errors](cases/platform/06-vCenter-API-SSL-Error-After-Root-CA.md) - Python/PowerCLI/Ansible trust stores
- [10 - vCenter 8 vApp Config Not Persisting](cases/platform/10-vCenter8-vApp-Config-Not-Persisting.md) - Database transaction commit bug, direct DB workaround

**Windows Host Configuration Issues:**
- [08 - Sleep Mode Network Failure](cases/platform/08-Windows-Host-Sleep-Network-Break.md) - ESXi uplink down after laptop sleep/wake
- [09 - NAT vs Bridged Networking](cases/platform/09-Windows-Host-NAT-vs-Bridge.md) - Architectural comparison and migration guide

**Network Issues:**
- [04 - Promiscuous Mode for Nested Virtualization](cases/network/04-promiscuous-mode-nested.md) - Required for nested ESXi networking
- [05 - Duplicate Packets from Network Loops](cases/network/05-duplicate-packets-loop.md) - Uplink redundancy causing packet duplication
- [06 - pfSense Power Off Issues](cases/network/06-pfsense-poweroff.md) - pfSense VM shutdown problems
- [07 - Windows IP Forwarding Loops](cases/network/07-Windows-Host-Network-Loops.md) - Duplicate packets and ARP corruption
- [08 - Static Route Loop SSH Disconnect](cases/network/08-Static-Route-Loop-SSH-Disconnect.md) - Routing loops from duplicate static routes

**Storage Performance Issues:**
- [01 - VMDK Snapshot Corruption](cases/storage/01-vmdk-snapshot-corruption.md) - Snapshot chain breakage and recovery
- [02 - NAS Snapshot Sizing Failure](cases/storage/02-nas-snapshot-sizing-failure.md) - Insufficient space for snapshots
- [03 - Disk Race Condition Disaster](cases/storage/03-disk-race-condition-disaster.md) - /dev/sdX vs UUID mounting issues
- [06 - Thick to Thin Conversion](cases/storage/06-thick-to-thin-conversion.md) - Converting provisioning types
- [07 - NAS Memory Starvation](cases/storage/07-nas-memory-starvation.md) - I/O performance degradation
- [08 - VMware Snapshot Chain Corruption](cases/storage/08-VMware-Snapshot-Chain-Corruption.md) - Parent VMDK link breakage
- [09 - Thick Provisioned Snapshot Size](cases/storage/09-Thick-Provisioned-Snapshot-Size.md) - Massive snapshots from thick disks
- [10 - Application-Aware Backup Loop Device Errors](cases/storage/10-Application-Aware-Backup-Loop-Device-Errors.md) - Veeam AAP causing I/O errors during backups
- [11 - Snapshot Chain Corruption from Sleep Mode](cases/storage/11-Snapshot-Chain-Corruption-Sleep-Mode.md) - Laptop sleep during I/O causing 1TB disk inflation

#### Layer 1: Platform Services

**FreeIPA Authentication Failures:**
- [11 - Time Sync Clock Skew](cases/platform/11-FreeIPA-Time-Sync-Clock-Skew.md) - Kerberos "Clock skew too great" from VMware Tools time sync conflicts
- [12 - SSSD Cache Not Updating](cases/platform/12-FreeIPA-SSSD-Cache-Not-Updating.md) - HBAC/sudo rule changes not reflecting due to SSSD caching

**Other Platform Services:**
- DNS resolution issues
- NTP synchronization problems
- Ansible connectivity issues
- Keytab authentication failures

#### Layer 2: Application Workloads
- Kubernetes cluster issues
- Pod scheduling failures
- Storage mount issues
- Jenkins pipeline failures
- Grafana data source issues
- Vault unsealing problems

#### Layer 3: Cloud & Hybrid
- VPN connectivity issues
- AWS authentication failures
- Terraform state corruption
- Cross-cloud networking issues
- Secret synchronization failures

---

## Quick Reference

### "VM won't start"
1. Check ESXi host resources
2. Verify datastore connectivity
3. Check VM hardware compatibility
4. Review VM logs

### "Can't SSH to VM"
1. Check network connectivity
2. Verify IPA authentication
3. Check SSSD cache
4. Verify HBAC rules

### "DNS not resolving"
1. Check IPA DNS service
2. Verify /etc/resolv.conf
3. Test with nslookup/dig
4. Check firewall rules

### "Time sync issues"
1. Verify NTP hierarchy (Internet → IPA → VMs)
2. Check chronyd status
3. Force sync with `chronyc makestep`
4. Disable VMware Tools time sync

### "Ansible playbook fails"
1. Check inventory connectivity
2. Verify keytab authentication
3. Test manual SSH connection
4. Check sudo permissions

### "Kubernetes pod not starting"
1. Check node resources
2. Verify image pull
3. Review pod logs
4. Check persistent volume claims

---

## Common Issues and Solutions

### Issue: VMs showing as orphaned after host crash

**Symptoms:**
- VMs appear as "orphaned" in vCenter
- Cannot power on VMs
- vCenter shows invalid state

**Root Cause:**
- ESXi host crashed/restarted unexpectedly
- vCenter database sync issue

**Solution:**
1. Right-click orphaned VM
2. Select "Remove from Inventory"
3. Browse datastore
4. Right-click .vmx file
5. Select "Register VM"
6. Verify VM configuration
7. Power on VM

---

### Issue: User can SSH but sudo doesn't work

**Symptoms:**
- User can authenticate via SSH
- `sudo` command fails with permission denied
- User is in correct IPA group

**Root Cause:**
- SSSD cache not updated
- Sudo rules not properly configured in IPA

**Solution:**
1. Check sudo rules in IPA: `ipa sudorule-show <rule-name>`
2. Verify user group membership: `id <username>`
3. Clear SSSD cache: `sudo sssctl cache-expire -E`
4. Restart SSSD: `sudo systemctl restart sssd`
5. Test sudo again

---

### Issue: Keytab authentication fails for Ansible

**Symptoms:**
- Ansible playbooks fail with authentication error
- Manual kinit with keytab works
- SSH with password works

**Root Cause:**
- Keytab file permissions
- Keytab not in correct location
- Principal not authorized in IPA

**Solution:**
1. Verify keytab permissions: `ls -la /path/to/keytab`
2. Test keytab: `kinit -kt /path/to/keytab principal`
3. Check ticket: `klist`
4. Verify SSH config uses keytab
5. Check IPA host entry

---

### Issue: IPA DNS not resolving external domains

**Symptoms:**
- Internal .home.lab domains resolve
- External domains (google.com) fail
- VMs can't reach internet

**Root Cause:**
- DNS forwarders not configured in IPA
- Firewall blocking DNS queries

**Solution:**
1. Check IPA DNS forwarders: `ipa dnsconfig-show`
2. Add forwarders if missing: `ipa dnsconfig-mod --forwarder=10.0.20.170`
3. Check pfSense DNS settings
4. Test with: `dig @10.0.20.184 google.com`

---

### Issue: vApp auto-shutdown not working

**Symptoms:**
- vApp shutdown initiated but VMs don't stop
- VMs timeout during shutdown
- Shutdown order not respected

**Root Cause:**
- VMware Tools not installed
- Shutdown timeout too short
- Dependencies not configured

**Solution:**
1. Verify VMware Tools installed and running
2. Check vApp shutdown settings
3. Increase shutdown timeout (default 120s → 300s)
4. Verify shutdown order in vApp settings
5. Test shutdown manually

---

### Issue: Vault cluster won't unseal after restart

**Symptoms:**
- Vault sealed after restart
- Unseal operation fails
- Raft cluster out of sync

**Root Cause:**
- Majority of nodes offline
- Storage backend issues
- Raft consensus lost

**Solution:**
1. Check Vault service status on all nodes
2. Verify storage backend connectivity
3. Unseal with recovery keys (requires quorum)
4. If quorum lost, restore from backup
5. Check Raft peer list: `vault operator raft list-peers`

---

## Lessons Learned

### FreeIPA and Domain Users

**Mistake:**
Created domain user for Veeam backups, relying on IPA being always available.

**Problem:**
When IPA is down, domain users cached on some VMs but not others, causing inconsistent access.

**Solution:**
- Use local emergency users for critical operations
- Configure SSSD offline cache with long timeout
- Create emergency procedures for IPA outage
- Consider local `veeam_emergency` user on critical VMs

**Lesson:**
Don't create single points of failure in authentication. Always have a break-glass procedure.

---

### Backup User Authentication

**Mistake:**
Assuming all VMs would cache domain user credentials consistently.

**Problem:**
After testing IPA shutdown, user `admin2` worked on 1 VM but failed on 2 others, despite expired Kerberos tickets.

**Root Cause:**
SSSD caches users at different times based on when they first authenticate. VMs boot at different times, so cache timing varies.

**Solution:**
- Create local emergency users on all VMs
- Use Ansible playbook to deploy emergency accounts
- Document which operations require IPA vs local auth
- Test recovery procedures regularly

**Lesson:**
Test failure scenarios. Cached authentication behavior is complex and not always predictable.

---

### pfSense and Automation

**Mistake:**
Planning to manage pfSense with Ansible like other VMs.

**Problem:**
pfSense is critical network infrastructure. If Ansible VM or IPA is down, you lose access to pfSense if it requires domain authentication.

**Solution:**
- Create local root-privileged user on pfSense manually
- Don't make pfSense dependent on IPA
- Keep pfSense management separate from other automation
- Document manual procedures for pfSense

**Lesson:**
Critical infrastructure (network, identity) should not depend on each other for access.

---

### VMware Tools and Graceful Shutdown

**Mistake:**
Assuming VMs would shutdown gracefully without VMware Tools.

**Problem:**
vApp shutdown timeouts because VMs don't respond to soft shutdown signal.

**Solution:**
- Install VMware Tools on all VMs
- Verify Tools service running
- Test shutdown before relying on automation
- Increase timeout for database VMs

**Lesson:**
Automation depends on proper tooling. Verify prerequisites before assuming functionality.

---

### NTP and Time Drift

**Mistake:**
VMs syncing time from multiple sources (VMware Tools, public NTP, IPA).

**Problem:**
Inconsistent time causes Kerberos authentication to fail intermittently.

**Solution:**
- Single time source hierarchy: Internet → IPA → VMs
- Disable VMware Tools time sync
- Configure chronyd to only use IPA
- Monitor time drift with Ansible playbook

**Lesson:**
Time synchronization must be hierarchical and consistent. Multiple sources cause drift.

---

## Best Practices

### Do's
- Document everything as you build
- Test disaster recovery procedures monthly
- Use Infrastructure as Code (Ansible/Terraform)
- Keep engineering logs of failures
- Validate assumptions with tests
- Create break-glass procedures

### Don'ts
- Don't skip backup validation
- Don't create circular dependencies
- Don't assume caching works consistently
- Don't make critical services depend on each other
- Don't ignore warning signs in logs
- Don't skip testing shutdown/recovery

---

## Diagnostic Commands

### Network
```bash
# Test connectivity
ping -c 4 10.0.20.184

# Check DNS
nslookup ipa.home.lab
dig @10.0.20.184 ipa.home.lab

# Check routes
ip route show
```

### Authentication
```bash
# Check Kerberos ticket
klist

# Test IPA connection
kinit admin
ipa user-show admin

# Check SSSD status
sudo systemctl status sssd
sudo sssctl cache-expire -E
```

### Storage
```bash
# Check NFS mounts
df -h
mount | grep nfs

# Test NFS connectivity
showmount -e 10.0.20.90
```

### Kubernetes
```bash
# Check cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# Check node resources
kubectl top nodes
kubectl describe node <node-name>
```

---

## When to Escalate

Some issues require rebuilding or major intervention:
- Corrupted vCenter database
- Failed ESXi upgrade
- Corrupted IPA database
- Lost Vault unseal keys
- Multiple simultaneous failures

Document the issue, take snapshots if possible, and consider restore from backup.

---

## Case File Index

### Network Cases (5 cases)
- 04 - Promiscuous Mode for Nested Virtualization
- 05 - Duplicate Packets from Network Loops
- 06 - pfSense Power Off Issues
- 07 - Windows IP Forwarding Loops
- 08 - Static Route Loop SSH Disconnect

### Platform Cases (11 cases)
- 01-06 - vCenter Issues (Installation, SSO, Lifecycle Manager, Certificates)
- 08-09 - Windows Host Issues (Sleep/Wake, NAT vs Bridge)
- 10 - vCenter 8 vApp Configuration Bug
- 11-12 - FreeIPA Issues (Time Sync, SSSD Cache)

### Storage Cases (9 cases)
- 01 - VMDK Snapshot Corruption
- 02 - NAS Snapshot Sizing Failure
- 03 - Disk Race Condition Disaster
- 06 - Thick to Thin Conversion
- 07 - NAS Memory Starvation
- 08 - VMware Snapshot Chain Corruption
- 09 - Thick Provisioned Snapshot Size
- 10 - Application-Aware Backup Loop Device Errors
- 11 - Snapshot Chain Corruption from Sleep Mode

**Total Cases:** 25 documented troubleshooting scenarios

---

## References

- Main Documentation: [../00-DOCUMENTATION/](../00-DOCUMENTATION/)
- Engineering logs: `/Codes/Logs/`
- Ansible troubleshooting playbooks: `/Codes/Ansible-Playbooks/troubleshooting/`
