#!/bin/bash
# Runs the screenshot classifier on every png, jpg, jpeg and heic file in a folder, on the Mac (AirDrop real screenshots, no simulator).
# Usage: scripts/classify-folder.sh <folder> [--dump]. --dump also prints each file's recognised text lines and positions.
set -euo pipefail
# The folder may be relative to the caller, so make it absolute before the cd.
args=()
for arg in "$@"; do
  if [ -d "$arg" ]; then args+=("$(cd "$arg" && pwd)"); else args+=("$arg"); fi
done
cd "$(dirname "$0")/.."
mkdir -p .seed
# swiftc only allows top-level code in a file called main.swift when several files are compiled together.
cp scripts/ClassifyFolder.swift .seed/main.swift
core=Packages/CleanupCore/Sources/CleanupCore
swiftc -O "$core/ScreenshotClassifier.swift" "$core/ScreenshotAnalyzer.swift" .seed/main.swift -o .seed/ClassifyFolder
./.seed/ClassifyFolder ${args[@]+"${args[@]}"}
