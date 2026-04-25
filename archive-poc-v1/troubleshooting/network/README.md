# Network — 4 cases

pfSense, VLANs, and networking issues from the PoC v1 era.

[reference/](reference/) has 1 guide

| # | File | What Happened |
|---|------|---------------|
| 04 | [promiscuous-mode](04-promiscuous-mode-nested.md) | Nested VMs isolated — promiscuous mode not enabled on vSwitch |
| 05 | [duplicate-packets](05-duplicate-packets-loop.md) | 3x duplicated pings — promiscuous mode + redundant uplinks |
| 07 | [windows-host-loops](07-windows-host-network-loops.md) | Packet duplication and ARP corruption from Windows IP forwarding |
| 08 | [static-route-loop](08-static-route-loop-ssh-disconnect.md) | SSH hangs — duplicate static routes creating routing loop |

---

## Related

- [Troubleshooting overview](../README.md)
- [Network documentation](../../docs/network/)
