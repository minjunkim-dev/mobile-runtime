import Foundation

/// A Node version pinned by team convention (`.nvmrc`, `.node-version`). Breaking
/// a pin is a warning; `engines` is the contract that errors.
public struct NodePin: Sendable, Equatable {
    public let value: String
    public let file: String

    public init(value: String, file: String) {
        self.value = value
        self.file = file
    }
}

/// How a verdict spells where a declaration was read. The anchor's `package.json`
/// and the workspace root's must never read alike: the source string is the only
/// record of what a judgement believed (ADR-0003), and in a monorepo the two files
/// disagree on purpose. One spelling, in one place, so they cannot drift apart.
public enum DeclarationOrigin {
    public static func anchor(_ field: String) -> String { "package.json \(field)" }
    public static func workspaceRoot(_ field: String) -> String { "workspace root package.json \(field)" }
}

/// The `packageManager` field, split into the two halves that get compared. The
/// corepack hash suffix is dropped — it is integrity data, not a version.
public struct PackageManagerRequirement: Sendable, Equatable {
    public let name: String
    public let version: String
    /// Which `package.json` declared it — the anchor's or the workspace root's.
    public let origin: String

    public init(name: String, version: String, origin: String = DeclarationOrigin.anchor("packageManager")) {
        self.name = name
        self.version = version
        self.origin = origin
    }
}

/// One `engines.node` declaration and the `package.json` it came from. A workspace
/// member carries two of these — its own and its root's — and each is a floor it has
/// to clear, so a verdict quotes whichever ones the installed Node actually broke.
public struct NodeEngines: Sendable, Equatable {
    public let range: String
    public let origin: String

    public init(range: String, origin: String = DeclarationOrigin.anchor("engines")) {
        self.range = range
        self.origin = origin
    }

    /// How a verdict names the requirement: the range, then where it was declared.
    public var described: String { "\(range) (\(origin))" }
}

/// The workspace root: the first lockfile at or above the anchor. A lockfile is a
/// measurement — it is where an install actually happened — so it answers both
/// "which package manager" and "where does install run", which is what a sub-package
/// of a monorepo cannot answer on its own. The `workspaces` field is deliberately not
/// parsed: npm, yarn and pnpm write it in different places, and the lockfile is the
/// same signal for all three. See ADR-0003.
///
/// In a single repo this is the anchor's own directory — a repo does not have to be a
/// monorepo to have a workspace root.
public struct WorkspaceRoot: Sendable, Equatable {
    /// The directory holding the lockfile.
    public let directory: URL
    /// The lockfile that named it — the evidence behind `installCommand`, so a
    /// remediation can say what picked the command it is asking a human to paste.
    public let lockfile: String
    /// The manager that lockfile belongs to.
    public let packageManagerName: String

    public init(directory: URL, lockfile: String, packageManagerName: String) {
        self.directory = directory
        self.lockfile = lockfile
        self.packageManagerName = packageManagerName
    }

    /// What a human would run to install the project's dependencies, from the two
    /// things the lockfile knows: its kind picks the manager, its directory picks
    /// where the install runs. Running an install from a sub-package is how a
    /// workspace gets broken, so the `cd` is part of the command whenever the anchor
    /// is somewhere else.
    public func installCommand(from anchor: URL) -> String {
        let install = installProcess.description
        return directory == anchor ? install : "cd \(directory.path) && \(install)"
    }

    /// The same install, as something to run rather than something to print. The `cd`
    /// above and this working directory are one decision written once — the line
    /// doctor hands a human and the command `up` executes must not be able to drift.
    ///
    /// No timeout: a cold install is minutes of network, and 30 seconds would kill it.
    public var installProcess: ProcessCommand {
        ProcessCommand(packageManagerName, ["install"], workingDirectory: directory, timeout: nil)
    }
}

/// The project's anchor: the nearest `package.json` that depends on react-native,
/// plus the Tier 1 declarations sitting next to it. Detection happens once and
/// everything project-scoped — the checks here, `mobile.yml` later — reads the
/// same anchor. There is exactly one detection rule in this project.
public struct ProjectAnchor: Sendable, Equatable {
    /// The directory holding the anchoring `package.json`.
    public let directory: URL
    /// From `dependencies.react-native` — a declared range, not a measurement.
    public let declaredReactNativeVersion: String
    /// The version every judgement about this project runs on, picked along the
    /// evidence chain and carrying which link answered. nil when none of them did —
    /// then, and only then, Tier 2 is `unknown`. There is one resolved version per
    /// anchor for the same reason there is one detection rule: two readers picking
    /// their own evidence is how a single run starts contradicting itself.
    public let reactNativeVersion: ReactNativeVersion?
    public let hasIOSDirectory: Bool
    public let hasNodeModules: Bool
    public let nodePin: NodePin?
    /// Every `engines.node` that binds this project, anchor first. Empty when nobody
    /// declared one — that is silence, not a range that everything satisfies.
    public let nodeEngines: [NodeEngines]
    public let packageManager: PackageManagerRequirement?
    /// nil when the project manages no gems — then there is no CocoaPods Check.
    public let cocoapods: CocoaPodsRequirement?
    /// From `.ruby-version`. nil means no Ruby Check — absence, not `unknown`.
    public let rubyPin: String?
    /// From `.xcode-version`, the file xcodes and fastlane already read. Tier 1
    /// evidence for a requirement the matrix only knows a framework floor for;
    /// nil is silence, not a missing answer.
    public let declaredXcodeVersion: String?
    /// The lowest iOS this app runs on, read from the iOS project. The same kind of
    /// evidence as `declaredXcodeVersion` for the other Tier 2 requirement.
    public let deploymentTarget: DeploymentTarget?
    /// nil when no lockfile sits at or above the anchor — nothing has ever been
    /// installed from this tree, so there is no measured manager to name.
    public let workspaceRoot: WorkspaceRoot?
    /// The name of the `package.json` script the project declared for installing its
    /// Pods, when it declared one. nil is silence, and silence means the bare
    /// `pod install` is all anybody said to run.
    public let podInstallScript: String?

    /// What a human would run to install the project's dependencies. doctor prints
    /// it and never runs it.
    ///
    /// The lockfile answers this when there is one. Without it there is nothing
    /// measured to go on, so the declaration is the next best evidence and npm the
    /// last resort — a guess, but the one a repo that declared nothing behaves like.
    public var installCommand: String {
        workspaceRoot?.installCommand(from: directory) ?? installProcess.description
    }

    /// The manager this project is run with — the one its lockfile named, else the one
    /// it declared, else npm. `dependencies` installs with it and `metro` calls the
    /// project's start script with it, off one answer.
    public var packageManagerName: String { installProcess.executable }

    /// What `up` runs where `installCommand` is what doctor prints. Same evidence and
    /// same fallback, so the two can never name different managers.
    public var installProcess: ProcessCommand {
        workspaceRoot?.installProcess
            ?? ProcessCommand(
                packageManager?.name ?? "npm", ["install"],
                workingDirectory: directory, timeout: nil
            )
    }

    /// What `up` runs to install the Pods. The project's own script when it declared
    /// one, else the bare `pod install` in `ios/`.
    ///
    /// A repo that declares the install declares it for a reason: mattermost-mobile's
    /// script sets `RCT_NEW_ARCH_ENABLED=1`, without which its `Podfile` refuses to
    /// evaluate — so a bare `pod install` there does not install slightly differently,
    /// it never installs at all (#48). The script is run through the manager rather
    /// than unpacked and re-run, because what it does is the project's business.
    ///
    /// The working directory follows the same logic: a declared script runs where the
    /// `package.json` that declares it is (`cd ios` is usually the script's own first
    /// word), a bare `pod install` runs where the `Podfile` is.
    ///
    /// No timeout, for the reason a Node install has none: a cold pod install is
    /// minutes of network, and it was measured at eleven.
    public var podInstallProcess: ProcessCommand {
        guard let podInstallScript else {
            return ProcessCommand(
                "pod", ["install"],
                workingDirectory: directory.appendingPathComponent("ios"), timeout: nil
            )
        }
        return ProcessCommand(
            packageManagerName, ["run", podInstallScript],
            workingDirectory: directory, timeout: nil
        )
    }

    /// The same install as a line to paste. One decision written once, like
    /// `installCommand` and `installProcess` — a remediation that hands over a command
    /// `up` did not run is the failure this ticket started as.
    ///
    /// Always with the `cd`: unlike the Node install, neither destination is where a
    /// human is standing when they read the failure.
    public var podInstallCommand: String {
        let process = podInstallProcess
        return "cd \((process.workingDirectory ?? directory).path) && \(process.description)"
    }

    /// What `up` runs to install the gems this project declared. nil when it declared
    /// none — `cocoapods` is non-nil exactly when a `Gemfile` or a `Gemfile.lock` sits
    /// at the anchor, which is the same question asked once.
    ///
    /// A declared pod install usually goes through `bundle exec`, and bundler refuses
    /// to run anything at all until every gem in the lock is present — so on a fresh
    /// clone the pod install cannot start (#59). The gems are the project's own
    /// dependencies by the same test `node_modules` and `Pods` pass: gitignored,
    /// reinstallable, and already described by a lockfile the project committed.
    public var gemInstallProcess: ProcessCommand? {
        guard cocoapods != nil else { return nil }
        // No timeout, for the reason the other two installs have none: it is minutes
        // of network on a cold machine.
        return ProcessCommand("bundle", ["install"], workingDirectory: directory, timeout: nil)
    }

    /// The same install as a line to paste — always with the `cd`, like the pod one.
    public var gemInstallCommand: String? {
        gemInstallProcess.map { "cd \(($0.workingDirectory ?? directory).path) && \($0.description)" }
    }

    /// Why this command and not another one. A pasted `yarn run pod-install` says less
    /// about itself than the `pod install` it replaced, so the line that hands it over
    /// carries the declaration that chose it (ADR-0003) — the same duty
    /// `ProjectDetectedCheck` pays for the Node install with the lockfile's name.
    ///
    /// Empty when nothing was declared: there is no evidence to name, only a default.
    public var podInstallEvidence: String {
        guard let podInstallScript else { return "" }
        return " `package.json` `scripts.\(podInstallScript)` is what picks it."
    }

    /// The Project checks this anchor can answer. A Check that needs a declaration
    /// to compare against is absent when the declaration is — a project that never
    /// pinned Ruby gets no Ruby line at all, rather than a permanent `unknown`.
    public func checks(runner: any ProcessRunner) -> [any Check] {
        var checks: [any Check] = [
            ProjectDetectedCheck(anchor: self),
            NodeVersionCheck(anchor: self, runner: runner),
        ]
        if let packageManager {
            checks.append(PackageManagerVersionCheck(requirement: packageManager, runner: runner))
        }
        if let cocoapods {
            checks.append(CocoaPodsVersionCheck(requirement: cocoapods, runner: runner))
        }
        if let rubyPin {
            checks.append(RubyVersionCheck(pin: rubyPin, runner: runner))
        }
        return checks
    }

    /// Walks up from `directory` looking for the anchor, stopping at the git root
    /// (or the filesystem root). The nearest react-native `package.json` wins, so a
    /// monorepo naturally judges the app you are standing in.
    ///
    /// - Returns: nil when there is no React Native project above the starting
    ///   point. That is not an error — it means host checks only.
    public static func detect(from directory: URL, fileManager: FileManager = .default) -> ProjectAnchor? {
        walkUp(from: directory.resolvingSymlinksInPath().path, fileManager: fileManager) {
            read(at: $0, fileManager: fileManager)
        }
    }

    /// Climbs from `directory` until `probe` answers, stopping at the git root or the
    /// filesystem root. Both upward searches in this file — the anchor and the
    /// workspace root — share it, so they cannot drift into different ideas of how
    /// far up a project reaches.
    private static func walkUp<Found>(
        from directory: String, fileManager: FileManager, probe: (String) -> Found?
    ) -> Found? {
        var current = directory
        while true {
            if let found = probe(current) { return found }
            // Above the git root is somebody else's project.
            if fileManager.fileExists(atPath: current.appending("/.git")) { return nil }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { return nil }
            current = parent
        }
    }

    private static let pinFiles = [".nvmrc", ".node-version"]

    private static func read(at directory: String, fileManager: FileManager) -> ProjectAnchor? {
        guard let manifest = manifest(in: directory, fileManager: fileManager),
            let declared = (manifest["dependencies"] as? [String: Any])?["react-native"] as? String
        else { return nil }

        let workspaceRoot = workspaceRoot(from: directory, fileManager: fileManager)
        // Only when the root is somewhere else: otherwise it is this same manifest,
        // and a declaration would be counted twice.
        let root = workspaceRoot.flatMap {
            $0.directory.path == directory ? nil : Self.manifest(in: $0.directory.path, fileManager: fileManager)
        }

        return ProjectAnchor(
            directory: URL(fileURLWithPath: directory),
            declaredReactNativeVersion: declared,
            reactNativeVersion: ReactNativeVersion.resolve(
                anchorDirectory: directory,
                declared: declared,
                installed: installedReactNative(in: directory, fileManager: fileManager),
                workspaceRoot: workspaceRoot,
                fileManager: fileManager
            ),
            hasIOSDirectory: isDirectory(directory.appending("/ios"), fileManager),
            hasNodeModules: isDirectory(directory.appending("/node_modules"), fileManager),
            nodePin: pin(in: directory, fileManager: fileManager),
            nodeEngines: nodeEngines(anchor: manifest, root: root),
            packageManager: packageManagerRequirement(anchor: manifest, root: root),
            cocoapods: CocoaPodsRequirement.resolve(
                anchorDirectory: directory, fileManager: fileManager
            ),
            rubyPin: rubyPin(in: directory, fileManager: fileManager),
            declaredXcodeVersion: declaration(
                at: directory.appending("/\(xcodeVersionFile)"), fileManager: fileManager
            ),
            deploymentTarget: DeploymentTarget.resolve(
                anchorDirectory: directory, fileManager: fileManager
            ),
            workspaceRoot: workspaceRoot,
            podInstallScript: podInstallScript(in: manifest)
        )
    }

    /// Names the ecosystem actually uses for "install the Pods", in the order a
    /// manifest holding several is read.
    private static let podInstallScriptNames = [
        "pod-install", "pods-install", "install-pods", "install:pods", "pod:install", "pods",
    ]

    /// The declared pod install, read from the anchor's `scripts`. Both halves have to
    /// agree — a conventional name **and** a body that runs `pod install`.
    ///
    /// Either half alone misreads one of the three dogfooding repos. On the name
    /// alone, a `pods` script that cleans or lints gets run as an install. On the body
    /// alone, joplin's root `postinstall` matches — it does run `pod install`, on its
    /// way through a dozen other things, and running it as the Pods step would run the
    /// whole install a second time.
    ///
    /// Only the anchor's manifest: the `ios/` directory belongs to the anchor, and a
    /// workspace root's script would be some other package's install.
    ///
    /// `pod-install` counts as a body too — the npm package of that name is how a
    /// large share of React Native apps spell the install (`npx pod-install`), and
    /// missing it would put those repos back on the bare command this ticket exists
    /// to stop.
    private static func podInstallScript(in manifest: [String: Any]) -> String? {
        guard let scripts = manifest["scripts"] as? [String: Any] else { return nil }
        return podInstallScriptNames.first {
            guard let body = scripts[$0] as? String else { return false }
            return body.contains("pod install") || body.contains("pod-install")
        }
    }

    private static func manifest(in directory: String, fileManager: FileManager) -> [String: Any]? {
        guard let data = fileManager.contents(atPath: directory.appending("/package.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Both are kept: `engines` is a floor each `package.json` sets for itself, and a
    /// workspace member has to clear its root's as well as its own.
    private static func nodeEngines(anchor: [String: Any], root: [String: Any]?) -> [NodeEngines] {
        func declared(_ manifest: [String: Any]?) -> String? {
            (manifest?["engines"] as? [String: Any])?["node"] as? String
        }
        return [
            declared(anchor).map { NodeEngines(range: $0) },
            declared(root).map { NodeEngines(range: $0, origin: DeclarationOrigin.workspaceRoot("engines")) },
        ].compactMap { $0 }
    }

    /// The workspace root wins: `packageManager` is a contract over the whole
    /// workspace, and a sub-package that stays silent has not opted out of it.
    private static func packageManagerRequirement(
        anchor: [String: Any], root: [String: Any]?
    ) -> PackageManagerRequirement? {
        if let field = root?["packageManager"] as? String,
            let requirement = packageManager(field, origin: DeclarationOrigin.workspaceRoot("packageManager"))
        {
            return requirement
        }
        return (anchor["packageManager"] as? String).flatMap { packageManager($0) }
    }

    /// Lockfile → manager, in the order a directory holding several is read. Two
    /// lockfiles side by side is already a broken repo; picking one deterministically
    /// beats guessing from a declaration that may itself be the thing that is wrong.
    private static let lockfiles: KeyValuePairs<String, String> = [
        "yarn.lock": "yarn",
        "package-lock.json": "npm",
        "pnpm-lock.yaml": "pnpm",
        "bun.lock": "bun",
        "bun.lockb": "bun",
    ]

    /// Walks up from the anchor to the first directory holding a lockfile. The
    /// anchor's own directory counts first — in a single repo the workspace root and
    /// the anchor are the same place.
    private static func workspaceRoot(from anchor: String, fileManager: FileManager) -> WorkspaceRoot? {
        walkUp(from: anchor, fileManager: fileManager) { directory in
            lockfiles.first { fileManager.fileExists(atPath: directory.appending("/\($0.key)")) }
                .map {
                    WorkspaceRoot(
                        directory: URL(fileURLWithPath: directory),
                        lockfile: $0.key,
                        packageManagerName: $0.value
                    )
                }
        }
    }

    /// Named here because the origin string in a verdict has to quote it back.
    public static let xcodeVersionFile = ".xcode-version"

    /// A one-line declaration file — `.nvmrc`, `.ruby-version`, `.xcode-version`.
    /// A blank file declares nothing, the same as no file at all.
    private static func declaration(at path: String, fileManager: FileManager) -> String? {
        guard let data = fileManager.contents(atPath: path) else { return nil }
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// RVM writes `ruby-3.2.2` where rbenv writes `3.2.2` — the prefix is the version
    /// manager's, not part of the version.
    private static func rubyPin(in directory: String, fileManager: FileManager) -> String? {
        guard let value = declaration(at: directory.appending("/.ruby-version"), fileManager: fileManager)
        else { return nil }
        return value.hasPrefix("ruby-") ? String(value.dropFirst(5)) : value
    }

    private static func installedReactNative(in directory: String, fileManager: FileManager) -> String? {
        guard
            let data = fileManager.contents(
                atPath: directory.appending("/node_modules/react-native/package.json")
            ),
            let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return manifest["version"] as? String
    }

    private static func pin(in directory: String, fileManager: FileManager) -> NodePin? {
        for file in pinFiles {
            guard let value = declaration(at: directory.appending("/\(file)"), fileManager: fileManager)
            else { continue }
            return NodePin(value: value, file: file)
        }
        return nil
    }

    /// `yarn@3.6.4+sha224.…` → yarn 3.6.4.
    private static func packageManager(
        _ field: String, origin: String = DeclarationOrigin.anchor("packageManager")
    ) -> PackageManagerRequirement? {
        let parts = field.split(separator: "@", maxSplits: 1)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let version = parts[1].split(separator: "+", maxSplits: 1)[0]
        guard !version.isEmpty else { return nil }
        return PackageManagerRequirement(name: String(parts[0]), version: String(version), origin: origin)
    }

    private static func isDirectory(_ path: String, _ fileManager: FileManager) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }
}
