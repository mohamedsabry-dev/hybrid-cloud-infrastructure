# TS-PVE-002 | 2026-02-20 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE / SSL Certificates
Sub-techs: pveproxy, SSL SAN, /etc/hosts, pvecm updatecerts, macOS Keychain
Environment: DEV & PROD Proxmox servers
Re-opened: No

_____________________________________________________________________

[Issue Description]
After changing Proxmox management IP from `192.168.0.x` to `10.0.5.x`, browser
showed certificate warning. Certificate still had old IP in SAN:

```
IP Address:127.0.0.1, IP Address:192.168.0.58, DNS:pve-dev, DNS:pve-dev.lab.local
```

_____________________________________________________________________

[Analysis]

```bash
openssl x509 -in /etc/pve/local/pve-ssl.pem -text | grep -A1 "Subject Alternative Name"
```

Certificate showed old IP (192.168.0.58) instead of new IP (10.0.5.110).

Proxmox reads the node IP from `/etc/hosts` when generating certificates. After
the IP change, `/etc/hosts` still had the old IP.

_____________________________________________________________________

[Final Root Cause]
Proxmox reads node IP from `/etc/hosts` when generating certificates. After IP
change, `/etc/hosts` still had old IP, so regenerated certificate contained wrong
SAN.

_____________________________________________________________________

[Final Solution]

DEV (10.0.5.110):
```bash
sed -i 's/192.168.0.58/10.0.5.110/' /etc/hosts
pvecm updatecerts --force
systemctl restart pveproxy
openssl x509 -in /etc/pve/local/pve-ssl.pem -text | grep -A1 "Subject Alternative Name"
# Should show: IP Address:10.0.5.110, DNS:pve-dev, DNS:pve-dev.lab.local
```

PROD (10.0.5.100):
```bash
sed -i 's/192.168.0.[0-9]*/10.0.5.100/' /etc/hosts
pvecm updatecerts --force
systemctl restart pveproxy
```

Trust CA on macOS:
```bash
scp root@pve-dev.lab.local:/etc/pve/pve-root-ca.pem ~/Desktop/pve-root-ca-dev.pem
scp root@pve-prod.lab.local:/etc/pve/pve-root-ca.pem ~/Desktop/pve-root-ca-prod.pem
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Desktop/pve-root-ca-dev.pem
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Desktop/pve-root-ca-prod.pem
```

The `network-setup-dev.sh` and `network-setup-prod.sh` scripts now automatically
update `/etc/hosts` and regenerate the certificate. This manual process is only
needed if the network setup script wasn't used.

Verified: Yes — certificate contains correct IP in SAN, browser shows no warnings.

_____________________________________________________________________

[Risk Level] LOW

Brief pveproxy restart, web UI unavailable for a few seconds.

_____________________________________________________________________

[References]
- TS-PVE-001 — node rename (similar SSL certificate regeneration process)
