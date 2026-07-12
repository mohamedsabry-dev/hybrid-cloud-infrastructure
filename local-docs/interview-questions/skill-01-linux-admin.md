Skill 1 — Linux Admin (11 questions)
======================================

Format: Standard questions only. Project examples are ammunition
you inject into answers to bait follow-ups — not separate questions.
Depth comes from scenarios and follow-ups, not question count.

---

1. How do you handle permissions on Linux — human users vs service accounts?

   Coverage check:
   - chmod/chown, rwx, SUID/SGID/sticky bit
   - ACLs (setfacl/getfacl)
   - umask
   - /etc/passwd vs /etc/shadow
   - sudoers config
   - PAM basics
   - service account vs human account differences
   - SSH key management

2. How do you manage services in Linux?

   Coverage check:
   - systemd (enable/start/stop/restart/mask)
   - unit file structure
   - dependencies (After/Requires/Wants)
   - journalctl filtering
   - cron vs systemd timers
   - creating custom services
   - log rotation (logrotate)
   - package management (yum/apt, repos, GPG keys)

3. How do you handle networking on a Linux server?

   Coverage check:
   - interfaces (ip addr/link)
   - routing table (ip route)
   - DNS (/etc/resolv.conf, dig, nslookup)
   - iptables/nftables (chains, tables, NAT rules)
   - ss/netstat
   - tcpdump basics
   - bonding/teaming
   - /etc/hosts
   - network config files (netplan/NetworkManager)

4. How do you manage storage on Linux?

   Coverage check:
   - filesystem hierarchy (FHS)
   - LVM (create/extend/reduce)
   - RAID levels (0/1/5/6/10)
   - mount options
   - mkfs, lsblk/blkid/fdisk
   - thin vs thick provisioning
   - NFS/SMB mounts
   - /etc/fstab entries
   - soft links vs hard links
   - inodes

5. How does the Linux boot process complete?

   Coverage check:
   - BIOS/UEFI → GRUB → kernel → initramfs → systemd → targets
   - what breaks at each stage
   - runlevels vs systemd targets
   - kernel parameters
   - dracut/initramfs regeneration

6. A web app on Linux suddenly dies — diagnose and recover when:
   it kills its own service, it OOM-kills a neighbor service, it crashes the OS.

   Coverage check:
   - process states
   - logs (journalctl -u, /var/log)
   - restart policies
   - OOM killer (/proc/sys/vm, dmesg, oom_score_adj)
   - cgroups/resource limits
   - swap behavior
   - kernel panic analysis, crash dumps
   - recovery path for each escalation level

7. Traffic from outside can't reach your server. What do you check?

   Coverage check:
   - is the port listening (ss -tlnp)
   - firewall rules (iptables -L)
   - security group/NACL (if cloud)
   - DNS resolving to correct IP
   - service bound to 0.0.0.0 vs 127.0.0.1
   - tcpdump to confirm packets arriving
   - routing on upstream devices

8. Your server can't reach the internet. What do you check?

   Coverage check:
   - default route (ip route)
   - DNS resolution (dig)
   - firewall outbound rules
   - NAT config
   - interface up/down
   - gateway reachable (ping)
   - MTU issues
   - /etc/resolv.conf correct
   - proxy settings if applicable

9. A server won't boot — corrupted config. How do you recover?
   (password lockout, bad fstab mount, GRUB scenarios)

   Coverage check:
   - GRUB rescue mode
   - single-user/rescue target
   - root password reset
   - bad fstab entry (mount -o remount,rw /)
   - broken initramfs
   - fsck on corrupted filesystem
   - chroot from live media
   - serial/console access when no display

10. Storage performance is degraded — walk me through:
    disk space, IO bottleneck, hardware failure, noisy neighbor service.

    Coverage check:
    - df/du discrepancy (deleted-but-open files)
    - inode exhaustion
    - iostat/iotop
    - IO scheduler
    - SMART data (smartctl)
    - dmesg for hardware errors
    - identifying IO-heavy processes (iotop, pidstat)
    - /proc/diskstats
    - IO throttling/cgroups

11. A service has correct file permissions but can't access a file
    or bind to a port. What else could block it?

    Coverage check:
    - SELinux (getenforce, sestatus, audit.log, sealert, restorecon, semanage)
    - AppArmor (aa-status, profiles, complain vs enforce)
    - capabilities (getcap/setcap)
    - kernel sysctl limits (net.ipv4.ip_unprivileged_port_start)
    - systemd sandboxing (ProtectSystem, NoNewPrivileges)
