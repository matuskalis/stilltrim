#!/bin/bash
# Downloads public sample photographs into .fixtures/ (gitignored) for CalibrationTests.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .fixtures
for id in 10 11 13 14 15 16 17 18 19 20 21 22 24 25 26 27; do
  file=".fixtures/p$id.jpg"
  [ -s "$file" ] || curl -sfL -m 40 -o "$file" "https://picsum.photos/id/$id/1600/1066.jpg"
  file "$file" | grep -q "JPEG image data" || { echo "not a JPEG: $file" >&2; rm -f "$file"; exit 1; }
done
echo "$(ls .fixtures/*.jpg | wc -l | tr -d ' ') fixtures in .fixtures/"
