━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING CASE #05: NETWORK LOOP - DUPLICATE PACKETS (RPF Fix)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Category: Network / High Availability
Severity: Medium
Environment: ESXi Master with Redundant Uplinks
Source: Draft for Networking (Lines 150-196)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROBLEM DESCRIPTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Issue: Duplicate Packets When Pinging Cross-Host

Goal: Add redundancy for high availability
Configuration: Added second uplink to each vSwitch (Active/Standby)

Symptom:
  ├── Ping from VM on ESXi Production Server → VM on ESXi DR Server
  └── Result: 3 DUP! responses for each ICMP request

Traffic Pattern:
  ├── Same-host (VM1 → VM2 on same ESXi): No loop (stays internal) Yes
  └── Cross-host (VM1 on Production → VM2 on DR Server): Loop occurs No

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ROOT CAUSE ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Network Loop Created by Promiscuous Mode + Multiple Uplinks:

Traffic Flow WITHOUT Fix (Loop):
  VM1 (ESXi Production Server) → ESXi Master vSwitch
    ├── vmnic0 (Active) → forwards to ESXi DR Server → VM2 Yes
    └── vmnic2 (Standby) → hears traffic → forwards AGAIN → VM2 (DUP!)
          └── vmnic0 hears vmnic2's forward → forwards AGAIN → VM2 (DUP!)

Why This Happens:
  ├── Promiscuous mode enabled (required for nested virtualization)
  ├── Both uplinks "hear" all traffic due to promiscuous mode
  ├── Active uplink forwards packet normally
  ├── Standby uplink ALSO forwards (shouldn't, but does due to promiscuous)
  └── Ping-pong loop between Active/Standby uplinks

Why Only Cross-Host Traffic Affected:
  ├── Same-host traffic stays within nested ESXi (never hits uplinks)
  └── Cross-host traffic traverses ESXi Master vSwitch (triggers loop)

Root Cause: Both uplinks listen due to Promiscuous mode

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SOLUTION: ENABLE REVERSE PATH FORWARDING (RPF) CHECK
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Command (Run on ESXi Master only):
  esxcli system settings advanced set -o /Net/ReversePathFwdCheckPromisc -i 1

What it does:
  ├── Checks if packet arrived on correct interface
  ├── Drops packet if it arrived on wrong interface
  └── Breaks ping-pong loop between Active/Standby uplinks

Applied on: ESXi Master only (nested ESXi don't need it)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Traffic Flow WITH Fix (No Loop):
  VM1 (ESXi Production Server) → ESXi Master vSwitch
    ├── vmnic0 (Active) → forwards to ESXi DR Server → VM2 Yes
    └── vmnic2 (Standby) → hears traffic → RPF CHECK → "Wrong interface" → DROP Yes

Result: Only one packet delivered, no duplicates

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VERIFICATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Check RPF Configuration:
  Command:
    esxcli system settings advanced list -d | grep "/Net/ReversePathFwdCheckPromisc" -A 10

  Expected Output:
    Path: /Net/ReversePathFwdCheckPromisc
    Type: integer
    Int Value: 1 (Enabled)
    Description: Block duplicate packets in teamed environment with Promiscuous mode

Test Connectivity:
  ├── Ping from VM on Production Server to VM on DR Server
  ├── Expected: Normal ping responses, no duplicates
  └── Monitor: tcpdump or packet capture to verify

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LESSONS LEARNED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Key Insights:
  Yes Promiscuous mode + Multiple uplinks = Potential network loop
  Yes RPF check prevents duplicate packet forwarding
  Yes Only affects cross-host traffic, not same-host
  Yes Essential for HA with nested virtualization

Important Note:
  "Future Consideration: Container networking inside nested VMs may need review.
  If containers use own MACs (not vbridge), may need adjustments. Will test
  and refactor if needed."

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PREVENTION MEASURES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Design Phase:
  Yes When planning HA with promiscuous mode, enable RPF check immediately
  Yes Document the relationship: Promiscuous + Uplinks = RPF required
  Yes Test cross-host connectivity after adding redundant uplinks
  Yes Include RPF check in initial ESXi Master configuration

Testing:
  Yes Ping tests between nested VMs on different hosts
  Yes Monitor for duplicate packets with tcpdump
  Yes Verify both Active and Standby uplink behavior
  Yes Test failover scenarios (disconnect Active uplink)

Documentation:
  Yes Document RPF setting and why it's required
  Yes Include in ESXi Master build checklist
  Yes Note container networking considerations for future
  Yes Track ESXi version compatibility

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING GUIDE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Symptom: Duplicate ping responses

Diagnostic Steps:
  1. Verify promiscuous mode is enabled on vSwitch
  2. Check number of uplinks configured (Active/Standby)
  3. Test same-host vs cross-host traffic
  4. Check RPF setting value

Resolution:
  └── Enable RPF check with command above

Verification:
  └── Ping test shows no duplicates

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RELATED ISSUES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  • Issue #04: Promiscuous Mode for Nested Virtualization
  • Future: Container networking with custom MACs

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
