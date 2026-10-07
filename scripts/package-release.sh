#!/bin/bash
set -euo pipefail

if [[ $# != 2 || ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$ ]]; then
  echo 'Usage: scripts/package-release.sh <version, e.g. 0.1.0-alpha.1> <output-directory>' >&2
  exit 64
fi
if [[ $(uname -s) != Darwin || $(uname -m) != arm64 ]]; then
  echo 'Release packaging requires macOS arm64.' >&2
  exit 1
fi
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
git diff --quiet
git diff --cached --quiet
version=$1
mkdir -p "$2"
output=$(cd "$2" && pwd)
name="runstir-$version-macos-arm64"
archive="$output/$name.tar.gz"
test ! -e "$archive"
test ! -e "$archive.sha256"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
revision=$(git rev-parse HEAD)
mkdir "$scratch/source"
git archive "$revision" | tar -x -C "$scratch/source"
cp "$scratch/source/Package.resolved" "$scratch/resolved.json"
cd "$scratch/source"

# A disposable build path proves the archive cannot use a checkout resource fallback.
swift build -c release --force-resolved-versions --scratch-path "$scratch/build"
cmp Package.resolved "$scratch/resolved.json"
products=$(swift build -c release --show-bin-path --scratch-path "$scratch/build")
test "$(lipo -archs "$products/mobile")" = arm64
stage="$scratch/$name"
mkdir "$stage"
cp "$products/mobile" "$stage/"
for bundle in mobile_Core.bundle mobile_AndroidKit.bundle; do
  test -d "$products/$bundle"
  cp -R "$products/$bundle" "$stage/"
done
cp LICENSE "$stage/"
cp docs/release-install.md "$stage/INSTALL.md"

python3 - "$scratch/build/checkouts" "$stage" "$version" "$revision" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

checkouts, stage = map(Path, sys.argv[1:3])
pins = json.loads(Path('Package.resolved').read_text())['pins']
directories = {path.name.lower(): path for path in checkouts.iterdir() if path.is_dir()}
notices = ['# Runstir third-party notices\n\nUnmodified dependencies from Package.resolved.\n']
for pin in pins:
    identity, state = pin['identity'], pin['state']
    checkout = directories[identity.lower()]
    revision = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != state['revision']:
        raise SystemExit(f'Unpinned dependency: {identity}')
    files = sorted(path for path in checkout.iterdir()
                   if path.is_file() and path.name.lower().startswith(('license', 'notice', 'copying')))
    if not any(path.name.lower().startswith(('license', 'copying')) for path in files):
        raise SystemExit(f'Missing license: {identity}')
    notices.append(f"\n## {identity} {state['version']}\n\n{pin['location']}\nRevision: {revision}\n")
    for path in files:
        notices.append(f'\n### {path.name}\n\n{path.read_text()}\n')
notices.append('\n## libyaml (vendored by Yams)\n\n'
               'License source: https://github.com/yaml/libyaml/blob/0.2.5/License\n\n'
               + Path('licenses/libyaml-LICENSE').read_text())
(stage / 'THIRD_PARTY_NOTICES.md').write_text('\n'.join(notices))
metadata = {
    'product': 'Runstir', 'releaseVersion': sys.argv[3], 'command': 'mobile',
    'sourceRevision': sys.argv[4],
    'architecture': 'arm64',
    'toolVersion': subprocess.check_output([str(stage / 'mobile'), '--version'], text=True).strip(),
    'swift': subprocess.check_output(['swift', '--version'], text=True).strip(),
    'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
    'dependencies': pins,
}
(stage / 'BUILD.json').write_text(json.dumps(metadata, indent=2) + '\n')
PY

COPYFILE_DISABLE=1 tar -czf "$archive" -C "$scratch" "$name"
(cd "$output" && shasum -a 256 "$name.tar.gz" > "$name.tar.gz.sha256")
# Remove the compiled absolute resource fallback before running the packaged binary.
rm -rf "$scratch/build"
scripts/verify-release.sh "$archive"
printf 'Archive: %s\nChecksum: %s.sha256\n' "$archive" "$archive"
