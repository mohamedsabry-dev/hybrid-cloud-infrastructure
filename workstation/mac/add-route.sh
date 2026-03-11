#!/bin/bash
# Wait for network, then add route to 10.x networks

GATEWAY="192.168.100.175"
NETWORK="10.0.0.0/8"

# Wait up to 60 seconds for network
for i in {1..60}; do
    if /sbin/ping -c 1 -t 1 "$GATEWAY" &>/dev/null; then
        /sbin/route add -net "$NETWORK" "$GATEWAY" 2>/dev/null
        logger "Route $NETWORK via $GATEWAY added"
        exit 0
    fi
    sleep 1
done

logger "Failed to add route - gateway $GATEWAY not reachable"
exit 1
