import Foundation
import TestSupport
import Testing

@testable import Core

/// The anchor is the project's single detection rule, so these scenarios are the
/// contract every project-scoped feature inherits.
@Suite("anchor detection")
struct ProjectAnchorTests {
    @Test("walks up from the working directory to the nearest package.json that has react-native")
    func findsAnchorAbove() throws {
        let repo = try FixtureRepo()
        try repo.write("app/package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.directory("app/src/screens")

        let anchor = try #require(ProjectAnchor.detect(from: repo.url("app/src/screens")))

        #expect(anchor.directory.path == repo.url("app").path)
        #expect(anchor.declaredReactNativeVersion == "0.76.5")
    }

    @Test("in a monorepo the nearest react-native package.json wins")
    func nearestPackageWins() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.70.0"}}"#)
        try repo.write("packages/app/package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let anchor = try #require(ProjectAnchor.detect(from: repo.url("packages/app")))

        #expect(anchor.directory.path == repo.url("packages/app").path)
        #expect(anchor.declaredReactNativeVersion == "0.76.5")
    }

    @Test("a package.json without react-native is not an anchor — the search keeps climbing")
    func skipsNonReactNativePackages() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("packages/tools/package.json", #"{"dependencies": {"typescript": "5.4.0"}}"#)

        let anchor = try #require(ProjectAnchor.detect(from: repo.url("packages/tools")))

        #expect(anchor.directory.path == repo.root.path)
    }

    @Test("no react-native anywhere above means no anchor — not an error")
    func noAnchor() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"typescript": "5.4.0"}}"#)

        #expect(ProjectAnchor.detect(from: repo.root) == nil)
    }

    @Test("the search stops at the git root")
    func stopsAtGitRoot() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.directory("checkout/.git")
        try repo.directory("checkout/src")

        #expect(ProjectAnchor.detect(from: repo.url("checkout/src")) == nil)
    }

    @Test("reads the installed react-native version, ios/ and node_modules from disk")
    func readsProjectFacts() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "^0.76.0"}}"#)
        try repo.write("node_modules/react-native/package.json", #"{"version": "0.76.5"}"#)
        try repo.directory("ios")

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.declaredReactNativeVersion == "^0.76.0")
        #expect(anchor.reactNativeVersion?.value == "0.76.5")
        #expect(anchor.reactNativeVersion?.origin == "node_modules/react-native")
        #expect(anchor.hasIOSDirectory)
        #expect(anchor.hasNodeModules)
    }

    @Test("a project with neither ios/ nor node_modules reports both as missing")
    func missingDirectories() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        // Nothing is installed, so the version cannot have been measured — it is the
        // declaration that answers here.
        #expect(anchor.reactNativeVersion?.origin == "package.json dependencies.react-native")
        #expect(anchor.hasIOSDirectory == false)
        #expect(anchor.hasNodeModules == false)
    }

    @Test("reads the Tier 1 declarations: node pin, engines and packageManager")
    func readsTier1Declarations() throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            """
            {
              "dependencies": {"react-native": "0.76.5"},
              "engines": {"node": ">=18"},
              "packageManager": "yarn@3.6.4+sha224.abcdef"
            }
            """
        )
        try repo.write(".nvmrc", "v20.11.1\n")

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.nodePin?.value == "v20.11.1")
        #expect(anchor.nodePin?.file == ".nvmrc")
        #expect(anchor.nodeEngines == [NodeEngines(range: ">=18")])
        // The corepack hash is not part of the version being compared.
        #expect(anchor.packageManager == PackageManagerRequirement(name: "yarn", version: "3.6.4"))
    }

    @Test("a .node-version file pins Node just like .nvmrc")
    func nodeVersionFileIsAPin() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".node-version", "20.11.1")

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.nodePin?.file == ".node-version")
    }

    @Test(".xcode-version is the project's own Xcode declaration")
    func xcodeVersionFile() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write(".xcode-version", "26.3\n")

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.declaredXcodeVersion == "26.3")
    }

    /// Absence is silence: a repo that never picked an Xcode has nothing to say,
    /// and neither has one that left the file empty.
    @Test("a missing or blank .xcode-version declares nothing")
    func noXcodeVersionFile() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        #expect(try #require(ProjectAnchor.detect(from: repo.root)).declaredXcodeVersion == nil)

        try repo.write(".xcode-version", "\n")
        #expect(try #require(ProjectAnchor.detect(from: repo.root)).declaredXcodeVersion == nil)
    }

    @Test("the workspace root is the first lockfile above the anchor, and it names the package manager")
    func workspaceRootFromLockfile() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"workspaces": ["packages/*"]}"#)
        try repo.write("yarn.lock", "# yarn lockfile v1\n")
        try repo.write("packages/app/package.json", #"{"dependencies": {"react-native": "0.81.6"}}"#)

        let anchor = try #require(ProjectAnchor.detect(from: repo.url("packages/app")))
        let workspaceRoot = try #require(anchor.workspaceRoot)

        #expect(workspaceRoot.directory.path == repo.root.path)
        #expect(workspaceRoot.lockfile == "yarn.lock")
        #expect(workspaceRoot.packageManagerName == "yarn")
        // Copy-pasting `yarn install` from the sub-package is what breaks a
        // workspace: the install belongs where the lockfile is.
        #expect(anchor.installCommand == "cd \(repo.root.path) && yarn install")
    }

    /// In a single repo the anchor is the workspace root, and an install that already
    /// runs in the right place does not need to be told where to run.
    @Test("a lockfile beside the anchor makes the install command a plain one")
    func lockfileBesideTheAnchor() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.76.5"}}"#)
        try repo.write("pnpm-lock.yaml", "lockfileVersion: '9.0'\n")

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.workspaceRoot?.directory.path == repo.root.path)
        #expect(anchor.installCommand == "pnpm install")
    }

    /// `packageManager` is a workspace-wide contract: a sub-package that does not
    /// repeat it is still bound by it. Reading only the anchor made the Check vanish.
    @Test("packageManager is read from the workspace root when the anchor does not declare one")
    func workspaceRootPackageManager() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"packageManager": "yarn@4.16.0"}"#)
        try repo.write("yarn.lock", "")
        try repo.write("packages/app/package.json", #"{"dependencies": {"react-native": "0.81.6"}}"#)

        let anchor = try #require(ProjectAnchor.detect(from: repo.url("packages/app")))
        let requirement = try #require(anchor.packageManager)

        #expect(requirement.name == "yarn")
        #expect(requirement.version == "4.16.0")
        #expect(requirement.origin == "workspace root package.json packageManager")
    }

    @Test("unparsable package.json is not an anchor")
    func brokenManifest() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", "{ this is not json")

        #expect(ProjectAnchor.detect(from: repo.root) == nil)
    }

    /// mattermost-mobile's, byte for byte: a bare `pod install` in this repo dies on
    /// the New Architecture flag the script sets, so the declaration is the only way
    /// the Pods ever get installed (#48).
    @Test("a declared pod install script is run through the project's package manager")
    func declaredPodInstallScript() throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"""
            {
              "dependencies": {"react-native": "0.81.6"},
              "scripts": {"pod-install": "cd ios && RCT_NEW_ARCH_ENABLED=1 pod install"}
            }
            """#
        )
        try repo.write("yarn.lock", "")

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.podInstallScript == "pod-install")
        #expect(anchor.podInstallProcess.description == "yarn run pod-install")
        // At the anchor, not in `ios/`: the script does its own `cd`, and the
        // manager has to be run where the `package.json` declaring it is.
        #expect(anchor.podInstallProcess.workingDirectory?.path == repo.root.path)
        #expect(anchor.podInstallCommand == "cd \(repo.root.path) && yarn run pod-install")
    }

    /// A repo that declares nothing keeps the behaviour it had — the bare install in
    /// `ios/`, which is what two of the three dogfooding repos needed.
    @Test("no declared script leaves pod install bare, in ios/")
    func noPodInstallScript() throws {
        let repo = try FixtureRepo()
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.81.6"}}"#)

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.podInstallScript == nil)
        #expect(anchor.podInstallProcess.description == "pod install")
        #expect(anchor.podInstallProcess.workingDirectory?.path == repo.url("ios").path)
        #expect(anchor.podInstallCommand == "cd \(repo.url("ios").path) && pod install")
    }

    /// Both halves have to agree. joplin's root `postinstall` does run `pod install`,
    /// on its way through a dozen other things — running it as the Pods step would be
    /// running the whole install again.
    @Test("a script that installs Pods under an unconventional name is not the pod install")
    func podInstallScriptNeedsAConventionalName() throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"""
            {
              "dependencies": {"react-native": "0.81.6"},
              "scripts": {"postinstall": "npm run build && cd ios && pod install"}
            }
            """#
        )

        #expect(try #require(ProjectAnchor.detect(from: repo.root)).podInstallScript == nil)
    }

    /// And the other half: a conventional name whose body does something else is not
    /// evidence either. `pods` is a common name for a lint or a cleanup.
    @Test("a conventionally named script that does not run pod install is not the pod install")
    func podInstallScriptNeedsAPodInstall() throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"""
            {
              "dependencies": {"react-native": "0.81.6"},
              "scripts": {"pods": "rm -rf ios/Pods"}
            }
            """#
        )

        #expect(try #require(ProjectAnchor.detect(from: repo.root)).podInstallScript == nil)
    }

    /// `npx pod-install` is how a large share of React Native apps spell it — the npm
    /// package, not the CocoaPods binary. Reading only the two-word spelling would put
    /// those repos back on the bare command this whole chain exists to replace.
    @Test("a script that runs the pod-install package counts as a declared pod install")
    func podInstallScriptViaTheNPMPackage() throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"""
            {
              "dependencies": {"react-native": "0.81.6"},
              "scripts": {"pod-install": "npx pod-install ios"}
            }
            """#
        )

        #expect(try #require(ProjectAnchor.detect(from: repo.root)).podInstallScript == "pod-install")
    }

    /// A manifest holding several is read in one order, not whichever the JSON
    /// dictionary happens to hand back first — two runs picking different scripts is
    /// the same class of bug as two readers picking their own evidence.
    @Test("a manifest declaring several conventional names is read in a fixed order")
    func podInstallScriptOrder() throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"""
            {
              "dependencies": {"react-native": "0.81.6"},
              "scripts": {
                "pods": "cd ios && pod install",
                "install-pods": "bundle exec pod install",
                "pod-install": "cd ios && RCT_NEW_ARCH_ENABLED=1 pod install"
              }
            }
            """#
        )

        #expect(try #require(ProjectAnchor.detect(from: repo.root)).podInstallScript == "pod-install")
    }

    /// A pasted command has to carry what chose it (ADR-0003) — `yarn run pod-install`
    /// says less about itself than the `pod install` it replaced.
    @Test("the declared pod install names the declaration that picked it")
    func podInstallEvidence() throws {
        let repo = try FixtureRepo()
        try repo.write(
            "package.json",
            #"""
            {
              "dependencies": {"react-native": "0.81.6"},
              "scripts": {"pod-install": "cd ios && pod install"}
            }
            """#
        )
        try repo.write("yarn.lock", "")

        let anchor = try #require(ProjectAnchor.detect(from: repo.root))

        #expect(anchor.podInstallEvidence.contains("scripts.pod-install"))
        // Nothing declared, nothing to name: a default is not evidence.
        try repo.write("package.json", #"{"dependencies": {"react-native": "0.81.6"}}"#)
        #expect(try #require(ProjectAnchor.detect(from: repo.root)).podInstallEvidence.isEmpty)
    }
}
