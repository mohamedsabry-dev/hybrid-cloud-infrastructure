# Proxmox Mail Configuration (Gmail SMTP Relay)

## Prerequisites
- Gmail account with 2-Step Verification enabled
- Gmail App Password (not regular password)

## Get Gmail App Password
1. Go to Google Account → Security
2. 2-Step Verification → App passwords
3. Generate password for "Mail"
4. Copy the 16-character password (remove spaces)

## Setup Commands

```bash
# 1. Install SASL module
apt install libsasl2-modules -y

# 2. Create credentials file
echo "[smtp.gmail.com]:587 your-email@gmail.com:YOUR_APP_PASSWORD" > /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd

# 3. Configure postfix
postconf -e "relayhost = [smtp.gmail.com]:587"
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
postconf -e "smtp_sasl_security_options = noanonymous"

# 3b. (Optional) Remove deprecated setting if you see warnings about smtp_use_tls
postconf -X smtp_use_tls

# 4. Restart postfix
systemctl restart postfix

# 5. Test
echo "Test email from Proxmox" | mail -s "PVE Test" your-email@gmail.com
```

## Verify

```bash
# Check relayhost is set
postconf relayhost

# Check logs
journalctl -u postfix --since "1 minute ago"
```

## Expected Success Log

```
status=sent (250 2.0.0 OK)
relay=smtp.gmail.com[...]:587
```

## Troubleshooting

| Error | Fix |
|-------|-----|
| `No worthy mechs found` | `apt install libsasl2-modules -y` |
| `SASL authentication failed` | Check app password, regenerate if needed |
| `relay=gmail-smtp-in...:25` | relayhost not set, run postconf commands |
| `Network is unreachable (IPv6)` | Ignore, falls back to IPv4 |

## Apply to Both Nodes

Run these commands on both `pve-dev` and `pve-prod`.
