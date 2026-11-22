#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="$(mktemp -d)"
trap 'rm -rf "$output"' EXIT
xcrun swiftc Hijri/UmmAlQura.swift Hijri/SaudiOccasionRules.swift Hijri/Occasions.swift \
    Hijri/ReminderDates.swift Checks/CalendarParity.swift -o "$output/calendar-checks"
"$output/calendar-checks" Hijri/Resources/ummalqura.bin
