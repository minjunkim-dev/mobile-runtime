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
dmg="$output/Runstir-$version-macos-arm64.dmg"
for file in "$archive" "$archive.sha256" "$dmg" "$dmg.sha256" "$output/CANDIDATE.json" "$output/runstir-candidate.rb"; do
  test ! -e "$file"
  test ! -L "$file"
done
if [[ -n ${RUNSTIR_SIGNING_IDENTITY:-} || -n ${RUNSTIR_NOTARY_PROFILE:-} ]]; then
  : "${RUNSTIR_SIGNING_IDENTITY:?Provide a Developer ID Application identity}"
  : "${RUNSTIR_NOTARY_PROFILE:?Provide an existing notarytool keychain profile}"
  [[ $RUNSTIR_SIGNING_IDENTITY == 'Developer ID Application: '* ]]
fi
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
revision=$(git rev-parse HEAD)
mkdir "$scratch/source"
git archive "$revision" | tar -x -C "$scratch/source"
cp "$scratch/source/Package.resolved" "$scratch/resolved.json"
cd "$scratch/source"
python3 -I - "$version" <<'PY'
from pathlib import Path
import re
import sys
path = Path('Sources/Core/ProductVersion.swift')
source, count = re.subn(r'(?m)^public let runstirProductVersion = "[^"]+"$',
                       f'public let runstirProductVersion = "{sys.argv[1]}"', path.read_text())
if count != 1:
    raise SystemExit('Expected one shared product version declaration')
path.write_text(source)
PY

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

python3 -I - "$scratch/build/checkouts" "$stage" "$version" "$revision" <<'PY'
import json
import hashlib
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
objects = sorted(path for path in checkouts.parent.rglob('*.o')
                 if any(part in {'Core.build', 'Core-t.build'} for part in path.parts))
if not objects:
    raise SystemExit('Missing Core build objects')
core_objects = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in objects}
if len(core_objects) != len(objects):
    raise SystemExit('Ambiguous Core object names')
metadata['coreBuildIdentity'] = hashlib.sha256(
    json.dumps(core_objects, sort_keys=True).encode()).hexdigest()
metadata['coreObjects'] = core_objects
if metadata['toolVersion'] != sys.argv[3]:
    raise SystemExit('CLI product version differs from candidate version')
(stage / 'BUILD.json').write_text(json.dumps(metadata, indent=2) + '\n')
PY

app="$scratch/disk/Runstir.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$products/Runstir" "$app/Contents/MacOS/Runstir"
cp packaging/Runstir-Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version%%-*}" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${version##*.}" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :RunstirProductVersion string $version" "$app/Contents/Info.plist"
cp -R "$stage/mobile_Core.bundle" "$stage/mobile_AndroidKit.bundle" "$app/"
cp "$stage/BUILD.json" "$stage/LICENSE" "$stage/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/"
cp docs/release-install.md "$scratch/disk/INSTALL.md"
ln -s /Applications "$scratch/disk/Applications"
signed=false
if [[ -n ${RUNSTIR_SIGNING_IDENTITY:-} ]]; then
  codesign --force --options runtime --timestamp --sign "$RUNSTIR_SIGNING_IDENTITY" "$stage/mobile"
  codesign --force --options runtime --timestamp --sign "$RUNSTIR_SIGNING_IDENTITY" "$app"
  codesign --verify --strict "$stage/mobile"
  codesign --verify --deep --strict "$app"
  ditto -c -k --keepParent "$stage" "$scratch/cli-notary.zip"
  xcrun notarytool submit "$scratch/cli-notary.zip" --keychain-profile "$RUNSTIR_NOTARY_PROFILE" \
    --wait --output-format json > "$scratch/cli-notary.json"
  python3 -I -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["status"] != "Accepted")' "$scratch/cli-notary.json"
  signed=true
fi
hdiutil create -quiet -fs HFS+ -volname Runstir -srcfolder "$scratch/disk" "$dmg"
if [[ $signed == true ]]; then
  codesign --timestamp --sign "$RUNSTIR_SIGNING_IDENTITY" "$dmg"
  xcrun notarytool submit "$dmg" --keychain-profile "$RUNSTIR_NOTARY_PROFILE" \
    --wait --output-format json > "$scratch/gui-notary.json"
  python3 -I -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["status"] != "Accepted")' "$scratch/gui-notary.json"
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
fi
COPYFILE_DISABLE=1 tar -czf "$archive" -C "$scratch" "$name"
(cd "$output" && shasum -a 256 "$name.tar.gz" > "$name.tar.gz.sha256")
(cd "$output" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
python3 -I - "$stage/BUILD.json" "$output" "$signed" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import runpy
import sys
build = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2])
version = build['releaseVersion']
signed = sys.argv[3] == 'true'
manifest = {
    'schemaVersion': 1, 'productVersion': version, 'sourceSHA': build['sourceRevision'],
    'coreBuildIdentity': build['coreBuildIdentity'],
    'ciRun': os.environ.get('GITHUB_RUN_ID'),
    'signing': 'developer-id' if signed else 'unsigned',
    'notarization': 'accepted' if signed else 'not-requested',
    'distributionReady': False,
    'artifacts': {kind: {'file': name, 'sha256': hashlib.sha256((output / name).read_bytes()).hexdigest()}
                  for kind, name in [('cli', f'runstir-{version}-macos-arm64.tar.gz'),
                                     ('gui', f'Runstir-{version}-macos-arm64.dmg')]},
}
runpy.run_path('scripts/validate-release-input.py')['validate_candidate'](manifest, build, build)
archive = manifest['artifacts']['cli']
(output / 'runstir-candidate.rb').write_text(f'''class RunstirCandidate < Formula
  desc "Restricted Runstir validation candidate"
  homepage "https://github.com/minjunkim-dev/mobile-runtime"
  url ENV.fetch("RUNSTIR_CANDIDATE_URL")
  version "{version}"
  sha256 "{archive['sha256']}"
  license "Apache-2.0"
  depends_on arch: :arm64
  depends_on macos: :sonoma
  keg_only "validation candidate; preserves the separate mobile CLI"
  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"mobile"
  end
  test do
    assert_equal version.to_s, shell_output("#{{bin}}/mobile --version").strip
    assert_path_exists libexec/"mobile_Core.bundle"
    assert_path_exists libexec/"mobile_AndroidKit.bundle"
  end
end
''')
formula = output / 'runstir-candidate.rb'
manifest['artifacts']['homebrew'] = {
    'file': formula.name, 'sha256': hashlib.sha256(formula.read_bytes()).hexdigest()}
(output / 'CANDIDATE.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
# Remove the compiled absolute resource fallback before running the packaged binary.
rm -rf "$scratch/build"
scripts/verify-release.sh "$archive"
scripts/verify-candidate.sh "$output"
printf 'Archive: %s\nGUI: %s\nCandidate: %s/CANDIDATE.json\n' "$archive" "$dmg" "$output"
