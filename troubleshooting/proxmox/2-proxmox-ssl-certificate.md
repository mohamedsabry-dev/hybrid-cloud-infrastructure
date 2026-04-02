# Case 2: Proxmox SSL Certificate — Wrong IP in SAN

## Status: RESOLVED
## Date: 2026-02-20
## Environment: Dev & Prod Proxmox servers

---

## Symptoms

After changing Proxmox management IP from `192.168.0.x` to `10.0.5.x`, the browser shows certificate warning. The certificate still contains the old IP in Subject Alternative Name (SAN).

## Root Cause

Proxmox reads the node IP from `/etc/hosts` when generating certificates. If `/etc/hosts` has the old IP, the certificate will have the wrong IP.

## Diagnosis

Check current certificate SAN:
```bash
openssl x509 -in /etc/pve/local/pve-ssl.pem -text | grep -A1 "Subject Alternative Name"
```

Wrong output (old IP):
```
IP Address:127.0.0.1, IP Address:192.168.0.58, DNS:pve-dev, DNS:pve-dev.lab.local
```

## Solution

### On Proxmox Server

**DEV (10.0.5.110):**
```bash
# Update /etc/hosts
sed -i 's/192.168.0.58/10.0.5.110/' /etc/hosts

# Regenerate certificate
pvecm updatecerts --force

# Restart proxy
systemctl restart pveproxy

# Verify new certificate
openssl x509 -in /etc/pve/local/pve-ssl.pem -text | grep -A1 "Subject Alternative Name"
# Should show: IP Address:10.0.5.110, DNS:pve-dev, DNS:pve-dev.lab.local
```

**PROD (10.0.5.100):**
```bash
sed -i 's/192.168.0.[0-9]*/10.0.5.100/' /etc/hosts
pvecm updatecerts --force
systemctl restart pveproxy
openssl x509 -in /etc/pve/local/pve-ssl.pem -text | grep -A1 "Subject Alternative Name"
```

### Trust CA on macOS

After fixing the certificate, trust the Proxmox root CA on macOS:

```bash
# Copy root CA from servers
scp root@pve-dev.lab.local:/etc/pve/pve-root-ca.pem ~/Desktop/pve-root-ca-dev.pem
scp root@pve-prod.lab.local:/etc/pve/pve-root-ca.pem ~/Desktop/pve-root-ca-prod.pem

# Add to System Keychain as trusted root
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Desktop/pve-root-ca-dev.pem
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Desktop/pve-root-ca-prod.pem

# Restart Chrome (fully quit and reopen)
```

### Verify Trust

```bash
security find-certificate -c "Proxmox Virtual Environment" /Library/Keychains/System.keychain
```

## Note

The `network-setup-dev.sh` and `network-setup-prod.sh` scripts now automatically update `/etc/hosts` and regenerate the certificate. This manual process is only needed if:
- The network setup script wasn't used
- Certificate needs regeneration for other reasons

---

## Commands Reference

```bash
# Check current certificate SAN
openssl x509 -in /etc/pve/local/pve-ssl.pem -text | grep -A1 "Subject Alternative Name"

# Update /etc/hosts with new IP
sed -i 's/OLD_IP/NEW_IP/' /etc/hosts

# Regenerate certificate
pvecm updatecerts --force

# Restart proxy service
systemctl restart pveproxy

# Trust CA on macOS
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Desktop/pve-root-ca.pem

# Find trusted cert on macOS
security find-certificate -c "Proxmox Virtual Environment" /Library/Keychains/System.keychain
```
