# External NGINX Down (SPOF Test)
# Date: -
# Result: NOT TESTED

---

## Scope

Stop external nginx (ex-nginx LXC) - the SPOF for external traffic.
Confirm external access is blocked while internal cluster remains healthy.

---

## Steps

1. Stop nginx service on ex-nginx (10.0.65.10)
2. Check: App unreachable externally (confirmed SPOF)
3. Check: ex-nginx upstream health status
4. Check: least_conn behavior when backend workers change
5. Recovery: Start nginx service
6. Measure: Downtime duration
7. Check: App accessible again

---

## Commands

```bash
# Stop nginx
ssh root@ex-nginx 'systemctl stop nginx'

# Check external access
curl -I https://wordpress.lab.local

# Check upstream health
ssh root@ex-nginx 'cat /var/log/nginx/error.log | tail -20'

# Start nginx
ssh root@ex-nginx 'systemctl start nginx'
```

---

## Expected Behavior

- External access: DOWN (SPOF confirmed)
- Internal cluster: UP (unaffected)
- Recovery: Immediate on nginx start

---

## TODO

- [ ] Execute test
- [ ] Document evidence
- [ ] Measure downtime
