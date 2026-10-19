#!/usr/bin/env bash
# Calls the live check-in function with a reserved test device ID and checks its answers.
#   ./scripts/backend-smoke-test.sh [analytics|minimal|erase]
# The argument is the state the test leaves behind, so the stored row can be inspected:
#   analytics  the row holds the analytics fields (IP, versions, language)
#   minimal    the user opted out: only the ID and the dates remain
#   erase      the row is deleted
set -euo pipefail

FINAL=${1:-erase}
URL=${CHECKIN_URL:-https://yomgyukfzlnjxcvdsivw.supabase.co/functions/v1/checkin}
DEVICE=00000000-0000-4000-8000-000000000001

check() {  # name, expected status, JSON body, optional jq assertion
    local out status body
    out=$(curl -sS -m 30 -w '\n%{http_code}' -X POST "$URL" -H 'Content-Type: application/json' -d "$3")
    status=${out##*$'\n'}
    body=${out%$'\n'*}
    echo "[$1] status=$status body=$body"
    [ "$status" = "$2" ] || { echo "FAIL: expected status $2"; exit 1; }
    if [ -n "${4:-}" ]; then
        echo "$body" | jq -e "$4" > /dev/null || { echo "FAIL: expected $4"; exit 1; }
    fi
}

request() {  # analytics, wants_update, license key
    jq -nc --arg d "$DEVICE" --argjson a "$1" --argjson w "$2" --arg k "$3" \
        '{device_id: $d, event: "open", analytics: $a, wants_update: $w, app_version: "0.0.1",
          macos_version: "14.1.0", os_language: "nl-NL", license_key: $k}'
}

check "rejects a bad device ID" 400 '{"device_id":"nope"}'
check "rejects invalid JSON" 400 'not json'
check "minimal check-in" 200 "$(request false false '')" '.ok == true'
check "no license key" 200 "$(request false true '')" '.license == "missing"'
check "unknown license key" 200 "$(request false true 'EMC-AAAAA-AAAAA-AAAAA-AAAAA')" '.license == "invalid"'

case "$FINAL" in
    analytics) check "analytics check-in" 200 "$(request true false 'EMC-TEST')" '.ok == true' ;;
    minimal)
        check "analytics check-in" 200 "$(request true false 'EMC-TEST')" '.ok == true'
        check "opt out" 200 "$(request false false '')" '.ok == true' ;;
    erase)
        check "analytics check-in" 200 "$(request true false 'EMC-TEST')" '.ok == true'
        check "erase" 200 "$(jq -nc --arg d "$DEVICE" '{device_id: $d, action: "erase"}')" '.ok == true' ;;
    *) echo "unknown final state: $FINAL"; exit 2 ;;
esac
echo "Smoke test passed (final state: $FINAL)"
