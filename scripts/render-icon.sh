#!/bin/bash
# Renders Design/AppIcon.svg into the 1024 px opaque PNG the asset catalog needs.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
qlmanage -t -s 1024 -o "$tmp" Design/AppIcon.svg >/dev/null 2>&1
swift scripts/FlattenPNG.swift "$tmp/AppIcon.svg.png" App/Assets.xcassets/AppIcon.appiconset/icon-1024.png
rm -rf "$tmp"
sips -g pixelWidth -g pixelHeight -g hasAlpha App/Assets.xcassets/AppIcon.appiconset/icon-1024.png | tail -3
