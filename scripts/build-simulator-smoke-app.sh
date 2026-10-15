#!/usr/bin/env bash
# Build the smallest iOS Simulator app the real-simulator smoke installs and launches.
# No Xcode project, CocoaPods or Node: the smoke checks simctl, not a React Native build.
set -euo pipefail

output="${1:?usage: build-simulator-smoke-app.sh <output-directory>}"
app="$output/RunstirSmoke.app"
source_dir="$(mktemp -d)"
trap 'rm -rf "$source_dir"' EXIT

rm -rf "$app"
mkdir -p "$app"

cat > "$source_dir/main.swift" <<'SWIFT'
import SwiftUI

@main
struct RunstirSmoke: App {
    var body: some Scene {
        WindowGroup { Text("Runstir simulator smoke") }
    }
}
SWIFT

xcrun --sdk iphonesimulator swiftc -parse-as-library \
  -target "$(uname -m)-apple-ios17.0-simulator" \
  "$source_dir/main.swift" -o "$app/RunstirSmoke"

cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>RunstirSmoke</string>
  <key>CFBundleIdentifier</key><string>dev.runstir.simulator-smoke</string>
  <key>CFBundleName</key><string>RunstirSmoke</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key>
  <dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
</dict>
</plist>
PLIST

codesign --force --sign - "$app" >/dev/null
echo "$app"
