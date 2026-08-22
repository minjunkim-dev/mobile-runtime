import Core
import Foundation

/// Shape of `xcodebuild -list -json`. The Xcode **project** is listed rather than
/// the workspace: a workspace's scheme list carries every Pod, which would turn
/// "which scheme should I build" into a hundred wrong answers.
struct XcodeSchemeList: Decodable {
    private struct Container: Decodable {
        let schemes: [String]?
    }

    private enum CodingKeys: String, CodingKey {
        case project
        case workspace
    }

    let schemes: [String]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let listing = try container.decodeIfPresent(Container.self, forKey: .project)
            ?? container.decode(Container.self, forKey: .workspace)
        schemes = listing.schemes ?? []
    }

    static func command(project: URL, environment: [String: String]) -> ProcessCommand {
        ProcessCommand(
            "xcodebuild", ["-list", "-json", "-project", project.path],
            environment: environment,
            timeout: .seconds(120)
        )
    }

    /// Prefer the shallow app project so a workspace does not add every Pod scheme.
    /// A workspace-only root still has enough information to list its shared schemes.
    static func target(
        inIOSDirectoryOf anchor: ProjectAnchor,
        buildTarget: XcodeBuildTarget,
        fileManager: FileManager = .default
    ) -> XcodeBuildTarget {
        project(inIOSDirectoryOf: anchor, fileManager: fileManager).map {
            XcodeBuildTarget(kind: .project, url: $0)
        } ?? buildTarget
    }

    static func command(target: XcodeBuildTarget, environment: [String: String]) -> ProcessCommand {
        ProcessCommand(
            "xcodebuild", ["-list", "-json"] + target.arguments,
            environment: environment,
            timeout: .seconds(120)
        )
    }

    static func decode(_ standardOutput: String) -> XcodeSchemeList? {
        try? JSONDecoder().decode(XcodeSchemeList.self, from: Data(standardOutput.utf8))
    }

    /// The single `ios/*.xcodeproj`. `Pods.xcodeproj` lives a directory deeper, so a
    /// shallow look finds the app's project and nothing else.
    ///
    /// - Returns: nil when there is no project, or more than one and therefore no
    ///   way to pick without guessing.
    static func project(inIOSDirectoryOf anchor: ProjectAnchor, fileManager: FileManager = .default) -> URL? {
        let ios = anchor.directory.appendingPathComponent("ios")
        // Listed by name rather than by URL: the URL-returning call hands back
        // paths resolved against the real file system, and the command line should
        // read as the path the project is actually rooted at.
        let names = (try? fileManager.contentsOfDirectory(atPath: ios.path)) ?? []
        return names.filter { $0.hasSuffix(".xcodeproj") }.only.map(ios.appendingPathComponent)
    }
}
