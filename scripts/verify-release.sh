#!/bin/bash
set -euo pipefail
if [[ $# != 1 ]]; then
  echo 'Usage: scripts/verify-release.sh <archive.tar.gz>' >&2
  exit 64
fi
archive=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
(cd "$(dirname "$archive")" && shasum -a 256 -c "$(basename "$archive").sha256")
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
tar -xzf "$archive" -C "$scratch"
package=$(find "$scratch" -mindepth 1 -maxdepth 1 -type d)
test -x "$package/mobile"
test -f "$package/mobile_Core.bundle/Contents/Resources/matrix.json"
test -f "$package/mobile_AndroidKit.bundle/Contents/Resources/mobile-doctor.gradle"
test -s "$package/LICENSE"
test -s "$package/THIRD_PARTY_NOTICES.md"
test -s "$package/INSTALL.md"
test -s "$package/BUILD.json"
mkdir "$scratch/bin"
ln -s "$package/mobile" "$scratch/bin/mobile"
mobile="$scratch/bin/mobile"
cd "$scratch"
"$mobile" --help > /dev/null
"$mobile" doctor --platform android --help > /dev/null
for platform in ios android; do
  result="$scratch/$platform.json"
  status=0
  "$mobile" doctor --platform "$platform" --json > "$result" || status=$?
  # Host requirements can fail outside a project; a tool failure cannot pass this smoke.
  test "$status" -le 1
  python3 - "$result" "$package/BUILD.json" <<'PY'
import json
import sys
from pathlib import Path
result, metadata = (json.loads(Path(path).read_text()) for path in sys.argv[1:])
assert result['toolVersion'] == metadata['toolVersion']
assert result['command'] == 'doctor'
PY
done
echo 'Archive smoke passed outside the build directory (iOS + Android).'
