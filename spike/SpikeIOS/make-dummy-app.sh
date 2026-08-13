#!/bin/bash
# SPIKE — 시뮬레이터 설치 테스트용 최소 .app 번들 생성
set -euo pipefail
cd "$(dirname "$0")"

rm -rf Dummy.app build-dummy
mkdir -p Dummy.app build-dummy

cat > build-dummy/main.swift <<'EOF'
import UIKit
@main class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let vc = UIViewController()
        vc.view.backgroundColor = .systemGreen
        let label = UILabel(frame: vc.view.bounds)
        label.text = "SpikeIOS"
        label.textAlignment = .center
        label.font = .boldSystemFont(ofSize: 48)
        vc.view.addSubview(label)
        window?.rootViewController = vc
        window?.makeKeyAndVisible()
        return true
    }
}
EOF

SDK=$(xcrun -sdk iphonesimulator --show-sdk-path)
swiftc -sdk "$SDK" -target arm64-apple-ios16.0-simulator -parse-as-library \
    build-dummy/main.swift -o Dummy.app/Dummy

cat > Dummy.app/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Dummy</string>
    <key>CFBundleIdentifier</key><string>com.spike.dummy</string>
    <key>CFBundleName</key><string>SpikeDummy</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>UILaunchScreen</key><dict/>
</dict>
</plist>
EOF

echo "OK: $(pwd)/Dummy.app"
