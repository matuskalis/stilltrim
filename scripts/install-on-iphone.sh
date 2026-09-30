#!/bin/bash
# Builds an optimised Stilltrim, signs it with your team and installs it on a paired iPhone.
# A free Apple ID build stops launching after 7 days: run this again to renew it.
# Needs your team id in Config/Local.xcconfig (or chosen once in Xcode's Signing tab), and the
# phone unlocked and on this Mac's network or plugged in.
# Usage: scripts/install-on-iphone.sh [device UDID]   (default: the first reachable paired iPhone)
set -euo pipefail
cd "$(dirname "$0")/.."

team=$(grep -hE '^DEVELOPMENT_TEAM *= *[A-Z0-9]{10}' Config/Local.xcconfig 2>/dev/null | head -1 | sed -E 's/.*= *//' || true)
if [ -z "$team" ] && [ -f Stilltrim.xcodeproj/project.pbxproj ]; then
  team=$(grep -m1 -oE 'DEVELOPMENT_TEAM = [A-Z0-9]{10}' Stilltrim.xcodeproj/project.pbxproj | awk '{print $3}' || true)
fi
if [ -z "$team" ]; then
  echo "No team id. Copy Config/Local.xcconfig.example to Config/Local.xcconfig and fill it in." >&2
  exit 1
fi

device="${1:-}"
if [ -z "$device" ]; then
  device=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/iPhone/ && /available \(paired\)/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) { print $i; exit } }')
fi
if [ -z "$device" ]; then
  echo "No reachable paired iPhone. Unlock it and put it on this Mac's network, or plug it in." >&2
  exit 1
fi

echo "Building for $device"
xcodegen generate >/dev/null
xcodebuild -project Stilltrim.xcodeproj -scheme Stilltrim -configuration Release \
  -destination "platform=iOS,id=$device" -allowProvisioningUpdates -derivedDataPath build/device \
  DEVELOPMENT_TEAM="$team" build | tail -3

app=build/device/Build/Products/Release-iphoneos/Stilltrim.app
echo "Installing"
xcrun devicectl device install app --device "$device" "$app"
echo "Launching (the phone must be unlocked)"
xcrun devicectl device process launch --device "$device" "$(plutil -extract CFBundleIdentifier raw "$app/Info.plist")"
