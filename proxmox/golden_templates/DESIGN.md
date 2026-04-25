# Golden templates — design notes and reasoning

Why these two scripts exist in the shape they do, how the package/config list grew over time, and the philosophy behind what belongs in a golden template vs what each cloned VM/LXC gets later from Ansible. Reads as a narrative — for the script reference, package list, and final-steps checklist, see [`README.md`](README.md).

---

## How these scripts grew into what they are now

I didn't sit down and write these in one go. The first version of `golden-vm-setup.sh` was short — basic packages, the `ipa-client` binary, a handful of config tweaks. Over 2–4 days of actually using the templates to stamp out real VMs and LXCs, I kept hitting small things that *every* cloned machine turned out to need. Those accreted into the current scripts.

After the first pass, the working pattern became:

1. Stamp a new VM / LXC from the golden template.
2. Hit something missing that should have been set at template level (e.g. firewalld running when I wanted it off by default, a debugging tool not installed, a service not enabled, cloud-init regenerating SSH host keys on every Terraform update).
3. Fix it quickly in Ansible on the running node so I can keep going.
4. Come back to this folder and add the fix into the golden script.
5. Next time I rebuild the template, the fix is baked in from day one.

`firewalld disabled by default` is a clean example of that loop. Same story for most of the networking/debugging tools and the cloud-init SSH-host-key preservation config (which also has a dedicated TS case at [`../../troubleshooting/terraform/10-cloud-init-ssh-host-key-regeneration.md`](../../troubleshooting/terraform/10-cloud-init-ssh-host-key-regeneration.md)).

**Two update paths** I've actually used, depending on how big the fix is:

| Path | When I use it |
|------|---------------|
| Patch in Ansible → add to golden script → rebuild template next cycle | Most common. Unblocks the current node immediately; golden script keeps accumulating the real list of "things every machine needs". |
| Boot the existing golden VM/LXC, apply the change live, re-convert to template | Faster for a single small tweak when I don't want to redo a fresh OS install. I've used this for minor package additions. |

**Current status: rarely touched.** The environment has stabilised and the last meaningful edit to these scripts was a while back. New requirements now almost always belong in **env/role customisation** via Ansible, not in the golden layer. I accept that split cleanly: golden = standard stuff every machine in the fleet needs regardless of role; everything else = Ansible.

---

## What actually goes in the golden template, and why

Three categories end up baked in:

### 1. Packages the OS should just have — period

Things I don't want to explain the absence of at any point:

- `curl`, `wget`, `vim`, `htop`, `git`, `tree`, `jq`, `sudo`, `bash-completion`, `tar`, `unzip`
- `openssh-server`, `openssh-clients`, `rsyslog`
- `ca-certificates`, `policycoreutils-python-utils`

### 2. Monitoring and debugging tools for incidents — the important category

- `tcpdump`, `nmap-ncat`, `traceroute`, `bind-utils`, `net-tools`, `iputils`, `iproute`, `NetworkManager`, `NetworkManager-tui`

This category looks heavy at first glance — why ship a debugger kit on every node? The reasoning is from real enterprise experience: **when you're debugging a live incident in a private / locked-down environment, you very often do not have the tool installed and you do not have a working network path to install it.** The network might be exactly what's broken. The Vault node might not have outbound internet. The LXC might have firewall rules that only allow application traffic. SSSD / Kerberos might be failing in a way that blocks your package-manager auth.

If the tool isn't already on the box when the incident starts, you're stuck. Two hours of the incident turn into *"wait, let me SSH to another host and scp a statically-linked binary over…"* — if you can even reach another host.

So I pre-install the debug kit on every machine at golden-template time, deliberately. It costs a few MB per node and buys unlimited incident visibility later. This is a pattern I brought in from enterprise jobs: *ship the tools before you need them, because the moment you need them is the moment you can't install them.*

### 3. Platform-integration packages

Pieces the fleet depends on whether they're visible in day-to-day use or not:

- **`qemu-guest-agent`** (VM only) — Proxmox needs this to get proper ACPI shutdown, IP info, filesystem freeze-during-backup. Install and enable at golden time so every cloned VM reports cleanly from day one.
- **`cloud-init`** (VM only) — the Proxmox Terraform provider uses cloud-init to inject IPs, hostnames, and SSH keys per VM. The golden template also includes a specific fix at `/etc/cloud/cloud.cfg.d/99-preserve-ssh.cfg` to stop cloud-init from regenerating SSH host keys every Terraform apply — that was its own rabbit hole, written up in the TS case linked above.
- **`ipa-client`** (VM + LXC) — RPM installed, host is **not** enrolled. Enrolment happens later per node via Ansible (`playbooks/freeipa/add_hosts_to_ipa.yml`) because it's env-specific (dev realm vs prod realm) and has to happen after the host gets its real hostname and IP.
- **`firewalld`** (installed, **disabled**). I want it present on every node so Ansible can enable and configure it per role without a package-install round-trip, but I don't want it defaulting to on. Cloned VMs came up with default `firewalld` rules once and couldn't be reached by the Ansible control node — disabled by default here, Ansible explicitly enables it where it should actually run.
- **`audit` / `auditd`** (VM only — LXC inherits host audits).

---

## What deliberately does NOT go in the golden template

- **IPA enrolment.** Template stays realm-neutral; Ansible enrols per env.
- **SSH keys.** Cleared during cleanup. Terraform cloud-init (VM) or Proxmox API (LXC) injects per-host keys at clone time.
- **Hostnames and network config.** Cleared. Set at clone time.
- **Passwords for the `gandalf` break-glass user.** Account is created and locked; Ansible pulls the password from AWS Secrets Manager and sets it per env.
- **Service-specific config.** No Vault, no k8s, no Nginx config here — all in Ansible per role.

The rule of thumb: *golden is for things every machine in the fleet needs regardless of role.* Anything that differs by VM type, by env, or by workload is Ansible's job.

---

## A naming legacy worth knowing about

The LXC template tarball is `rocky-9-lxc-golden.tar.gz`, referenced by that name throughout Terraform. The actual OS running on the template today is **Rocky Linux 10.x** — the `rocky-9` in the filename is a leftover from the early PoC plan when I was on Rocky 9. When I moved to 10, I kept the filename so the Terraform state and references didn't have to chase a rename. Mentioning it here so you don't mistake the name for the OS version.

---

## Related

- [`README.md`](README.md) — operational reference: scripts, packages, final steps
- [`../bootstrap_proxmox/`](../bootstrap_proxmox/) — Proxmox host setup (runs *before* golden images can be built)
- [`../../ansible/`](../../ansible/) — where all the role-specific / env-specific config lives
- [`../../troubleshooting/terraform/10-cloud-init-ssh-host-key-regeneration.md`](../../troubleshooting/terraform/10-cloud-init-ssh-host-key-regeneration.md) — the TS case behind the `preserve-ssh` cloud-init fix baked into the VM script
