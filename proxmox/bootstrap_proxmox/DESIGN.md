# Bootstrap scripts — design notes and reasoning

Why `bootstrap.sh` + `network-setup.sh` + `mail-config.sh` exist in the shape they do, and how they grew. Reads as a narrative — for the practical run order, script table, and what each one actually does, see [`README.md`](README.md).

---

## How these scripts came to be

I set up the first Proxmox host fully **manually** — no script, no automation. On purpose. I wanted to hit every small issue the vendor default install throws at you, so I'd actually understand what each fix did. Working through that first server surfaced things like:

- Enterprise repos requiring a paid subscription
- The subscription-nag popup in the web UI
- DNS fallback behaviour when `resolv.conf` gets clobbered
- Chrony + timezone defaults that don't fit
- WiFi packages not in the default install
- `wpa_supplicant` per-interface config file naming
- Proxmox SSL cert regeneration after the hostname change
- `/etc/network/interfaces` layout for a Wi-Fi-mgmt + two-USB-ethernet + trunked-bridge host
- …and a dozen more like it

Every command I ran to fix something, I wrote down in order. At the end of the first host I had a long ordered list. Sat down with an AI, turned that list into [`bootstrap.sh`](bootstrap.sh) and [`network-setup.sh`](network-setup.sh), then validated the scripts by **destroying and redeploying both servers from scratch with them.** Full re-bootstrap of the whole infrastructure went from "multi-day manual grind on server #1" to **under two hours end-to-end** for the second pass.

The scripts are still a living record. Every time I hit a new issue that "should have been prevented from day one", I fix it manually on the running server, then add the fix into the script. That's why the script stays current — it's a continuously-updated log of "setup mistakes that should never happen twice".

---

## Why split into `bootstrap.sh` vs `network-setup.sh` (and not one big script)

They do different things and they fail differently:

- **`bootstrap.sh`** touches repos, packages, NTP, users, subscription-nag. Safe to run from SSH. Idempotent enough to re-run.
- **`network-setup.sh`** rewrites `/etc/network/interfaces`, brings WiFi up, restructures bridges, regenerates the SSL cert. **It will disconnect your session if you run it over the wrong interface.** Needs to be run from console or from the storage-network path.

Collapsing them into one script makes the SSH-disconnect risk invisible until you hit it. Two scripts with one of them flagged "run from console, not SSH" makes the risk impossible to miss.

## Why `mail-config.sh` is separate (and optional)

Email alerts via Gmail SMTP are nice-to-have, not load-bearing. Splitting it out means:

- The core bootstrap path has zero dependency on a Gmail App Password being ready.
- I can rerun or rebuild mail config independently when a password rotates or the relay breaks.
- Someone using this repo as a reference but not wanting Gmail SMTP can skip it cleanly.

---

## Why the Terraform user (`tf_<env>`) gets a PAM-less Proxmox role with a long-lived token

The bootstrap creates `tf_dev@pve` / `tf_prod@pve` with an API token (`--privsep 0 --expire 0`). That's an always-on credential with admin scope on the Proxmox host. Worth understanding why:

- Terraform (via the `bpg/proxmox` provider) needs API access to create VMs, LXCs, disks, and bridges. No API = no IaC.
- Proxmox's auth model is either PAM (shared with host OS) or its own realm (`@pve`). Using `@pve` means the Terraform token is **not** valid for SSH, `pct`, or any host-level command — it's API-only. If the token leaks, the blast radius is Proxmox API actions, not shell on the host.
- `--privsep 0` = token has the same perms as the user; simplifies the policy surface for a single-operator project.
- `--expire 0` = no expiry. In a team / production setting I'd rotate on a schedule; for a solo-owned portfolio lab it would be ceremony without a real threat model.

The token value is read once at creation time and stored in AWS Secrets Manager (`{env}/proxmox/terraform-token`). It's never committed to git. Workflows fetch it at apply time via OIDC → Secrets Manager.

---

## What the scripts deliberately do NOT do

- **No FreeIPA enrolment.** Each Proxmox host stays outside the domain — it's the hypervisor, not a client. Same reasoning applies to the FreeIPA server VM itself (see `/ansible/dev/README.md` → "FreeIPA server uses root, not super_bot"). Managing the hypervisor through the thing it hosts would be a dependency loop.
- **No host-level monitoring agent install.** Node Exporter is deployed by Ansible (`/ansible/*/playbooks/common/install_node_exporter.yml`) as a post-bootstrap step so it can be env-scoped to the right Prometheus target.
- **No Vault / Docker / k8s tooling on the hypervisor itself.** Those run inside VMs/LXCs. Hypervisor stays minimal.
