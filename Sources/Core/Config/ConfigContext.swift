import Foundation

/// Everything the two `config.*` Checks need to know about mobile.yml, resolved
/// once. Discovery shares the anchor with adapter activation — there is exactly
/// one detection rule in this project — and looks **only** beside it: no upward
/// search, no repo-root fallback. A file mobile would silently never read is
/// reported rather than ignored.
public struct ConfigContext: Sendable {
    /// nil outside a React Native project.
    public let anchor: ProjectAnchor?
    /// `<anchor>/mobile.yml`, the one location and the one filename.
    public let file: URL?
    /// `<anchor>/mobile.yaml` — found so it can be named, never read.
    public let misspelledFile: URL?
    /// A correctly-named file sitting where mobile never looks.
    public let strayFile: URL?
    /// nil when there is no `file` to read.
    public let parse: MobileConfigParse?

    /// Where the command was run. Paths in a verdict are written relative to it when
    /// they sit underneath — a pasteable line should not carry the reader's whole home
    /// directory (#35).
    public let workingDirectory: URL

    public init(
        anchor: ProjectAnchor?,
        workingDirectory: URL,
        file: URL?,
        misspelledFile: URL?,
        strayFile: URL?,
        parse: MobileConfigParse?
    ) {
        self.anchor = anchor
        self.workingDirectory = workingDirectory
        self.file = file
        self.misspelledFile = misspelledFile
        self.strayFile = strayFile
        self.parse = parse
    }

    public var anchorDirectory: URL? { anchor?.directory }

    /// How a verdict spells a path: relative to where the command was run when it is
    /// under it, absolute otherwise. A `cd` to the workspace root is above the working
    /// directory, and a line that gets pasted somewhere else has to keep pointing at
    /// the same place.
    public func display(_ url: URL) -> String {
        let base = workingDirectory.path
        let path = url.resolvingSymlinksInPath().path
        if path == base { return "." }
        guard path.hasPrefix(base + "/") else { return url.path }
        return String(path.dropFirst(base.count + 1))
    }

    /// The declarations to act on. nil when there is no file, and nil when the file
    /// did not parse — a broken file never degrades into a partial configuration.
    public var configuration: MobileConfig? {
        guard case .parsed(let config, _) = parse else { return nil }
        return config
    }

    public func selecting(scheme: String? = nil, module: String? = nil, variant: String? = nil,
                          avd: String? = nil, clearDevice: Bool = false) -> ConfigContext {
        if case .invalid = parse { return self }
        let previous = configuration ?? MobileConfig()
        let unknownKeys: [String]
        if case .parsed(_, let keys) = parse { unknownKeys = keys } else { unknownKeys = [] }
        let selected = MobileConfig(device: clearDevice ? nil : previous.device, scheme: scheme ?? previous.scheme,
                                    xcode: previous.xcode, iosRuntime: previous.iosRuntime,
                                    androidModule: module ?? previous.androidModule,
                                    androidVariant: variant ?? previous.androidVariant,
                                    androidLauncherActivity: previous.androidLauncherActivity,
                                    androidAVD: avd ?? previous.androidAVD)
        return ConfigContext(anchor: anchor, workingDirectory: workingDirectory, file: file,
                             misspelledFile: misspelledFile, strayFile: strayFile,
                             parse: .parsed(selected, unknownKeys: unknownKeys))
    }

    /// The Check exists only when a file does. A project with no mobile.yml gets no
    /// mobile.yml line — zero-config means zero noise.
    public func checks() -> [any Check] {
        file == nil && misspelledFile == nil ? [] : [ConfigSyntaxCheck(context: self)]
    }

    public static func detect(
        anchor: ProjectAnchor?,
        workingDirectory: URL,
        fileManager: FileManager = .default
    ) -> ConfigContext {
        let anchorDirectory = anchor?.directory
        let file = anchorDirectory.flatMap { existing($0, MobileConfig.fileName, fileManager) }
        let misspelled = anchorDirectory.flatMap {
            existing($0, MobileConfig.misspelledFileName, fileManager)
        }

        // Standing inside the anchor, the anchor's own file is the file — not a stray.
        let working = workingDirectory.resolvingSymlinksInPath()
        let stray: URL? =
            working.path == anchorDirectory?.resolvingSymlinksInPath().path
            ? nil
            : existing(working, MobileConfig.fileName, fileManager)
                ?? existing(working, MobileConfig.misspelledFileName, fileManager)

        return ConfigContext(
            anchor: anchor,
            workingDirectory: working,
            file: file,
            misspelledFile: misspelled,
            strayFile: stray,
            parse: file.map { url in
                guard let data = fileManager.contents(atPath: url.path) else {
                    return .invalid("\(MobileConfig.fileName) could not be read")
                }
                return MobileConfig.parse(String(decoding: data, as: UTF8.self))
            }
        )
    }

    private static func existing(_ directory: URL, _ name: String, _ fileManager: FileManager) -> URL? {
        let url = directory.appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
}
