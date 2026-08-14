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

    public init(
        anchor: ProjectAnchor?,
        file: URL?,
        misspelledFile: URL?,
        strayFile: URL?,
        parse: MobileConfigParse?
    ) {
        self.anchor = anchor
        self.file = file
        self.misspelledFile = misspelledFile
        self.strayFile = strayFile
        self.parse = parse
    }

    public var anchorDirectory: URL? { anchor?.directory }

    /// The declarations to act on. nil when there is no file, and nil when the file
    /// did not parse — a broken file never degrades into a partial configuration.
    public var configuration: MobileConfig? {
        guard case .parsed(let config, _) = parse else { return nil }
        return config
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
