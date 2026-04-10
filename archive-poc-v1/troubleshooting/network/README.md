# Network Troubleshooting

pfSense, VLANs, and networking issues.

## Cases (5)

| Case | Issue | Root Cause |
|------|-------|------------|
| 04 | Promiscuous Mode for Nested Virtualization | vSwitch security settings |
| 05 | Duplicate Packets from Network Loops | Uplink redundancy config |
| 06 | pfSense Power Off Issues | VM shutdown sequence |
| 07 | Windows IP Forwarding Loops | ARP corruption |
| 08 | Static Route Loop SSH Disconnect | Duplicate static routes |

## Key Lessons

- Enable promiscuous mode for nested ESXi
- Avoid duplicate uplinks without proper LAG config
- Disable Windows IP forwarding unless needed
- Verify static routes don't create loops

## Related

- [Troubleshooting overview](../README.md)
- [Network documentation](../../docs/network/)
