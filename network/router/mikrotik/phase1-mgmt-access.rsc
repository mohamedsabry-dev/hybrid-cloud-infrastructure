# MikroTik L009UiGS-RM - Phase 1: Management Access
# Run these commands on fresh/reset MikroTik via console or WinBox
#
# Purpose: Get router accessible from ISP network (192.168.100.0/24)
# ether1 = Management port connected to ISP router
#
# Workstation IP: 192.168.100.223
# Router IP: 192.168.100.195
# ISP Gateway: 192.168.100.1

# Step 1: Configure ether1 with static IP
/ip address add address=192.168.100.195/24 interface=ether1

# Step 2: Set default gateway to ISP router
/ip route add dst-address=0.0.0.0/0 gateway=192.168.100.1

# Step 3: Allow .223 to ping internal networks (10.0.0.0/8)
# Note: Clean MikroTik has no firewall = all allowed, but adding explicit rule
/ip firewall filter add chain=forward src-address=192.168.100.223 dst-address=10.0.0.0/8 protocol=icmp action=accept comment="Allow .223 ping to internal"

# Verification commands:
# /ip address print
# /ip route print
# /ip firewall filter print
# /ping 192.168.100.1