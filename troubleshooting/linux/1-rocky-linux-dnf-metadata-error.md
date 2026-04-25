# TS-LNX-001 | 2026-02-24 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Linux
Sub-techs: Rocky Linux, DNF, yum repos, mirrorlist, HTTPS
Environment: DEV lab.local | Rocky Linux 10.1 | LXC containers
Re-opened: No

_____________________________________________________________________

[Issue Description]
DNF fails to download repository metadata on any command (install, update, makecache).

  Error: Failed to download metadata for repo 'baseos':
  repomd.xml parser error: Parse error at line: 36
  (Opening and ending tag mismatch: link line 0 and head)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
The error message itself was the first clue — "link" and "head" are HTML tags,
not XML. DNF was receiving an HTML page instead of repo metadata.

Checked repo config to understand where DNF was fetching from:

Command:
  cat /etc/yum.repos.d/rocky.repo | grep -E "mirrorlist|baseurl"

Output:
  mirrorlist=http://mirrors.rockylinux.org/mirrorlist?...
  #baseurl=http://dl.rockylinux.org/$contentdir/$releasever/BaseOS/$basearch/os/

Using mirrorlist — DNF picks a mirror from the list. Some mirrors in the list
are misconfigured or down and return HTML error pages instead of XML metadata.

Tested direct baseurl to confirm it works:

Command:
  curl -I https://dl.rockylinux.org/pub/rocky/10/BaseOS/x86_64/os/repodata/repomd.xml

Output:
  HTTP/2 200 — direct URL works fine.

Problem is the mirrorlist handing out bad mirrors, not the metadata itself.


# Suspected Root Cause
Rocky Linux mirrorlist returns mirrors that may serve HTML error pages instead
of XML metadata. Default repo config uses http:// which can redirect to error
pages. Some mirrors in the list are misconfigured or down.


# More Checks Notes:
N/A — direct URL test confirmed the fix direction.


# Suspected Solution
Disable mirrorlist, switch to direct baseurl pointing at dl.rockylinux.org over HTTPS.
Bypasses unreliable mirrors entirely.


# Test
Applied sed commands to switch to baseurl + HTTPS, ran dnf makecache.

Command:
  dnf makecache
  dnf install -y vim

Result: PASS — metadata downloaded cleanly, package install worked.

_____________________________________________________________________

[Final Root Cause]
Rocky Linux mirrorlist was handing out misconfigured or down mirrors that return
HTML error pages instead of XML repo metadata. DNF tried to parse the HTML as XML
and failed. The official direct URL (dl.rockylinux.org) works fine — the mirrorlist
was the only problem.

_____________________________________________________________________

[Final Solution]
Disabled mirrorlist, enabled direct baseurl with HTTPS on all affected Rocky Linux systems.

  # Disable mirrorlist, enable baseurl
  sed -i 's/^mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/rocky.repo
  sed -i 's/^#baseurl=/baseurl=/g' /etc/yum.repos.d/rocky.repo

  # Switch to HTTPS
  sed -i 's|http://dl.rockylinux.org|https://dl.rockylinux.org|g' /etc/yum.repos.d/rocky.repo

  # Disable extras repo (not usually needed)
  dnf config-manager --set-disabled extras

  # Rebuild cache
  dnf clean all && dnf makecache

One-liner:
  sed -i 's/^mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/rocky.repo && \
  sed -i 's/^#baseurl=/baseurl=/g' /etc/yum.repos.d/rocky.repo && \
  sed -i 's|http://dl.rockylinux.org|https://dl.rockylinux.org|g' /etc/yum.repos.d/rocky.repo && \
  dnf config-manager --set-disabled extras && \
  dnf clean all && dnf makecache

Apply as part of golden image setup or initial provisioning on any Rocky Linux 10.x.
Affected: ansible LXC (10.0.63.10), any Rocky Linux 10.x using default mirrorlist.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Now using single mirror (dl.rockylinux.org) instead of mirrorlist.
If that mirror goes down DNF will fail — but it is the official Rocky mirror,
very reliable in practice.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Related files:
  /etc/yum.repos.d/rocky.repo
  /etc/yum.repos.d/rocky-extras.repo