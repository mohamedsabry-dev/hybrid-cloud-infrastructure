# TS-PVE-001 | 2026-02-04 | RESOLVED

## 1. Context
- System: Proxmox VE 8.1.5, single node
- Environment: Home lab, standalone node
- Related components: pve-cluster, pmxcfs, SSL certificates, DNS

**Change Required:**
- Old hostname: pve → New hostname: pve-master
- Old domain: pve.lab.local → New domain: pve-master.lab.local
- IP: 192.168.0.120

## 2. Issue
- Symptom: Need to rename Proxmox node and update SSL certificate SANs to match new domain
- Error (first attempt):
```
Changed hostname BEFORE stopping pve-cluster
pmxcfs failed to mount (/etc/pve/nodes/ disappeared)
Web UI became completely inaccessible
```

## 3. Analysis

**What Went Wrong (First Attempt):**
1. Changed hostname with `hostnamectl` BEFORE stopping pve-cluster
2. This caused pmxcfs to fail mounting (/etc/pve/nodes/ disappeared)
3. Web UI became completely inaccessible
4. Fix: reverted hostname back to "pve", restarted pve-cluster, then followed correct order

**Why Order Matters:**
- The cluster filesystem (pmxcfs) matches the hostname to the node directory
- If hostname and node directory mismatch, pmxcfs refuses to start
- /etc/pve becomes unavailable, breaking the web UI

## 4. Root Cause
> Hostname was changed before stopping pve-cluster. The cluster filesystem requires hostname and node directory to match - changing hostname while pmxcfs is running causes immediate failure.

## 5. Solution
> Stop pve-cluster BEFORE changing hostname. Follow exact order below.

### Warning
- Do this on a fresh node with NO VMs/CTs, or back up all configs first
- Do NOT change the hostname before stopping pve-cluster
- The correct order matters - follow the steps exactly

### Procedure (via SSH on the Proxmox host)

**Step 1: Stop PVE services**
```bash
systemctl stop pvedaemon pveproxy pvestatd
```

**Step 2: Stop the cluster filesystem**
```bash
systemctl stop pve-cluster
```

**Step 3: Rename the node in the SQLite database**
```bash
sqlite3 /var/lib/pve-cluster/config.db \
  "UPDATE tree SET name = 'pve-master' WHERE name = 'pve';"
```

**Step 4: Rename the node config directory on disk**
```bash
mv /var/lib/pve-cluster/nodes/pve /var/lib/pve-cluster/nodes/pve-master 2>/dev/null; true
```

**Step 5: Set the new hostname**
```bash
hostnamectl set-hostname pve-master
```

**Step 6: Update /etc/hosts**
```
127.0.0.1       localhost.localdomain localhost
192.168.0.120   pve-master.lab.local pve-master
```

**Step 7: Reboot**
```bash
reboot
```

**Step 8: After reboot - verify via SSH**
```bash
hostname                      # should return: pve-master
ls /etc/pve/nodes/            # should show: pve-master (only)
systemctl status pve-cluster  # should be: active
```

**Step 9: Regenerate SSL certificates**
```bash
rm /etc/pve/local/pve-ssl.pem /etc/pve/local/pve-ssl.key
pvecm updatecerts --force
systemctl restart pveproxy
```

**Step 10: Verify the new cert SANs**
```bash
openssl x509 -in /etc/pve/local/pve-ssl.pem -noout -text | grep -A1 "Subject Alternative Name"
# Expected: DNS:pve-master, DNS:pve-master.lab.local
```

**Step 11: Trust the certificate on macOS client**
```bash
# Download the root CA
scp root@pve-master.lab.local:/etc/pve/pve-root-ca.pem ~/Desktop/pve-root-ca.pem

# Remove old trusted cert
sudo security delete-certificate -c "Proxmox Virtual Environment" /Library/Keychains/System.keychain

# Add the new one
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Desktop/pve-root-ca.pem
```

**Step 12: Update /etc/hosts on macOS client**
```
192.168.0.120   pve-master.lab.local
```

**Step 13: Restart Chrome and access**
```
https://pve-master.lab.local:8006
```

## 6. Solution Risk
- Risk level: HIGH
- Potential impact: Wrong order causes web UI and cluster filesystem to break completely. Always backup configs first.

## 7. Impact After Fix
- Observed: Node renamed successfully
- SSL certificate SANs updated to new domain
- Web UI accessible at new hostname

## 8. Notes

**Key Takeaway:**
Always stop pve-cluster BEFORE changing the hostname. The cluster filesystem matches the hostname to the node directory - if they mismatch, pmxcfs refuses to start and /etc/pve becomes unavailable.

**Recovery from failed attempt:**
1. Revert hostname back to original: `hostnamectl set-hostname pve`
2. Restart pve-cluster: `systemctl restart pve-cluster`
3. Follow the correct order above

## 9. Workaround (if any)
> If pmxcfs fails to mount: Revert hostname to match node directory name, then restart pve-cluster. Once recovered, follow the correct procedure.
