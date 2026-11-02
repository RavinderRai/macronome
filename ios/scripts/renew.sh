#!/bin/bash
# Weekly renewal for a free Apple ID install: copies the log off the phone, then rebuilds
# and reinstalls the app, which restarts its 7 days.
#
#   ios/scripts/renew.sh                 back up, then reinstall
#   ios/scripts/renew.sh --backup-only   just copy the log
#
# The phone must be unlocked and either plugged in or on the same Wi-Fi as the Mac.
# Backups go to $MACRONOME_BACKUP_DIR (default ~/Documents/Macronome/backups), outside the
# repo, since the repo is public.
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="${MACRONOME_BACKUP_DIR:-$HOME/Documents/Macronome/backups}"
BACKUP_ONLY=false
[[ "${1:-}" == "--backup-only" ]] && BACKUP_ONLY=true

cd "$IOS_DIR"

if [[ ! -f Config/Signing.local.xcconfig ]]; then
    echo "Set your team and bundle id first: cp Config/Signing.example.xcconfig Config/Signing.local.xcconfig" >&2
    exit 1
fi

settings="$(xcodebuild -project Macronome.xcodeproj -target Macronome -showBuildSettings 2>/dev/null)"
APP_GROUP_ID="$(awk -F' = ' '/^ *APP_GROUP_ID = /{print $2; exit}' <<<"$settings")"

# First physical iPhone the Mac can reach.
devices_json="$(mktemp)"
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1
read -r UDID NAME < <(python3 -I - "$devices_json" <<'EOF'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
for d in devices:
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hw.get("reality") != "simulated" and hw.get("platform") == "iOS" and conn.get("tunnelState") != "unavailable":
        print(hw["udid"], d.get("deviceProperties", {}).get("name", "iPhone"))
        break
EOF
) || true
if [[ -z "${UDID:-}" ]]; then
    echo "No iPhone found. Unlock it and plug it in (or join the Mac's Wi-Fi), then try again." >&2
    exit 1
fi
echo "Phone: $NAME"

# Back up before reinstalling, so a failed install can't cost anything.
mkdir -p "$BACKUP_DIR"
stamp="$(date +%Y-%m-%d-%H%M)"
if xcrun devicectl device copy from --device "$UDID" --quiet \
    --domain-type appGroupDataContainer --domain-identifier "$APP_GROUP_ID" \
    --source events.jsonl --destination "$BACKUP_DIR/events-$stamp.jsonl"; then
    cp "$BACKUP_DIR/events-$stamp.jsonl" "$BACKUP_DIR/events-latest.jsonl"
    echo "Backed up $(wc -l <"$BACKUP_DIR/events-$stamp.jsonl" | tr -d ' ') events to $BACKUP_DIR/events-$stamp.jsonl"
else
    echo "Backup failed (nothing logged yet, or the app isn't installed). Continuing." >&2
fi

$BACKUP_ONLY && exit 0

echo "Building and installing..."
xcodebuild -project Macronome.xcodeproj -scheme Macronome -configuration Debug \
    -destination "id=$UDID" -derivedDataPath build/device -allowProvisioningUpdates \
    -quiet build
xcrun devicectl device install app --device "$UDID" --quiet \
    build/device/Build/Products/Debug-iphoneos/Macronome.app
echo "Installed. Good for another 7 days."
