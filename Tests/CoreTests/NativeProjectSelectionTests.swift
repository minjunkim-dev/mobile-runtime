import Core
import Foundation
import TestSupport
import Testing

@Suite("native project selection")
struct NativeProjectSelectionTests {
    @Test("React Native candidate ids remain stable beside another framework", arguments: [
        ProjectFramework.flutter, .nativeIOS, .nativeAndroid
    ])
    func reactNativeCandidateID(framework: ProjectFramework) throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.76.5"}}"#)
        try repo.write("ios/.keep", "")
        switch framework {
        case .flutter:
            try repo.write("pubspec.yaml", "dependencies:\n  flutter:\n    sdk: flutter\n")
        case .nativeIOS:
            try repo.write("App.xcodeproj/project.pbxproj", "native app")
        case .nativeAndroid:
            try repo.write("settings.gradle", "rootProject.name = 'native'")
            try repo.write("gradlew", "#!/bin/sh")
        case .reactNative:
            Issue.record("The additional declaration must use another framework")
        }
        let selection = try ProjectInspectionInput(directory: repo.root, environment: [:]).selection()
        #expect(selection.candidates.first { $0.framework == .reactNative }?.id == ".")
        let chosen = try ProjectInspectionInput(directory: repo.root, environment: [:], app: ".").selection()
        #expect(chosen.selected?.framework == .reactNative)
        #expect(chosen.error == nil)
    }

    @Test("a root native iOS project is selected without a JavaScript manifest")
    func nativeIOSRoot() throws {
        let repo = try FixtureRepo()
        try repo.write("Sample.xcodeproj/project.pbxproj", "// native project fixture")
        let selection = try ProjectInspectionInput(directory: repo.root, environment: [:]).selection()
        #expect(selection.candidates.map(\.id) == ["Sample.xcodeproj"])
        #expect(selection.selected?.app.path == repo.root.path)
        #expect(selection.platform == .ios)
        #expect(selection.requiredInput.isEmpty)
        let encoded = try JSONEncoder().encode(selection)
        let document = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let selected = document["selected"] as? [String: Any]
        #expect(selected?["framework"] as? String == "native-ios")
        #expect(try String(contentsOf: repo.url("Sample.xcodeproj/project.pbxproj"), encoding: .utf8)
            == "// native project fixture")
        #expect(!FileManager.default.fileExists(atPath: repo.url("package.json").path))
    }

    @Test("multiple native containers require a reported id and preserve app-root identity")
    func multipleNativeContainers() throws {
        let repo = try FixtureRepo()
        try repo.write("One.xcodeproj/project.pbxproj", "one")
        try repo.write("Two.xcodeproj/project.pbxproj", "two")
        let selection = try ProjectInspectionInput(directory: repo.root, environment: [:]).selection()
        #expect(selection.candidates.map(\.id) == ["One.xcodeproj", "Two.xcodeproj"])
        #expect(selection.selected == nil)
        #expect(selection.requiredInput == ["--app"])
        let chosen = try ProjectInspectionInput(directory: repo.root, environment: [:], app: "Two.xcodeproj").selection()
        #expect(chosen.selected?.id == "Two.xcodeproj")
        #expect(chosen.selected?.app.path == repo.root.path)
        #expect(chosen.requiredInput.isEmpty)
        let invalid = try ProjectInspectionInput(directory: repo.root, environment: [:], app: "missing.xcodeproj").selection()
        #expect(invalid.error != nil)
        #expect(invalid.selected == nil)
    }

    @Test("framework native hosts remain part of their original framework candidate")
    func embeddedReactNativeHost() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies":{"react-native":"0.76.5"}}"#)
        try repo.write("ios/Sample.xcodeproj/project.pbxproj", "native host")
        let selection = try ProjectInspectionInput(directory: repo.url("ios"), environment: [:]).selection()
        #expect(selection.candidates.count == 1)
        #expect(selection.selected?.app.path == repo.root.path)
        let encoded = try JSONEncoder().encode(selection)
        let document = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let selected = document["selected"] as? [String: Any]
        #expect(selected?["framework"] as? String == "react-native")
    }

    @Test("Flutter native hosts do not become standalone native candidates")
    func embeddedFlutterHost() throws {
        let repo = try FixtureRepo()
        try repo.write("pubspec.yaml", "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
        try repo.write("ios/Runner.xcodeproj/project.pbxproj", "host")
        try repo.write("android/settings.gradle", "host")
        try repo.write("android/gradlew", "host")
        let selection = try ProjectInspectionInput(directory: repo.url("android"), environment: [:]).selection()
        #expect(selection.candidates.count == 1)
        #expect(selection.selected?.framework == .flutter)
        #expect(selection.selected?.id == repo.root.path)
        #expect(selection.requiredInput == ["--platform"])
    }

    @Test("native Android keeps its root identity without acquiring a JavaScript contract")
    func nativeAndroidRoot() throws {
        let repo = try FixtureRepo()
        try repo.write("settings.gradle.kts", "rootProject.name = \"native\"")
        try repo.write("gradlew", "#!/bin/sh")
        let selection = try ProjectInspectionInput(directory: repo.root, environment: [:]).selection()
        let candidate = try #require(selection.selected)
        #expect(candidate.framework == .nativeAndroid)
        #expect(selection.platform == .android)
        let anchor = try #require(ProjectAnchor.detect(candidate: candidate))
        #expect(anchor.directory.path == repo.root.path)
        #expect(anchor.commonChecks(runner: FakeProcessRunner(), context: ConfigContext.detect(anchor: anchor, workingDirectory: repo.root)).isEmpty)
    }

    @Test("native iOS requirements never load the React Native compatibility matrix")
    func nativeRequirements() throws {
        let repo = try FixtureRepo()
        try repo.write("App.xcodeproj/project.pbxproj", "fixture")
        try repo.write(".xcode-version", "26.0")
        try repo.write("Podfile", "platform :ios, '17.0'")
        let anchor = try #require(ProjectAnchor.detect(from: repo.root))
        let lookup = MatrixLookup.resolve(anchor: anchor, loading: {
            Issue.record("A native project must not query the React Native matrix")
            return try CompatibilityMatrix.bundled()
        })
        guard case .requirement(let xcode, _) = lookup.xcode,
              case .requirement(let runtime, let source) = lookup.runtime else {
            Issue.record("Native declarations should resolve without React Native")
            return
        }
        #expect(xcode.text == "27.0")
        #expect(runtime.text == "17.0")
        #expect(source.origin.contains("Podfile"))
        #expect(anchor.iosDirectory.path == repo.root.path)
    }

    @Test("an Xcode project's internal workspace never becomes the app root")
    func internalWorkspace() throws {
        let repo = try FixtureRepo()
        try repo.write("App.xcodeproj/project.pbxproj", "app")
        try repo.write("App.xcodeproj/project.xcworkspace/contents.xcworkspacedata", "<Workspace/>")
        let selection = try ProjectInspectionInput(directory: repo.url("App.xcodeproj"), environment: [:]).selection()
        #expect(selection.candidates.count == 1)
        #expect(selection.selected?.app.path == repo.root.path)
        #expect(selection.selected?.iosContainer == "App.xcodeproj")
    }
}
