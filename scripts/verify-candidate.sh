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
    hdiutil detach -quiet "$scratch/mount"
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT
python3 - "$output" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
output = Path(sys.argv[1])
manifest = json.loads((output / 'CANDIDATE.json').read_text())
for artifact in manifest['artifacts'].values():
    name = artifact['file']
    if Path(name).name != name:
        raise SystemExit('Artifact must be in the candidate directory')
    if hashlib.sha256((output / name).read_bytes()).hexdigest() != artifact['sha256']:
        raise SystemExit('Candidate checksum mismatch')
PY
version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["productVersion"])' "$output/CANDIDATE.json")
# validate_inputs rejects path and command text before using the version in paths.
python3 - "$root" "$output" <<'PY'
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
python3 - "$root" "$output" "$scratch" "$version" <<'PY'
import json
from pathlib import Path
import plistlib
import runpy
import sys
root, output, scratch = map(Path, sys.argv[1:4])
manifest = json.loads((output / 'CANDIDATE.json').read_text())
cli = scratch / f'runstir-{sys.argv[4]}-macos-arm64'
app = scratch / 'mount/Runstir.app'
gui_build = json.loads((app / 'Contents/Resources/BUILD.json').read_text())
cli_build = json.loads((cli / 'BUILD.json').read_text())
runpy.run_path(str(root / 'scripts/validate-release-input.py'))['validate_candidate'](
    manifest, cli_build, gui_build)
plist = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if (plist.get('RunstirProductVersion') != manifest['productVersion']
        or plist['CFBundleShortVersionString'] != manifest['productVersion'].split('-')[0]):
    raise SystemExit('GUI bundle version differs from candidate')
if (app / 'Contents/MacOS/mobile').exists():
    raise SystemExit('GUI must work independently of the CLI')
for resource in ['mobile_Core.bundle', 'mobile_AndroidKit.bundle']:
    if not (app / resource).is_dir():
        raise SystemExit(f'Missing GUI resource: {resource}')
if not (app / 'Contents/MacOS/Runstir').is_file():
    raise SystemExit('Missing GUI executable')
print('Candidate identities, checksums and mounted GUI bundle passed; interactive GUI and Gatekeeper remain separate gates.')
PY
