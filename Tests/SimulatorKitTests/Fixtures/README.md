# Fixtures

Real captured output — nothing here is hand-written. Captured 2026-08-13 on
macOS 26 (Darwin 25.6.0), Xcode 26.6 (17F113), iOS 26.5 runtime (23F77), the same
machine as the SpikeIOS run in `spike/ios`.

| File | Command |
|---|---|
| `xcodebuild-version.stdout.txt` | `xcodebuild -version` (exit 0) |
| `xcodebuild-version-commandlinetools.stderr.txt` | `DEVELOPER_DIR=/Library/Developer/CommandLineTools xcodebuild -version` (exit 1) |
| `xcodebuild-version-broken-developer-dir.stderr.txt` | `DEVELOPER_DIR=/tmp/nope xcodebuild -version` (exit 1) |
| `simctl-list-runtimes.stdout.json` | `xcrun simctl list runtimes -j` (exit 0) |
| `simctl-commandlinetools.stderr.txt` | `DEVELOPER_DIR=/Library/Developer/CommandLineTools xcrun simctl list runtimes -j` (exit 72) |
