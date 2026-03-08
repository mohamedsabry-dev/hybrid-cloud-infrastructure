# Troubleshooting Case #15: Rocky Linux DNF Metadata Download Error

**Date:** 2026-02-24
**Environment:** Rocky Linux 10.1 (LXC containers)
**Component:** DNF package manager

---

## Problem

DNF fails to download repository metadata with XML parsing error:

```
Error: Failed to download metadata for repo 'baseos': repomd.xml parser error: Parse error at line: 36 (Opening and ending tag mismatch: link line 0 and head)
```

This error occurs when running any DNF command (`dnf install`, `dnf update`, `dnf makecache`).

---

## Root Cause

1. The Rocky Linux mirrorlist returns mirrors that serve HTML error pages instead of XML metadata
2. Default repo config uses `http://` which may redirect to an error page
3. Some mirrors in the mirrorlist are misconfigured or down

---

## Solution

### Step 1: Disable mirrorlist, enable direct baseurl

```bash
sed -i 's/^mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/rocky.repo
sed -i 's/^#baseurl=/baseurl=/g' /etc/yum.repos.d/rocky.repo
```

### Step 2: Switch from HTTP to HTTPS

```bash
sed -i 's|http://dl.rockylinux.org|https://dl.rockylinux.org|g' /etc/yum.repos.d/rocky.repo
```

### Step 3: Fix extras repo (if exists)

```bash
# Option A: Disable extras (not usually needed)
dnf config-manager --set-disabled extras

# Option B: Fix extras repo URL
sed -i 's|http://dl.rockylinux.org|https://dl.rockylinux.org|g' /etc/yum.repos.d/rocky-extras.repo
```

### Step 4: Clean and rebuild cache

```bash
dnf clean all
dnf makecache
```

---

## Complete One-Liner Fix

```bash
sed -i 's/^mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/rocky.repo && \
sed -i 's/^#baseurl=/baseurl=/g' /etc/yum.repos.d/rocky.repo && \
sed -i 's|http://dl.rockylinux.org|https://dl.rockylinux.org|g' /etc/yum.repos.d/rocky.repo && \
dnf config-manager --set-disabled extras && \
dnf clean all && \
dnf makecache
```

---

## Verification

```bash
# Should complete without errors
dnf makecache

# Test install
dnf install -y vim
```

---

## Affected Systems

- ansible LXC (10.0.63.10)
- Any Rocky Linux 10.x system using default mirrorlist

---

## Prevention

When creating new Rocky Linux systems, apply the fix as part of the golden image setup script or during initial provisioning.

---

## Related

- Rocky Linux repo configuration: `/etc/yum.repos.d/rocky.repo`
- Rocky Linux extras repo: `/etc/yum.repos.d/rocky-extras.repo`
