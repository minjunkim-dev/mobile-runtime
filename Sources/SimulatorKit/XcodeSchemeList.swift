import Core
import Foundation

/// Shape of `xcodebuild -list -json`. The Xcode **project** is listed rather than
/// the workspace: a workspace's scheme list carries every Pod, which would turn
/// "which scheme should I build" into a hundred wrong answers.
struct XcodeSchemeList: Decodable {
    struct Project: Decodable {
        let schemes: [String]?
    }

    let project: Project

    static func command(project: URL, environment: [String: String]) -> ProcessCommand {
        ProcessCommand(
            "xcodebuild", ["-list", "-json", "-project", project.path],
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
        let projects = names.filter { $0.hasSuffix(".xcodeproj") }
        return projects.count == 1 ? ios.appendingPathComponent(projects[0]) : nil
    }
}
