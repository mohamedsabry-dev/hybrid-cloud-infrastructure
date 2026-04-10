# MikroTik L009UiGS-RM - Phase 2: Dev Services on ether6
# Run after Phase 1 (management access) is verified
#
# Purpose: Configure ether6 as trunk for Dev VLANs (60-65)
# ether6 connects to same switch/Proxmox as ER605 Port4 was

# Step 1: Create bridge for Dev VLANs
/interface bridge add name=br-dev vlan-filtering=no

# Step 2: Add ether6 to bridge (trunk port)
/interface bridge port add bridge=br-dev interface=ether6

# Step 3: Create VLAN interfaces
/interface vlan add interface=br-dev vlan-id=60 name=vlan60-dev-identity
/interface vlan add interface=br-dev vlan-id=61 name=vlan61-dev-platform
/interface vlan add interface=br-dev vlan-id=62 name=vlan62-dev-vault
/interface vlan add interface=br-dev vlan-id=63 name=vlan63-dev-control
/interface vlan add interface=br-dev vlan-id=64 name=vlan64-dev-data
/interface vlan add interface=br-dev vlan-id=65 name=vlan65-dev-dmz

# Step 4: Assign gateway IPs
/ip address add address=10.0.60.1/24 interface=vlan60-dev-identity
/ip address add address=10.0.61.1/24 interface=vlan61-dev-platform
/ip address add address=10.0.62.1/24 interface=vlan62-dev-vault
/ip address add address=10.0.63.1/24 interface=vlan63-dev-control
/ip address add address=10.0.64.1/24 interface=vlan64-dev-data
/ip address add address=10.0.65.1/24 interface=vlan65-dev-dmz

# Verification commands:
# /interface bridge print
# /interface bridge port print
# /interface vlan print
# /ip address print

# Test from VMs:
# ping 10.0.60.1  (from VLAN 60 VM)
# ping 10.0.61.1  (from VLAN 61 VM)
# etc.
