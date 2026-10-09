#!/usr/bin/env bash
# Build a local development bundle; signed/notarized distribution has a separate release gate.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
swift build --product Runstir --force-resolved-versions
binary="$(swift build --show-bin-path)/Runstir"
bundle="$root/.build/Runstir.app"
mkdir -p "$bundle/Contents/MacOS"
cp "$binary" "$bundle/Contents/MacOS/Runstir"
cp "$root/packaging/Runstir-Info.plist" "$bundle/Contents/Info.plist"
for resources in "$(dirname "$binary")"/*.bundle; do
    cp -R "$resources" "$bundle/"
done
open "$bundle"
