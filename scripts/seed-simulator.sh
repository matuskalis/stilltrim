#!/bin/bash
# Fills a simulator's photo library with test media: near-duplicates, blurry and blank frames,
# screenshots and one big video. Usage: scripts/seed-simulator.sh <simulator UDID or "booted">
set -euo pipefail
cd "$(dirname "$0")/.."
target="${1:-booted}"
[ -d .fixtures ] || ./scripts/fetch-fixtures.sh
rm -rf .seed
mkdir -p .seed
swiftc -O scripts/SeedMedia.swift -o .seed/SeedMedia
./.seed/SeedMedia "$PWD/.fixtures" "$PWD/.seed/media"
xcrun simctl addmedia "$target" .seed/media/*
echo "seeded $(ls .seed/media | wc -l | tr -d ' ') files"
