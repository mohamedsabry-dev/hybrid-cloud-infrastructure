# Thermal Monitor — To Fix Later

Issues found in `draft-temperature_monitor.sh` (2026-04-21):

## Bugs
1. **`EIL_TO=` typo** (line 5) — variable referenced as `$EMAIL_TO` is empty. Emails only land because postfix aliases root mail.
2. **`-gt 80` shutdown threshold** (line 13) — strictly greater than, so at exactly 80°C no shutdown fires; falls to warning branch instead.
3. **`fiMA` syntax error** (line 29) — `if` has no matching `fi`; as currently saved, script won't execute at all.

## Design problems
4. **Wrong sensor.** Reads `/sys/class/thermal/thermal_zone0/temp` → usually `acpitz` on AMD, not the CPU die. Should read `k10temp/Tctl` via `sensors`.
5. **No averaging / no debounce.** Cron runs every 5 min but takes a single instantaneous reading. A transient spike triggers "CRITICAL SHUTDOWN" email immediately. Subject line is misleading.
6. **Thresholds too aggressive for Ryzen.** 80°C is normal operating range on AMD mobile (Tjmax ~100°C, throttle ~95°C). Shutdown at 80°C is premature.

## Recommended direction
- Stop doing shutdown in bash — firmware already handles Tjmax protection faster and more reliably than any cron.
- Keep script for **alerting only**: debounced (3 consecutive breaches = ~15 min sustained) before paging.
- Read `k10temp` via `sensors -u k10temp-pci-00c3 | awk '/temp1_input/ {print int($2)}'`.
- Suggested thresholds: warn ≥85°C, critical ≥92°C.

## Current box sensor reference (pve-dev, AMD Ryzen APU)
| Sensor | Meaning |
|---|---|
| `k10temp / Tctl` | **CPU die control temp — authoritative** |
| `amdgpu / edge` | Integrated GPU |
| `acpitz / temp1` | Motherboard/skin — vague |
| `nvme / Composite` | SSD |
| `asus / cpu_fan` | Fan RPM |
