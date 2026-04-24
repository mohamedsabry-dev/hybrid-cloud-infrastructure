#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# IO Storm Watchdog
# Detects the VM causing an IO cascade and force-resets it.
#
# Detection logic:
#   1. Check IO pressure (pressureiosome) for all VMs every 30s
#   2. If 3+ VMs have IO pressure > 15 → system-wide IO distress
#   3. Among K8s VMs, find the one with IO pressure < 2 → source
#   4. Confirm source has high CPU (not just uninvolved like freeipa)
#   5. If pattern holds for 4 consecutive checks (2 min) → reset
#   6. Send email, sleep 3 min cooldown, resume monitoring
#
# Install on Proxmox:
#   cp io-storm-watchdog.sh /root/scripts/
#   chmod +x /root/scripts/io-storm-watchdog.sh
#   # Add to cron @reboot:
#   @reboot /root/scripts/io-storm-watchdog.sh >> /var/log/io-storm-watchdog.log 2>&1 &
# ─────────────────────────────────────────────────────────────────

EMAIL_TO="mohamedsabry.dev@gmail.com"
HOSTNAME=$(hostname)
LOG="/var/log/io-storm-watchdog.log"

# VMs to monitor
K8S_VMIDS="1010 1011 1012 1020 1021 1022"
ALL_VMIDS="1001 1010 1011 1012 1020 1021 1022"

# Thresholds
IO_VICTIM=15           # IO pressure above this = victim
IO_SOURCE=2            # IO pressure below this = potential source
CPU_SOURCE=40          # CPU% above this = actively generating (not just idle)
CPU_STUCK=300          # CPU% above this = VM stuck in loop (multi-core total, 4 vCPUs × ~100%)
CONFIRM_NEEDED=4       # Consecutive hits before action (4 × 30s = 2 min)
CHECK_INTERVAL=30      # Seconds between checks
COOLDOWN=180           # Seconds after reset before resuming

# State files for tracking consecutive suspect hits
STATE_FILE="/tmp/io-watchdog-suspect"
CPU_STATE_FILE="/tmp/io-watchdog-cpu-suspect"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

get_io_pressure() {
    local vmid=$1
    pvesh get /nodes/$HOSTNAME/qemu/$vmid/status/current --output-format text 2>/dev/null \
        | grep 'pressureiosome' | awk '{print $4}'
}

get_cpu() {
    local vmid=$1
    local pid
    pid=$(cat /run/qemu-server/${vmid}.pid 2>/dev/null)
    [ -z "$pid" ] && echo "0" && return
    # Read two 1-second samples from top for instantaneous CPU
    top -b -n 2 -d 1 -p "$pid" 2>/dev/null | grep "$pid" | tail -1 | awk '{print $9}'
}

is_greater() {
    awk "BEGIN { exit !($1 > $2) }"
}

is_less() {
    awk "BEGIN { exit !($1 < $2) }"
}

# ─────────────────────────────────────────────────────────────────

log "=== IO Storm Watchdog started ==="
log "Monitoring VMs: $ALL_VMIDS"
log "Thresholds: IO_VICTIM=$IO_VICTIM IO_SOURCE=$IO_SOURCE CPU_SOURCE=$CPU_SOURCE"

# Clear state on start
echo "" > "$STATE_FILE"
echo "" > "$CPU_STATE_FILE"

while true; do
    victim_count=0
    victim_list=""

    # Step 1: Read IO pressure for all VMs, count victims
    declare -A io_map
    for vmid in $ALL_VMIDS; do
        io=$(get_io_pressure "$vmid")
        io_map[$vmid]="${io:-0}"
        if is_greater "${io:-0}" "$IO_VICTIM"; then
            ((victim_count++))
            victim_list+=" $vmid(${io})"
        fi
    done

    # Step 2: System-wide IO distress?
    if [ "$victim_count" -ge 3 ]; then
        log "IO DISTRESS: $victim_count victims:$victim_list"

        # Step 3: Find source among K8s VMs (low IO + high CPU)
        for vmid in $K8S_VMIDS; do
            io="${io_map[$vmid]}"
            if is_less "${io:-0}" "$IO_SOURCE"; then
                # Low IO — check CPU to confirm it's the source (not just uninvolved)
                cpu=$(get_cpu "$vmid")
                if is_greater "${cpu:-0}" "$CPU_SOURCE"; then
                    # Read current suspect count
                    current=$(grep "^$vmid " "$STATE_FILE" 2>/dev/null | awk '{print $2}')
                    current=$(( ${current:-0} + 1 ))

                    # Update state
                    grep -v "^$vmid " "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null
                    echo "$vmid $current" >> "${STATE_FILE}.tmp"
                    mv "${STATE_FILE}.tmp" "$STATE_FILE"

                    log "SUSPECT: VM $vmid (IO=$io CPU=${cpu}% hits=$current/$CONFIRM_NEEDED)"

                    # Step 4: Confirmed?
                    if [ "$current" -ge "$CONFIRM_NEEDED" ]; then
                        log "CONFIRMED SOURCE: VM $vmid — executing reset"

                        # Collect evidence snapshot
                        evidence=""
                        for v in $ALL_VMIDS; do
                            evidence+="  VM $v: IO_pressure=${io_map[$v]}"$'\n'
                        done

                        # Reset the VM
                        qm reset "$vmid" 2>>"$LOG"
                        log "VM $vmid reset executed"

                        # Send email
                        mail -s "[CRITICAL] $HOSTNAME - IO Storm - VM $vmid Reset" "$EMAIL_TO" <<EOF
Server: $HOSTNAME
Time: $(date)
Action: VM $vmid force-reset (IO storm source detected)

Detection:
  Victims (IO pressure > $IO_VICTIM): $victim_count VMs
  Source VM $vmid: IO_pressure=$io  CPU=${cpu}%
  Pattern sustained: $(( CONFIRM_NEEDED * CHECK_INTERVAL ))s ($CONFIRM_NEEDED consecutive checks)

All VM readings at time of reset:
$evidence
Expected recovery: ~7 minutes for cluster stabilization.
This is an automated action by io-storm-watchdog.
EOF
                        log "Alert email sent to $EMAIL_TO"

                        # Clear state and cooldown
                        echo "" > "$STATE_FILE"
                        log "Cooldown ${COOLDOWN}s — waiting for environment recovery"
                        sleep "$COOLDOWN"
                        log "Cooldown complete — verifying recovery (4 checks)"

                        # Post-reset recovery verification
                        recovery_ok=0
                        for check in 1 2 3 4; do
                            r_victims=0
                            r_readings=""
                            for v in $ALL_VMIDS; do
                                r_io=$(get_io_pressure "$v")
                                r_readings+="  VM $v: IO_pressure=${r_io:-0}"$'\n'
                                if is_greater "${r_io:-0}" "$IO_VICTIM"; then
                                    ((r_victims++))
                                fi
                            done
                            log "RECOVERY CHECK $check/4: $r_victims victims"
                            if [ "$r_victims" -ge 3 ]; then
                                log "RECOVERY FAILED: still $r_victims victims at check $check"
                                recovery_ok=0
                                break
                            fi
                            recovery_ok=1
                            sleep "$CHECK_INTERVAL"
                        done

                        if [ "$recovery_ok" -eq 1 ]; then
                            log "RECOVERY CONFIRMED: all 4 checks normal"
                            mail -s "[RECOVERED] $HOSTNAME - IO Storm resolved - VM $vmid" "$EMAIL_TO" <<REOF
Server: $HOSTNAME
Time: $(date)
Status: RECOVERED — environment stable after VM $vmid reset

Recovery verification (4 consecutive checks, all normal):
$r_readings
Cluster expected fully healthy within ~7 minutes of reset.
This is an automated action by io-storm-watchdog.
REOF
                            log "Recovery email sent to $EMAIL_TO"
                        else
                            log "WARNING: recovery not confirmed — storm may still be active"
                        fi

                        break
                    fi
                fi
            fi
        done
    else
        # No IO distress — clear IO suspects
        echo "" > "$STATE_FILE"

        # Rule 2: Single VM stuck at high CPU (throttle contained IO but VM is dead)
        for vmid in $K8S_VMIDS; do
            cpu=$(get_cpu "$vmid")
            if is_greater "${cpu:-0}" "$CPU_STUCK"; then
                current=$(grep "^$vmid " "$CPU_STATE_FILE" 2>/dev/null | awk '{print $2}')
                current=$(( ${current:-0} + 1 ))

                grep -v "^$vmid " "$CPU_STATE_FILE" > "${CPU_STATE_FILE}.tmp" 2>/dev/null
                echo "$vmid $current" >> "${CPU_STATE_FILE}.tmp"
                mv "${CPU_STATE_FILE}.tmp" "$CPU_STATE_FILE"

                log "CPU STUCK: VM $vmid (CPU=${cpu}% hits=$current/$CONFIRM_NEEDED)"

                if [ "$current" -ge "$CONFIRM_NEEDED" ]; then
                    log "CONFIRMED STUCK: VM $vmid at ${cpu}% CPU for $(( CONFIRM_NEEDED * CHECK_INTERVAL ))s — executing reset"

                    qm reset "$vmid" 2>>"$LOG"
                    log "VM $vmid reset executed"

                    mail -s "[CRITICAL] $HOSTNAME - CPU Stuck - VM $vmid Reset" "$EMAIL_TO" <<EOF
Server: $HOSTNAME
Time: $(date)
Action: VM $vmid force-reset (CPU stuck detected)

Detection:
  VM $vmid CPU: ${cpu}% (threshold: $CPU_STUCK%)
  No system-wide IO distress (IO throttle contained the blast)
  Pattern sustained: $(( CONFIRM_NEEDED * CHECK_INTERVAL ))s ($CONFIRM_NEEDED consecutive checks)

Expected recovery: ~7 minutes for cluster stabilization.
This is an automated action by io-storm-watchdog.
EOF
                    log "Alert email sent to $EMAIL_TO"

                    echo "" > "$CPU_STATE_FILE"
                    log "Cooldown ${COOLDOWN}s"
                    sleep "$COOLDOWN"

                    # Recovery verification
                    log "Verifying recovery (4 checks)"
                    recovery_ok=0
                    for check in 1 2 3 4; do
                        r_cpu=$(get_cpu "$vmid")
                        log "RECOVERY CHECK $check/4: VM $vmid CPU=${r_cpu:-?}%"
                        if is_greater "${r_cpu:-0}" "$CPU_STUCK"; then
                            log "RECOVERY FAILED: VM $vmid still at ${r_cpu}%"
                            recovery_ok=0
                            break
                        fi
                        recovery_ok=1
                        sleep "$CHECK_INTERVAL"
                    done

                    if [ "$recovery_ok" -eq 1 ]; then
                        log "RECOVERY CONFIRMED: VM $vmid CPU normal"
                        mail -s "[RECOVERED] $HOSTNAME - VM $vmid CPU normal" "$EMAIL_TO" <<REOF
Server: $HOSTNAME
Time: $(date)
Status: RECOVERED — VM $vmid CPU back to normal after reset.
This is an automated action by io-storm-watchdog.
REOF
                        log "Recovery email sent"
                    fi

                    break
                fi
            else
                # CPU normal — clear this VM's suspect count
                grep -v "^$vmid " "$CPU_STATE_FILE" > "${CPU_STATE_FILE}.tmp" 2>/dev/null
                mv "${CPU_STATE_FILE}.tmp" "$CPU_STATE_FILE"
            fi
        done
    fi

    unset io_map
    sleep "$CHECK_INTERVAL"
done
