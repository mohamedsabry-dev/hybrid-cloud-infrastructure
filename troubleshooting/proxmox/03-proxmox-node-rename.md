# Troubleshooting: Proxmox Node Rename

## Case: Rename Proxmox Node and Update Domain Name

**Date:** 2026-02-04
**Status:** RESOLVED

---

## Environment

- Proxmox VE 9.1.5, single node
- Old hostname: pve
- Old domain: pve.lab.local
- New hostname: pve-master
- New domain: pve-master.lab.local
- IP: 192.168.0.120

---

## Goal

Rename the Proxmox node from "pve" to "pve-master" and update the
SSL certificate SANs to match, so the web UI is trusted under the
new domain.

---

## Warning

- Do this on a fresh node with NO VMs/CTs, or back up all configs first
- Do NOT change the hostname before stopping pve-cluster, or the
  cluster filesystem (pmxcfs) will fail to mount and the web UI breaks
- The correct order matters - follow the steps exactly

---

## Procedure (via SSH on the Proxmox host)

### Step 1: Stop PVE services
```bash
systemctl stop pvedaemon pveproxy pvestatd
```

### Step 2: Stop the cluster filesystem
```bash
systemctl stop pve-cluster
```

### Step 3: Rename the node in the SQLite database
```bash
sqlite3 /var/lib/pve-cluster/config.db \
  "UPDATE tree SET name = 'pve-master' WHERE name = 'pve';"
```

### Step 4: Rename the node config directory on disk
```bash
mv /var/lib/pve-cluster/nodes/pve /var/lib/pve-cluster/nodes/pve-master 2>/dev/null; true
```

### Step 5: Set the new hostname
```bash
hostnamectl set-hostname pve-master
```

### Step 6: Update /etc/hosts

Edit /etc/hosts to read:
```
127.0.0.1       localhost.localdomain localhost
192.168.0.120   pve-master.lab.local pve-master
```

### Step 7: Reboot
```bash
reboot
```

### Step 8: After reboot - verify via SSH
```bash
hostname                      # should return: pve-master
ls /etc/pve/nodes/            # should show: pve-master (only)
systemctl status pve-cluster  # should be: active
```

### Step 9: Regenerate SSL certificates
```bash
rm /etc/pve/local/pve-ssl.pem /etc/pve/local/pve-ssl.key
pvecm updatecerts --force
systemctl restart pveproxy
```

### Step 10: Verify the new cert SANs
```bash
openssl x509 -in /etc/pve/local/pve-ssl.pem -noout -text | grep -A1 "Subject Alternative Name"
# Expected: DNS:pve-master, DNS:pve-master.lab.local
```

### Step 11: Trust the certificate on macOS client
```bash
# Download the root CA
scp root@pve-master.lab.local:/etc/pve/pve-root-ca.pem ~/Desktop/pve-root-ca.pem

# Remove old trusted cert
sudo security delete-certificate -c "Proxmox Virtual Environment" /Library/Keychains/System.keychain

# Add the new one
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Desktop/pve-root-ca.pem
```

### Step 12: Update /etc/hosts on macOS client

Add to /etc/hosts:
```
192.168.0.120   pve-master.lab.local
```

### Step 13: Restart Chrome and access
```
https://pve-master.lab.local:8006
```

---

## What Went Wrong (First Attempt)

- Changed hostname with hostnamectl BEFORE stopping pve-cluster
- This caused pmxcfs to fail mounting (/etc/pve/nodes/ disappeared)
- Web UI became completely inaccessible
- Fix: reverted hostname back to "pve", restarted pve-cluster,
  then followed the correct order above

---

## Key Takeaway

Always stop pve-cluster BEFORE changing the hostname. The cluster
filesystem matches the hostname to the node directory - if they
mismatch, pmxcfs refuses to start and /etc/pve becomes unavailable.
