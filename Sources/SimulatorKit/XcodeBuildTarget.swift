import Core
import Foundation

/// What xcodebuild is pointed at. A workspace when the project has one — CocoaPods
/// puts the Pods there and building the project alone fails at link time — and the
/// `.xcodeproj` otherwise.
///
/// Not the same question as "what do I list schemes from": that is always the
/// project, because a workspace answers with every Pod scheme it contains.
struct XcodeBuildTarget {
    enum Kind: String {
        case workspace = "-workspace"
        case project = "-project"
    }

    let kind: Kind
    let url: URL
    var freezesPackages = false

    var arguments: [String] {
        [kind.rawValue, url.path] + (freezesPackages
            ? ["-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile"] : [])
    }

    /// The single `ios/*.xcworkspace`, else the single `ios/*.xcodeproj`. Shallow, so
    /// `Pods.xcodeproj` and the `project.xcworkspace` inside every `.xcodeproj` are
    /// both out of reach.
    ///
    /// - Returns: nil when `ios/` holds neither, or holds more than one of each and
    ///   therefore no way to pick without guessing.
    static func locate(
        inIOSDirectoryOf anchor: ProjectAnchor,
        fileManager: FileManager = .default
    ) -> XcodeBuildTarget? {
        let ios = anchor.iosDirectory
        if anchor.framework == .nativeIOS {
            guard let name = anchor.iosContainer, name == URL(fileURLWithPath: name).lastPathComponent,
                fileManager.fileExists(atPath: ios.appendingPathComponent(name).path)
            else { return nil }
            let kind: Kind
            if name.hasSuffix(".xcworkspace") { kind = .workspace }
            else if name.hasSuffix(".xcodeproj") { kind = .project }
            else { return nil }
            return XcodeBuildTarget(kind: kind, url: ios.appendingPathComponent(name), freezesPackages: true)
        }
        let names = (try? fileManager.contentsOfDirectory(atPath: ios.path)) ?? []
        let workspaces = names.filter { $0.hasSuffix(".xcworkspace") }
        if let workspace = workspaces.only {
            return XcodeBuildTarget(kind: .workspace, url: ios.appendingPathComponent(workspace))
        }
        // Several workspaces is not "no workspace": falling through to the project
        // would build the one target CocoaPods cannot link, and blame the code.
        guard workspaces.isEmpty,
            let project = XcodeSchemeList.project(inIOSDirectoryOf: anchor, fileManager: fileManager)
        else { return nil }
        return XcodeBuildTarget(kind: .project, url: project)
    }
}

/// The part of `xcodebuild -showBuildSettings -json` that says what was built.
/// Asking xcodebuild beats parsing the build log: the log's format moves between
/// Xcode versions, and these keys are the ones Xcode itself resolved.
struct XcodeBuildSettings {
    /// One per target the scheme builds — an app, and whatever extensions and test
    /// bundles come with it.
    struct Entry: Decodable {
        let target: String
        let buildSettings: [String: String]
    }

    let entries: [Entry]

    static func decode(_ standardOutput: String) -> XcodeBuildSettings? {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: Data(standardOutput.utf8)) else {
            return nil
        }
        return XcodeBuildSettings(entries: entries)
    }

    /// The app bundle, out of a scheme that may also build extensions and test
    /// bundles. The scheme's own target wins; failing that, the one `.app` there is.
    ///
    /// Never a guess between several: a scheme that builds an app and a test host
    /// builds two `.app`s, and handing install whichever xcodebuild printed first is
    /// the same coin-flip `SchemeSelector` refuses to make.
    func application(scheme: String) -> BuiltProduct? {
        guard let settings = applicationSettings(scheme: scheme),
            let directory = settings["BUILT_PRODUCTS_DIR"],
            let name = settings["FULL_PRODUCT_NAME"],
            let bundleIdentifier = settings["PRODUCT_BUNDLE_IDENTIFIER"]
        else { return nil }
        return BuiltProduct(
            path: URL(fileURLWithPath: directory).appendingPathComponent(name).path,
            bundleIdentifier: bundleIdentifier
        )
    }

    func applicationSettings(scheme: String) -> [String: String]? {
        let apps = entries.filter { $0.buildSettings["FULL_PRODUCT_NAME"]?.hasSuffix(".app") == true }
        return (apps.first(where: { $0.target == scheme }) ?? apps.only)?.buildSettings
    }
}
