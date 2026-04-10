# TS-LNX-001 | 2026-02-24 | RESOLVED

## 1. Context
- System: Rocky Linux 10.1 / DNF package manager
- Environment: DEV (lab.local)
- Related components: LXC containers, yum repos

## 2. Issue
- Symptom: DNF fails to download repository metadata
- Error:
```
Error: Failed to download metadata for repo 'baseos': repomd.xml parser error: Parse error at line: 36 (Opening and ending tag mismatch: link line 0 and head)
```

This error occurs when running any DNF command (`dnf install`, `dnf update`, `dnf makecache`).

## 3. Analysis

**Check 1: What is the error saying?**
```
repomd.xml parser error: Opening and ending tag mismatch: link line 0 and head
```
Finding: DNF is receiving HTML instead of XML. The "link" and "head" tags are HTML elements, not XML metadata.

**Check 2: Why is it returning HTML?**
```bash
# Check current repo config
cat /etc/yum.repos.d/rocky.repo | grep -E "mirrorlist|baseurl"
mirrorlist=http://mirrors.rockylinux.org/mirrorlist?...
#baseurl=http://dl.rockylinux.org/$contentdir/$releasever/BaseOS/$basearch/os/
```
Finding: Using mirrorlist which returns mirrors - some mirrors are misconfigured and return HTML error pages.

**Check 3: Test direct baseurl**
```bash
curl -I https://dl.rockylinux.org/pub/rocky/10/BaseOS/x86_64/os/repodata/repomd.xml
# HTTP/2 200
```
Finding: Direct URL works. Problem is with mirrorlist returning bad mirrors.

## 4. Root Cause
> 1. Rocky Linux mirrorlist returns mirrors that may serve HTML error pages instead of XML metadata
> 2. Default repo config uses `http://` which may redirect to error pages
> 3. Some mirrors in the mirrorlist are misconfigured or down

## 5. Solution
> Disable mirrorlist, enable direct baseurl with HTTPS.

**Why this works:** Using direct URL to dl.rockylinux.org bypasses unreliable mirrors. HTTPS prevents redirects to error pages.

**Location:** On affected Rocky Linux system (LXC container or VM)

**File:** `/etc/yum.repos.d/rocky.repo`

**Step 1: Disable mirrorlist, enable baseurl**
```bash
sed -i 's/^mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/rocky.repo
sed -i 's/^#baseurl=/baseurl=/g' /etc/yum.repos.d/rocky.repo
```

**Step 2: Switch from HTTP to HTTPS**
```bash
sed -i 's|http://dl.rockylinux.org|https://dl.rockylinux.org|g' /etc/yum.repos.d/rocky.repo
```

**Step 3: Fix extras repo (if exists)**
```bash
# Option A: Disable extras (not usually needed)
dnf config-manager --set-disabled extras

# Option B: Fix extras repo URL
sed -i 's|http://dl.rockylinux.org|https://dl.rockylinux.org|g' /etc/yum.repos.d/rocky-extras.repo
```

**Step 4: Clean and rebuild cache**
```bash
dnf clean all
dnf makecache
```

**Complete one-liner:**
```bash
sed -i 's/^mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/rocky.repo && \
sed -i 's/^#baseurl=/baseurl=/g' /etc/yum.repos.d/rocky.repo && \
sed -i 's|http://dl.rockylinux.org|https://dl.rockylinux.org|g' /etc/yum.repos.d/rocky.repo && \
dnf config-manager --set-disabled extras && \
dnf clean all && \
dnf makecache
```

**Verification:**
```bash
# Should complete without errors
dnf makecache

# Test install
dnf install -y vim
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Using single mirror (dl.rockylinux.org) instead of mirrorlist - if that mirror is down, DNF fails. But it's the official mirror, very reliable.

## 7. Impact After Fix
- Observed: DNF commands work correctly
- No new issues caused

## 8. Notes
- Apply this fix as part of golden image setup or initial provisioning
- Affected systems: ansible LXC (10.0.63.10), any Rocky Linux 10.x using default mirrorlist

**Related files:**
- `/etc/yum.repos.d/rocky.repo`
- `/etc/yum.repos.d/rocky-extras.repo`

## 9. Workaround (if any)
> Same as solution - no alternative workaround.
