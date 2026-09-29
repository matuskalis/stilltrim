#!/bin/bash
# Adds N generated photos to a simulator library for scale tests. Usage: scripts/seed-bulk.sh <UDID> <N>
set -euo pipefail
cd "$(dirname "$0")/.."
target="${1:-booted}"
count="${2:-2000}"
[ -d .fixtures ] || ./scripts/fetch-fixtures.sh
rm -rf .seed/bulk
mkdir -p .seed/bulk
swiftc -O scripts/SeedBulk.swift -o .seed/SeedBulk
./.seed/SeedBulk "$PWD/.fixtures" "$PWD/.seed/bulk" "$count"
xcrun simctl addmedia "$target" .seed/bulk/*
echo "seeded $count bulk photos"
