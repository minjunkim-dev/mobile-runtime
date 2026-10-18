import Core
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Shape of `xcodebuild -list -json`. RN lists its shallow app project to exclude
/// Pod schemes. Native iOS preserves the selected container and filters shared schemes.
struct XcodeSchemeList: Decodable {
    private struct Container: Decodable {
        let schemes: [String]?
        let configurations: [String]?
    }

    private enum CodingKeys: String, CodingKey {
        case project
        case workspace
    }

    let schemes: [String]
    let configurations: [String]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let listing = try container.decodeIfPresent(Container.self, forKey: .project)
            ?? container.decode(Container.self, forKey: .workspace)
        schemes = listing.schemes ?? []
        configurations = listing.configurations ?? []
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
        if anchor.framework == .nativeIOS { return buildTarget }
        return project(inIOSDirectoryOf: anchor, fileManager: fileManager).map {
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

    /// Xcode's listing can include a user's unshared schemes. Native projects
    /// expose only shared schemes beside the selected container or its members.
    func schemes(in target: XcodeBuildTarget, anchor: ProjectAnchor) -> [String] {
        guard anchor.framework == .nativeIOS else { return schemes }
        let shared = Set(Self.sharedSchemes(in: target).map { $0.deletingPathExtension().lastPathComponent })
        return schemes.filter { shared.contains($0) }
    }

    static func sharedSchemes(in target: XcodeBuildTarget) -> [URL] {
        var containers = [target.url]
        if target.kind == .workspace,
           let data = try? Data(contentsOf: target.url.appendingPathComponent("contents.xcworkspacedata")) {
            let references = WorkspaceReferences(root: target.url.deletingLastPathComponent())
            let parser = XMLParser(data: data)
            parser.delegate = references
            if parser.parse() {
                containers += references.projects
            }
        }
        return containers.flatMap { container in
            let directory = container.appendingPathComponent("xcshareddata/xcschemes")
            return ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter { $0.hasSuffix(".xcscheme") }.map(directory.appendingPathComponent)
        }
    }

    static func runnable(scheme: String, in target: XcodeBuildTarget) -> [String: String]? {
        guard let file = sharedSchemes(in: target).filter({ $0.deletingPathExtension().lastPathComponent == scheme }).only,
            let data = try? Data(contentsOf: file) else { return nil }
        let runnable = SchemeRunnable()
        let parser = XMLParser(data: data)
        parser.delegate = runnable
        guard parser.parse() else { return nil }
        return runnable.references.only
    }

    /// The single `ios/*.xcodeproj`. `Pods.xcodeproj` lives a directory deeper, so a
    /// shallow look finds the app's project and nothing else.
    ///
    /// - Returns: nil when there is no project, or more than one and therefore no
    ///   way to pick without guessing.
    static func project(inIOSDirectoryOf anchor: ProjectAnchor, fileManager: FileManager = .default) -> URL? {
        let ios = anchor.iosDirectory
        // Listed by name rather than by URL: the URL-returning call hands back
        // paths resolved against the real file system, and the command line should
        // read as the path the project is actually rooted at.
        let names = (try? fileManager.contentsOfDirectory(atPath: ios.path)) ?? []
        return names.filter { $0.hasSuffix(".xcodeproj") }.only.map(ios.appendingPathComponent)
    }
}

private final class SchemeRunnable: NSObject, XMLParserDelegate {
    var elements: [String] = []
    var references: [[String: String]] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "BuildableReference", elements.suffix(2) == ["LaunchAction", "BuildableProductRunnable"] {
            references.append(attributes)
        }
        elements.append(elementName)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        elements.removeLast()
    }
}

private final class WorkspaceReferences: NSObject, XMLParserDelegate {
    let root: URL
    var groups: [URL]
    var projects: [URL] = []

    init(root: URL) {
        self.root = root
        self.groups = [root]
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        guard let location = attributes["location"], let url = resolve(location) else {
            if elementName == "Group" { groups.append(groups.last ?? root) }
            return
        }
        if elementName == "Group" { groups.append(url) }
        else if elementName == "FileRef", url.pathExtension == "xcodeproj" { projects.append(url) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Group", groups.count > 1 { groups.removeLast() }
    }

    private func resolve(_ location: String) -> URL? {
        if location.hasPrefix("group:") { return (groups.last ?? root).appendingPathComponent(String(location.dropFirst(6))) }
        if location.hasPrefix("container:") { return root.appendingPathComponent(String(location.dropFirst(10))) }
        if location.hasPrefix("absolute:") { return URL(fileURLWithPath: String(location.dropFirst(9))) }
        return nil
    }
}
