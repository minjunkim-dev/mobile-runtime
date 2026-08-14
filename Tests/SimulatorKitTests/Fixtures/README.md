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
| `simctl-list-devices.stdout.json` | `xcrun simctl list devices -j` (exit 0) |
| `simctl-list-devices-shutdown.stdout.json` | `xcrun simctl list devices "iPhone 16" -j` (exit 0) |
| `simctl-list-devices-none.stdout.json` | `xcrun simctl list devices "iPhone 99" -j` (exit 0) |
| `simctl-list-devicetypes.stdout.json` | `xcrun simctl list devicetypes -j` (exit 0) |
| `simctl-commandlinetools.stderr.txt` | `DEVELOPER_DIR=/Library/Developer/CommandLineTools xcrun simctl list runtimes -j` (exit 72) |

One substitution: the home directory in the device lists' `dataPath` / `logPath`
is written `/Users/USER`, the way `docs/dogfooding/` shortens clone paths to
`$REPO`. Nothing else is edited, and no field any code reads is touched — the
device list is decoded for `name`, `udid`, `state` and `isAvailable`.

The three device lists and the device types were captured 2026-08-14 on the same
machine, which has one simulator of its own and had it booted — `iPhone 16` and
`iPhone 16 Pro` were created with `simctl create` for the capture and deleted
afterwards. The search term is how a list with nothing booted, and a list with
nothing at all, were captured without shutting down or deleting that device.
