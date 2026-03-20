#!/bin/bash
# DR UPS Monitor for Proxmox on Laptop
# Run via cron: */5 * * * * /path/to/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1

# Email config
EMAIL_TO="mohamedsabry.dev@gmail.com"
HOSTNAME=$(hostname)

LOCK_FILE="/tmp/dr_ups_monitor.lock"

# Prevent multiple instances running at same time
if [[ -f "$LOCK_FILE" ]]; then
    echo "[SKIP] Another instance is running"
    exit 0
fi
trap "rm -f $LOCK_FILE" EXIT
touch "$LOCK_FILE"

# Step 1: Get battery info
BATTERY_STATUS=$(cat /sys/class/power_supply/BAT0/status)
BATTERY_CAPACITY=$(cat /sys/class/power_supply/BAT0/capacity)

echo "$(date) - Battery: $BATTERY_STATUS at ${BATTERY_CAPACITY}%"

# IMPORTANT: Only trigger shutdown if DISCHARGING (going down)
# If charging (going up from low), do nothing - power is back!
if [[ "$BATTERY_STATUS" != "Discharging" ]]; then
    echo "[OK] Battery is $BATTERY_STATUS - power connected, no action"
    exit 0
fi

# From here: Battery IS discharging (power lost)

# Step 2: CRITICAL - Below 35% AND discharging = force halt NOW
if [[ "$BATTERY_CAPACITY" -lt 35 ]]; then
    echo "[CRITICAL] DISCHARGING at ${BATTERY_CAPACITY}% - FORCE HALT!"
    mail -s "[CRITICAL] $HOSTNAME - Battery ${BATTERY_CAPACITY}% FORCE HALT" "$EMAIL_TO" << EOF
Server: $HOSTNAME
Time: $(date)
Battery: ${BATTERY_CAPACITY}%
Status: DISCHARGING
Action: FORCE HALT NOW - No time left!
EOF
    /sbin/shutdown -h now "CRITICAL: Battery dying - forced halt"
    exit 0
fi

# Step 3: LOW - Below 55% AND discharging = graceful shutdown
if [[ "$BATTERY_CAPACITY" -lt 55 ]]; then
    echo "[WARNING] DISCHARGING at ${BATTERY_CAPACITY}% - power lost confirmed"
    echo "Starting graceful shutdown..."
    mail -s "[WARNING] $HOSTNAME - Battery ${BATTERY_CAPACITY}% Shutdown" "$EMAIL_TO" << EOF
Server: $HOSTNAME
Time: $(date)
Battery: ${BATTERY_CAPACITY}%
Status: DISCHARGING
Action: Graceful shutdown in 1 minute
Reason: Battery below 55% - power source lost
EOF
    /sbin/shutdown +1 "Low battery - graceful shutdown"
    exit 0
fi

# Step 4: WARNING - Below 78% AND discharging = check network first
if [[ "$BATTERY_CAPACITY" -lt 78 ]]; then
    echo "[ALERT] DISCHARGING at ${BATTERY_CAPACITY}% - checking network for 2 min..."

    # Send email alert immediately when battery drops below 78%
    mail -s "[ALERT] $HOSTNAME - Battery ${BATTERY_CAPACITY}% Discharging" "$EMAIL_TO" << EOF
Server: $HOSTNAME
Time: $(date)
Battery: ${BATTERY_CAPACITY}%
Status: DISCHARGING - Power may be lost!
EOF

    # Ping hosts for 2 minutes (12 checks x 10 seconds)
    for i in {1..12}; do
        echo "Network check $i of 12..."

        # If ANY host responds, maybe just unplugged briefly
        if ping -c 1 -W 2 10.0.5.1 &>/dev/null; then
            echo "[OK] 10.0.5.1 reachable - network up, waiting..."
            exit 0
        fi
        if ping -c 1 -W 2 10.0.40.120 &>/dev/null; then
            echo "[OK] 10.0.40.120 reachable - network up, waiting..."
            exit 0
        fi
        if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
            echo "[OK] 8.8.8.8 reachable - network up, waiting..."
            exit 0
        fi

        echo "All hosts unreachable - waiting 10 seconds..."
        sleep 10
    done

    # 2 minutes passed, all hosts still down = full site outage
    echo "[CRITICAL] DISCHARGING + Network down for 2 min = power outage!"
    echo "Starting graceful shutdown..."
    /sbin/shutdown +1 "Power outage - emergency shutdown"
    exit 0
fi

echo "[OK] DISCHARGING at ${BATTERY_CAPACITY}% - above 78%, monitoring only"