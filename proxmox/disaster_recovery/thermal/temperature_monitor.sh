#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# CPU Temperature Monitor
# Daemon that checks CPU temp every 30s. Triggers graceful shutdown
# only if temp stays above 90°C for 5 minutes straight AND no
# backup/restore is running (those spikes are expected).
#
# Install:
#   cp draft-temperature_monitor.sh /root/scripts/temperature_monitor.sh
#   chmod +x /root/scripts/temperature_monitor.sh
#   # cron @reboot:
#   @reboot /root/scripts/temperature_monitor.sh >> /var/log/temperature_monitor.log 2>&1 &
# ─────────────────────────────────────────────────────────────────

EMAIL_TO="mohamedsabry.dev@gmail.com"
HOSTNAME=$(hostname)
THRESHOLD=90
CONFIRM_NEEDED=10      # 10 × 30s = 5 min sustained
CHECK_INTERVAL=30

suspect_count=0
alert_sent=0

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1"; }

log "=== Temperature Monitor started (threshold=${THRESHOLD}°C, confirm=${CONFIRM_NEEDED}) ==="

while true; do
    temp=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))

    if [[ "$temp" -ge "$THRESHOLD" ]]; then
        # Backup or restore running? Skip — spike is expected
        if pgrep -f 'vzdump|qmrestore' >/dev/null 2>&1; then
            log "CPU: ${temp}°C — backup/restore running, skipping"
            suspect_count=0
        else
            ((suspect_count++))
            log "CPU: ${temp}°C — no known cause (hits=$suspect_count/$CONFIRM_NEEDED)"

            # Alert once per episode
            if [[ "$alert_sent" -eq 0 ]]; then
                mail -s "[WARNING] $HOSTNAME CPU ${temp}°C" "$EMAIL_TO" <<EOF
CPU at ${temp}°C with no backup/restore running.
Shutdown triggers after $CONFIRM_NEEDED consecutive readings ($(( CONFIRM_NEEDED * CHECK_INTERVAL ))s).
EOF
                alert_sent=1
            fi

            # Sustained — shut down
            if [[ "$suspect_count" -ge "$CONFIRM_NEEDED" ]]; then
                log "SHUTDOWN: ${temp}°C sustained for $(( suspect_count * CHECK_INTERVAL ))s"
                mail -s "[CRITICAL] $HOSTNAME CPU ${temp}°C - SHUTDOWN" "$EMAIL_TO" <<EOF
CPU at ${temp}°C for $(( suspect_count * CHECK_INTERVAL ))s with no backup/restore.
Graceful shutdown triggered.
EOF
                /sbin/shutdown -h +1 "CPU ${temp}°C sustained — thermal shutdown"
                exit 0
            fi
        fi
    else
        [[ "$suspect_count" -gt 0 ]] && log "CPU: ${temp}°C — cooled, counter reset"
        suspect_count=0
        alert_sent=0
    fi

    sleep "$CHECK_INTERVAL"
done