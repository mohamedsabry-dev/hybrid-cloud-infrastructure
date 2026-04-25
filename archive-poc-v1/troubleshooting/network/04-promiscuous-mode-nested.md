━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING CASE #04: NESTED VIRTUALIZATION NETWORK ISOLATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Category: Network / Nested Virtualization
Severity: High
Environment: ESXi Master → ESXi Nested VMs
Source: Draft for Networking (Lines 96-147)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROBLEM DESCRIPTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Issue: Nested ESXi VMs Completely Isolated - No Network Connectivity

Initial Design:
  ├── ESXi Master on VMware Workstation
  ├── 2 vNICs: 1 for Bridge (192.x.x.x), 1 for Host-Only (10.0.20.x)
  └── Default Security Settings

Symptoms:
  - Nested VMs can't communicate with each other
  - Nested VMs can't reach external networks
  - "Network unreachable" errors when pinging
  - ESXi host works, but VMs inside it are isolated

Configuration at Time of Issue:
  ├── Promiscuous Mode: OFF (default)
  └── Forged Transmits: OFF (default)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ROOT CAUSE ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Nested Virtualization Requirement:
  ├── Nested ESXi hosts need traffic for nested VMs (different MACs)
  ├── Without promiscuous mode, outer vSwitch drops packets for nested VMs
  ├── Nested ESXi forwards traffic on behalf of nested VMs
  └── Packets have nested VM's MAC, NOT ESXi host's MAC

Default vSwitch Behavior:
  ├── Normal mode: Only forwards packets matching VM's MAC address
  ├── Security feature: Prevents MAC spoofing
  └── Problem: Breaks nested virtualization completely

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SOLUTION: ENABLE SECURITY POLICY SETTINGS ON ESXI MASTER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Security Setting 1: Promiscuous Mode (Allow-Promiscuous: Accept)

What it does:
  ├── Allows vSwitch to forward ALL packets to VMs
  └── Normal mode: Only forwards packets matching VM's MAC address

Why required for nested virtualization:
  ├── Nested ESXi hosts need traffic for nested VMs (different MACs)
  └── Without this, outer vSwitch drops packets for nested VMs

What happens if disabled:
  - Nested VMs can't communicate with each other
  - Nested VMs can't reach external networks
  - "Network unreachable" errors when pinging
  - ESXi host works, but VMs inside it are isolated

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Security Setting 2: Forged Transmits (Allow-Forged-Transmits: Accept)

What it does:
  ├── Allows VMs to send packets with different source MAC
  └── Normal mode: Drops packets if source MAC doesn't match VM's MAC

Why required for nested virtualization:
  ├── Nested ESXi forwards traffic on behalf of nested VMs
  ├── Packets have nested VM's MAC, NOT ESXi host's MAC
  └── Outer vSwitch must allow these "forged" MACs

What happens if disabled:
  - Outbound traffic from nested VMs dropped at vSwitch
  - Nested VMs can't send any traffic out
  - Ping requests sent but never reach destination
  - One-way communication (can receive, can't send)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Security Setting 3: MAC Address Changes (Allow-MAC-Changes: Accept)

What it does:
  ├── Allows VMs to change MAC at runtime
  └── Normal mode: Locks VM to configured MAC

Why required for nested virtualization:
  ├── VM migration scenarios (vMotion)
  └── Network failover and load balancing

What happens if disabled:
    Less critical, but causes issues during:
  • VM migration (vMotion)
  • Network failover scenarios
  • Advanced nested networking

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CONFIGURATION STEPS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Step 1: Access ESXi Master Web Interface
  └── Navigate to Networking → Virtual Switches

Step 2: Configure vSwitch0 (Bridge Network)
  ├── Select vSwitch0
  ├── Edit Settings → Security
  ├── Promiscuous Mode: Accept
  ├── Forged Transmits: Accept
  ├── MAC Address Changes: Accept
  └── Save

Step 3: Configure vSwitch_Internal (Management + Production)
  ├── Select vSwitch_Internal
  ├── Edit Settings → Security
  ├── Promiscuous Mode: Accept
  ├── Forged Transmits: Accept
  ├── MAC Address Changes: Accept
  └── Save

Step 4: Verify Configuration
  ├── Check each vSwitch security policy
  └── Ensure all three settings show "Accept"

Step 5: Test Connectivity
  ├── Ping from nested VM to external network
  ├── Ping between nested VMs on different ESXi hosts
  └── Verify bidirectional communication

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
APPLIED SETTINGS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ESXi Master:
  Yes vSwitch0: Promiscuous ON, Forged Transmits ON
  Yes vSwitch_Internal: Promiscuous ON, Forged Transmits ON

ESXi Production & DR Servers (Nested):
  No Promiscuous OFF (not needed inside nested ESXi)
  No Forged Transmits OFF (not needed inside nested ESXi)

Rationale:
  ├── Only OUTER layer (ESXi Master) needs these settings
  ├── Inner nested ESXi behaves like normal ESXi
  └── Security settings only required at hypervisor boundary

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LESSONS LEARNED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Key Insights:
  Yes Nested virtualization requires relaxed security policies
  Yes Promiscuous mode is MANDATORY for nested ESXi networking
  Yes Forged transmits is MANDATORY for outbound traffic
  Yes Only enable on outer hypervisor, not nested ESXi

Security Considerations:
  ├── These settings reduce network security
  ├── Only enable on vSwitches used for nested virtualization
  ├── Acceptable risk in lab environment
  └── Production: Consider dedicated physical hosts for nested labs

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PREVENTION MEASURES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Design Phase:
  Yes Research nested virtualization requirements BEFORE deployment
  Yes Document security policy changes required
  Yes Plan vSwitch architecture with security settings in mind
  Yes Understand impact of promiscuous mode on network security

Documentation:
  Yes Document why security settings are relaxed
  Yes Clearly mark vSwitches with special security policies
  Yes Include troubleshooting steps for network connectivity
  Yes Maintain change log for security policy modifications

Testing:
  Yes Test nested VM connectivity immediately after ESXi creation
  Yes Verify both inbound and outbound traffic
  Yes Test cross-host communication
  Yes Document baseline connectivity tests

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RELATED ISSUES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  • Issue #05: Network Loop with Multiple Uplinks (RPF check)
  • Container networking considerations (future refactor)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
