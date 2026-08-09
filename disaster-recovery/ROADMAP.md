Tests Planned for Later

=========================================================
[Linux DR Plan] [June -July]

1. Node keeps crashing after boot (kernel panic vs service crash-loop vs OOM kill — identify which)
2. Critical config directory wiped (/etc) — restore from backup/git
3. All nodes can't resolve DNS — resolver/FreeIPA DNS failure
4. Some/all users can't login (SSH/GUI) — Kerberos/SSSD auth chain investigation
5. Node can't boot at all / boots into maintenance mode
6. Node has low performance — isolate CPU vs memory vs IO bottleneck
7. Storage drive missing — NFS/LVM impact investigation
8. Network unreachable — link/routing layer (not DNS) — interface down, wrong route, firewall block
9. Root filesystem full (/ or /var) — cascading service failures, read-only remount
10. Time sync drift / clock skew — Kerberos ticket validation failure

=========================================================
