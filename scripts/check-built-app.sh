#!/bin/bash
# Checks one built Stilltrim.app: its binaries link no networking or web framework and it embeds no
# framework. Runs after every Xcode build (a post-build phase in project.yml), so a device build is
# checked too, and from scripts/check-no-network.sh for builds found on disk.
# It fails closed: a binary it cannot read counts as a failure.
# Usage: scripts/check-built-app.sh <path to Stilltrim.app>
set -uo pipefail

app="${1:?usage: check-built-app.sh <path to .app>}"
DENY_LINK='Network\.framework|WebKit\.framework|SafariServices\.framework|AdSupport\.framework|AppTrackingTransparency\.framework|StoreKit\.framework|CloudKit\.framework|MessageUI\.framework'
failed=0

if ! command -v otool >/dev/null 2>&1; then
  echo "error: otool not found, so the built app cannot be checked"
  exit 1
fi

if [ ! -f "$app/Stilltrim" ]; then
  echo "error: no Stilltrim binary in $app"
  failed=1
fi

for binary in "$app/Stilltrim" "$app/Stilltrim.debug.dylib"; do
  [ -f "$binary" ] || continue
  if ! libraries=$(otool -L "$binary" 2>&1); then
    echo "error: otool could not read $(basename "$binary"): $libraries"
    failed=1
    continue
  fi
  # Every real Mach-O binary links libSystem. Without it, otool printed a complaint, not a library list.
  if ! echo "$libraries" | grep -q "libSystem"; then
    echo "error: $(basename "$binary") is not a readable Mach-O binary: $(echo "$libraries" | head -1)"
    failed=1
    continue
  fi
  linked=$(echo "$libraries" | grep -E "$DENY_LINK" || true)
  if [ -n "$linked" ]; then
    echo "error: $(basename "$binary") links a framework Stilltrim must not use: $(echo "$linked" | tr -d '\t' | tr '\n' ' ')"
    failed=1
  fi
done

if [ -d "$app/Frameworks" ]; then
  echo "error: $app embeds frameworks: $(ls "$app/Frameworks" | tr '\n' ' ')"
  failed=1
fi

exit $failed
