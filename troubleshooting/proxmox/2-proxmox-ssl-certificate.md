# TS-PVE-002 | 2026-02-20 | RESOLVED

## 1. Context
- System: Proxmox VE
- Environment: Dev & Prod Proxmox servers
- Related components: SSL certificates, /etc/hosts, pveproxy

## 2. Issue
- Symptom: After changing Proxmox management IP from `192.168.0.x` to `10.0.5.x`, browser shows certificate warning
- Error: Certificate still contains old IP in Subject Alternative Name (SAN)
```
IP Address:127.0.0.1, IP Address:192.168.0.58, DNS:pve-dev, DNS:pve-dev.lab.local
```

## 3. Analysis

**Check current certificate SAN:**
```bash
openssl x509 -in /etc/pve/local/pve-ssl.pem -text | grep -A1 "Subject Alternative Name"
```

**Finding:** Certificate shows old IP (192.168.0.58) instead of new IP (10.0.5.110)

**Why this happens:**
Proxmox reads the node IP from `/etc/hosts` when generating certificates. If `/etc/hosts` has the old IP, the certificate will have the wrong IP.

## 4. Root Cause
> Proxmox reads node IP from `/etc/hosts` when generating certificates. After IP change, `/etc/hosts` still had old IP, so regenerated certificate contained wrong SAN.

## 5. Solution
> Update /etc/hosts with new IP, then regenerate certificate.

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

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Brief pveproxy restart, web UI unavailable for a few seconds

## 7. Impact After Fix
- Observed: Certificate now contains correct IP in SAN
- Browser no longer shows certificate warnings
- macOS trusts the Proxmox CA

## 8. Notes

**Automation:**
The `network-setup-dev.sh` and `network-setup-prod.sh` scripts now automatically update `/etc/hosts` and regenerate the certificate. This manual process is only needed if:
- The network setup script wasn't used
- Certificate needs regeneration for other reasons

**Commands Reference:**
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

**Related:** TS-PVE-001 (node rename) - similar SSL certificate regeneration process

## 9. Workaround (if any)
> Temporarily bypass certificate warning in browser, but this is not recommended for production use.
