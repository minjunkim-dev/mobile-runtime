import Core

/// Which scheme a build uses, decided in one place. `config.values` asks whether the
/// project's schemes leave a choice to be made and `build` asks which one to hand
/// xcodebuild — the same question, and a second copy of the rule would let doctor
/// approve a scheme that up then refuses to build.
///
/// The grades differ and that is deliberate: an unpicked scheme is a `warning` for
/// doctor (nobody has chosen yet, the machine is fine — ADR-0004) and an error for
/// `up`, which cannot build without choosing. The wording is what they share.
struct SchemeSelector {
    /// Why nothing was chosen.
    enum Miss: Error, Equatable {
        /// mobile.yml names a scheme this project does not define.
        case noSchemeNamed(String, available: [String])
        /// Several schemes and nothing declaring which. App extensions make this the
        /// norm, so it is a question to answer rather than a project that is broken.
        case undecided([String])

        /// What was looked for and not found. Both callers report this verbatim.
        var observed: String {
            switch self {
            case .noSchemeNamed(let declared, let available):
                "no scheme named \(declared) — this project has \(available.joined(separator: ", "))"
            case .undecided(let schemes):
                "\(schemes.count) schemes — \(schemes.joined(separator: ", ")) — "
                    + "and nothing declares which one to build"
            }
        }

        /// - Parameters:
        ///   - configFile: where mobile.yml goes, spelled the way the caller spells paths.
        ///   - target: the app project when one is shallowly available, otherwise
        ///     the selected workspace.
        func remediation(
            configFile: String,
            target: String,
            kind: XcodeBuildTarget.Kind
        ) -> Remediation {
            let list = "xcodebuild -list \(kind.rawValue) \(target)"
            switch self {
            case .noSchemeNamed:
                return Remediation(summary: "Set ios.scheme to one of them.", command: list)
            case .undecided(let schemes):
                let projectName = target.split(separator: "/").last.flatMap { component -> String? in
                    guard component.hasSuffix(".xcodeproj") else { return nil }
                    return String(component.dropLast(".xcodeproj".count))
                }
                guard let projectName, schemes.contains(projectName) else {
                    return Remediation(
                        summary: "Declare ios.scheme in \(configFile) after reviewing the listed schemes.",
                        command: list
                    )
                }
                return Remediation(
                    summary: "Declare the scheme in \(configFile): "
                        + "`ios:` on one line, `  scheme: \(projectName)` on the next.",
                    command: list
                )
            }
        }
    }

    private let schemes: [String]

    init(schemes: [String]) {
        self.schemes = schemes
    }

    /// mobile.yml's scheme, then the only one there is. Never a guess between several
    /// — picking one of a project's schemes for the developer is how a tool builds
    /// the tvOS target for eight minutes and says nothing about it.
    func resolve(declared: String?) -> Result<String, Miss> {
        guard let declared else {
            guard schemes.count == 1 else { return .failure(.undecided(schemes)) }
            return .success(schemes[0])
        }
        guard schemes.contains(declared) else {
            return .failure(.noSchemeNamed(declared, available: schemes))
        }
        return .success(declared)
    }
}
