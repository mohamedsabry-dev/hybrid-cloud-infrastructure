#!/bin/bash
# Proxmox CPU Temperature Monitor
# Run via cron: */5 * * * * /root/scripts/temperature_monitor.sh >> /var/log/temperature_monitor.log 2>&1

EIL_TO="mohamedsabry.dev@gmail.com"
HOSTNAME=$(hostname)

# Read CPU temperature in °C
TEMP_C=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))

echo "$(date) - CPU: ${TEMP_C}°C"

if [[ "$TEMP_C" -gt 80 ]]; then
    mail -s "[CRITICAL] $HOSTNAME - CPU ${TEMP_C}°C - SHUTDOWN" "$EMAIL_TO" << EOF
Server: $HOSTNAME
Time: $(date)
CPU Temperature: ${TEMP_C}°C
Threshold: 80°C
Action: Graceful shutdown triggered
EOF
    /sbin/shutdown -h +1 "CPU temperature ${TEMP_C}°C - graceful thermal shutdown"
elif [[ "$TEMP_C" -gt 76 ]]; then
    mail -s "[WARNING] $HOSTNAME - CPU ${TEMP_C}°C over 76°C" "$EMAIL_TO" << EOF
Server: $HOSTNAME
Time: $(date)
CPU Temperature: ${TEMP_C}°C
Threshold: 76°C
EOF
fiMA
