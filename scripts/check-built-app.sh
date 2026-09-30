#!/bin/bash
# Checks one built Stilltrim.app: its binaries link no networking or web framework, bind symbols only from
# allow-listed libraries and none of the deny-listed networking symbols, and it embeds no framework. Runs after every Xcode build (a post-build phase in project.yml), so a device build is
# checked too, and from scripts/check-no-network.sh for builds found on disk.
# It fails closed: a binary it cannot read counts as a failure.
# Usage: scripts/check-built-app.sh <path to Stilltrim.app>
set -uo pipefail

app="${1:?usage: check-built-app.sh <path to .app>}"
DENY_LINK='Network\.framework|CFNetwork\.framework|WebKit\.framework|SafariServices\.framework|AdSupport\.framework|AppTrackingTransparency\.framework|StoreKit\.framework|CloudKit\.framework|MessageUI\.framework'
# Libraries a binary may bind symbols from: local Apple frameworks only, no networking-capable one. A new framework is a
# deliberate edit of this list. Keep it in step with ALLOWED_IMPORTS in scripts/check-no-network.sh.
ALLOW_LIBS='^(SwiftUI|Foundation|Photos|UIKit|CoreGraphics|Vision|Accelerate|CoreFoundation|PhotosUI|QuartzCore|ImageIO|CoreImage|CoreText|UniformTypeIdentifiers|libobjc|libSystem|libswift.*|libc\+\+.*|DeveloperToolsSupport)$'
DENY_SYMS='_OBJC_CLASS_\$_(NSURLSession|NSURLConnection|NSURLRequest|NSMutableURLRequest|NSURLDownload|NSNetService|NSNetServiceBrowser|NSUbiquitousKeyValueStore|WKWebView|SFSafariViewController|UIPasteboard|UIActivityViewController)$|\$s7SwiftUI10AsyncImage|^_(socket|connect|bind|listen|accept|sendto|recvfrom|getaddrinfo|gethostbyname|CFStreamCreatePairWithSocketToHost|CFHostCreateWithName|CFSocketCreate|nw_connection_create|nw_listener_create)$'
failed=0

for tool in otool nm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: $tool not found, so the built app cannot be checked"
    exit 1
  fi
done

if [ ! -f "$app/Stilltrim" ]; then
  echo "error: no Stilltrim binary in $app"
  failed=1
fi

for binary in "$app/Stilltrim" "$app/Stilltrim.debug.dylib" "$app/__preview.dylib"; do
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
  if ! symbols=$(nm -m -u "$binary" 2>&1); then
    echo "error: nm could not read $(basename "$binary"): $symbols"
    failed=1
    continue
  fi
  bad_libraries=$(echo "$symbols" | sed -n 's/.*(from \(.*\))$/\1/p' | sort -u | grep -vE "$ALLOW_LIBS" || true)
  if [ -n "$bad_libraries" ]; then
    echo "error: $(basename "$binary") binds symbols from a library that is not on the allow-list: $(echo $bad_libraries). If it is local and deliberate, add it to ALLOW_LIBS in scripts/check-built-app.sh"
    failed=1
  fi
  bad_symbols=$(echo "$symbols" | sed -E 's/^ *\(undefined\) (weak )?external ([^ ]+).*/\2/' | grep -E "$DENY_SYMS" | sort -u || true)
  if [ -n "$bad_symbols" ]; then
    echo "error: $(basename "$binary") uses a networking symbol: $(echo $bad_symbols | cut -c1-110)"
    failed=1
  fi
done

if [ -d "$app/Frameworks" ]; then
  echo "error: $app embeds frameworks: $(ls "$app/Frameworks" | tr '\n' ' ')"
  failed=1
fi

exit $failed
