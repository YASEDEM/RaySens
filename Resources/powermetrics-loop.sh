#!/bin/sh
set -u

BASE="/Library/Application Support/RaySens"
OUTPUT="$BASE/powermetrics.log"
TEMP="$BASE/powermetrics.tmp"
ERROR="$BASE/powermetrics.err"

trap 'exit 0' TERM INT

while :; do
    /usr/bin/powermetrics --samplers cpu_power -n 1 -i 1000 --show-pstates > "$TEMP" 2> "$ERROR"
    if /usr/bin/grep -q "System Average frequency as fraction of nominal" "$TEMP"; then
        # Read VirtualSMC CPU temperature keys directly through AppleSMC.
        if [ -x "$BASE/smc-temperature" ]; then
            "$BASE/smc-temperature" >> "$TEMP" 2>> "$ERROR" || true
        fi
        /bin/chmod 644 "$TEMP"
        /bin/mv -f "$TEMP" "$OUTPUT"
    fi
    /bin/chmod 644 "$ERROR" 2>/dev/null || true
    /bin/sleep 0.5
done
