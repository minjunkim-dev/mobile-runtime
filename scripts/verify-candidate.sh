#!/bin/bash
set -euo pipefail
if [[ $# != 1 ]]; then
  echo 'Usage: scripts/verify-candidate.sh <candidate-directory>' >&2
  exit 64
fi
root=$(cd "$(dirname "$0")/.." && pwd)
output=$(cd "$1" && pwd)
scratch=$(mktemp -d)
mounted=false
cleanup() {
  if [[ $mounted == true ]]; then
    if ! hdiutil detach -quiet "$scratch/mount" && ! hdiutil detach -quiet -force "$scratch/mount"; then
      echo "DMG still mounted at $scratch/mount" >&2
      return 1
    fi
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT
# Candidate files must not shadow Python modules during verification.
python3 -I - "$root" "$output" <<'PY'
import json
from pathlib import Path
import runpy
import sys
output = Path(sys.argv[2])
manifest = json.loads((output / 'CANDIDATE.json').read_text())
runpy.run_path(str(Path(sys.argv[1]) / 'scripts/validate-release-input.py'))['validate_candidate_artifacts'](
    manifest, output)
PY
version=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["productVersion"])' "$output/CANDIDATE.json")
# validate_inputs rejects path and command text before using the version in paths.
python3 -I - "$root" "$output" <<'PY'
import json
from pathlib import Path
import runpy
import sys
import tarfile
manifest = json.loads((Path(sys.argv[2]) / 'CANDIDATE.json').read_text())
validation = runpy.run_path(str(Path(sys.argv[1]) / 'scripts/validate-release-input.py'))
validation['validate_inputs'](manifest['productVersion'], manifest['sourceSHA'])
archive = Path(sys.argv[2]) / f"runstir-{manifest['productVersion']}-macos-arm64.tar.gz"
with tarfile.open(archive, 'r:gz') as source:
    validation['validate_candidate_archive'](source, manifest['productVersion'])
PY
tar -xzf "$output/runstir-$version-macos-arm64.tar.gz" -C "$scratch"
mkdir "$scratch/mount"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$scratch/mount" "$output/Runstir-$version-macos-arm64.dmg"
mounted=true
python3 -I - "$root" "$output" "$scratch" "$version" <<'PY'
import json
import os
from pathlib import Path
import plistlib
import runpy
import sys
root, output, scratch = map(Path, sys.argv[1:4])
manifest = json.loads((output / 'CANDIDATE.json').read_text())
cli = scratch / f'runstir-{sys.argv[4]}-macos-arm64'
app = scratch / 'mount/Runstir.app'
if {path.name for path in app.iterdir()} != {'Contents'}:
    raise SystemExit('Unexpected GUI app top-level content; expected only Contents')
gui_build = json.loads((app / 'Contents/Resources/BUILD.json').read_text())
cli_build = json.loads((cli / 'BUILD.json').read_text())
runpy.run_path(str(root / 'scripts/validate-release-input.py'))['validate_candidate'](
    manifest, cli_build, gui_build)
plist = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if (plist.get('RunstirProductVersion') != manifest['productVersion']
        or plist['CFBundleShortVersionString'] != manifest['productVersion'].split('-')[0]):
    raise SystemExit('GUI bundle version differs from candidate')
if (app / 'Contents/MacOS/mobile').is_symlink() or (app / 'Contents/MacOS/mobile').exists():
    raise SystemExit('GUI must work independently of the CLI')
if not (cli / 'mobile').is_file() or not os.access(cli / 'mobile', os.X_OK):
    raise SystemExit('Missing CLI executable')
for label, product in [('CLI', cli), ('GUI', app / 'Contents/Resources')]:
    for bundle, name in [('mobile_Core.bundle', 'matrix.json'),
                         ('mobile_AndroidKit.bundle', 'mobile-doctor.gradle')]:
        resource = product / bundle
        if not any(path.is_file() for path in [resource / name, resource / 'Contents/Resources' / name]):
            raise SystemExit(f'Missing {label} resource: {bundle}/{name}')
if not (app / 'Contents/MacOS/Runstir').is_file():
    raise SystemExit('Missing GUI executable')
print('Candidate identities, checksums and mounted GUI bundle passed; interactive GUI and Gatekeeper remain separate gates.')
PY
if [[ $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["signing"])' "$output/CANDIDATE.json") == developer-id ]]; then
  requirement='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
  codesign --verify --strict -R "$requirement" "$scratch/runstir-$version-macos-arm64/mobile"
  codesign --verify --deep --strict -R "$requirement" "$scratch/mount/Runstir.app"
  xcrun stapler validate "$output/Runstir-$version-macos-arm64.dmg"
fi
ruby -c "$output/runstir-candidate.rb"
