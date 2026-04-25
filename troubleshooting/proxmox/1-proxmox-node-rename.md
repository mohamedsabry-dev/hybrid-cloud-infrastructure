# TS-PVE-001 | 2026-02-04 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE / Node Management
Sub-techs: pve-cluster, pmxcfs, SSL certificates, hostname change, SQLite
Environment: Home lab, standalone Proxmox node | IP 192.168.0.120
Change: pve → pve-master (hostname), pve.lab.local → pve-master.lab.local
Re-opened: No

_____________________________________________________________________

[Issue Description]
Needed to rename Proxmox node and update SSL certificate SANs. First attempt
failed because I changed the hostname BEFORE stopping pve-cluster:

```
Changed hostname BEFORE stopping pve-cluster
pmxcfs failed to mount (/etc/pve/nodes/ disappeared)
Web UI became completely inaccessible
```

The cluster filesystem (pmxcfs) matches hostname to node directory. If they
mismatch, pmxcfs refuses to start and /etc/pve becomes unavailable.

_____________________________________________________________________

[Analysis]

I changed hostname with `hostnamectl` while pve-cluster was still running.
pmxcfs immediately failed because the node directory name no longer matched.
Web UI broke completely.

Recovery: reverted hostname back to "pve", restarted pve-cluster, then followed
the correct order.

_____________________________________________________________________

[Final Root Cause]
Hostname was changed before stopping pve-cluster. The cluster filesystem requires
hostname and node directory to match — changing hostname while pmxcfs is running
causes immediate failure.

_____________________________________________________________________

[Final Solution]

Stop pve-cluster BEFORE changing hostname. Full procedure:

```bash
# Step 1-2: Stop PVE services and cluster filesystem
systemctl stop pvedaemon pveproxy pvestatd
systemctl stop pve-cluster

# Step 3: Rename node in SQLite database
sqlite3 /var/lib/pve-cluster/config.db \
  "UPDATE tree SET name = 'pve-master' WHERE name = 'pve';"

# Step 4: Rename node config directory
mv /var/lib/pve-cluster/nodes/pve /var/lib/pve-cluster/nodes/pve-master 2>/dev/null; true

# Step 5: Set new hostname
hostnamectl set-hostname pve-master

# Step 6: Update /etc/hosts
# 127.0.0.1       localhost.localdomain localhost
# 192.168.0.120   pve-master.lab.local pve-master

# Step 7: Reboot
reboot
```

After reboot:
```bash
hostname                      # should return: pve-master
ls /etc/pve/nodes/            # should show: pve-master (only)
systemctl status pve-cluster  # should be: active
```

Regenerate SSL certificates:
```bash
rm /etc/pve/local/pve-ssl.pem /etc/pve/local/pve-ssl.key
pvecm updatecerts --force
systemctl restart pveproxy

openssl x509 -in /etc/pve/local/pve-ssl.pem -noout -text | grep -A1 "Subject Alternative Name"
# Expected: DNS:pve-master, DNS:pve-master.lab.local
```

Trust certificate on macOS client:
```bash
scp root@pve-master.lab.local:/etc/pve/pve-root-ca.pem ~/Desktop/pve-root-ca.pem
sudo security delete-certificate -c "Proxmox Virtual Environment" /Library/Keychains/System.keychain
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Desktop/pve-root-ca.pem
```

Recovery from failed attempt:
```bash
hostnamectl set-hostname pve          # revert to original
systemctl restart pve-cluster         # recover pmxcfs
# then follow correct order above
```

Verified: Yes — node renamed, SSL SANs updated, web UI accessible at new hostname.

_____________________________________________________________________

[Risk Level] HIGH

Wrong order causes web UI and cluster filesystem to break completely. Always
backup configs first. Do this on a fresh node with no VMs/CTs.

_____________________________________________________________________

[References]
- TS-PVE-002 — SSL certificate regeneration (similar process)
