#!/bin/sh

KEXT="/Library/Application Support/RaySens/DisableTurboBoost.64bits.kext"
LOG="/Library/Application Support/RaySens/turbo-startup.log"

if /usr/bin/kmutil showloaded 2>/dev/null | /usr/bin/grep -q 'dev.raysens.DisableTurboBoost'; then
    exit 0
fi

/usr/bin/kextutil -v "$KEXT" >> "$LOG" 2>&1
