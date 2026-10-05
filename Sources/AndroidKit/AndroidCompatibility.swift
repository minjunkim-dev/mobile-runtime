import Core
import Foundation

struct AndroidCompatibilityEvaluation: Sendable, Equatable {
    let required: [String]
    let violations: [String]
    let unknown: [String]
}

enum AndroidCompatibility {
    static let source = CheckSource(
        tier: 2,
        origin: "Android AGP compatibility table + Gradle Java compatibility table (2026-08-20)"
    )

    static func evaluate(
        wrapper: AndroidGradleWrapper,
        model: AndroidGradleModel,
        module: AndroidGradleModel.Module,
        compileSDK: String?
    ) -> AndroidCompatibilityEvaluation {
        var required: [String] = []
        var violations: [String] = []
        var unknown: [String] = []

        guard let agpText = module.agpVersion, let agp = SemanticVersion(agpText) else {
            return AndroidCompatibilityEvaluation(
                required: [], violations: [], unknown: ["the evaluated application plugin did not report an exact AGP version"]
            )
        }
        guard let gradle = SemanticVersion(model.gradleVersion) else {
            return AndroidCompatibilityEvaluation(
                required: [], violations: [], unknown: ["Gradle did not report an exact version"]
            )
        }
        guard gradle == wrapper.version else {
            return AndroidCompatibilityEvaluation(
                required: ["Gradle \(wrapper.versionText) from the wrapper"],
                violations: ["the wrapper declares \(wrapper.versionText), but the evaluated build ran Gradle \(model.gradleVersion)"],
                unknown: []
            )
        }

        if let minimum = minimumGradle(for: agp) {
            required.append("Gradle >= \(minimum.description) for AGP \(agpText)")
            if gradle < minimum {
                violations.append("AGP \(agpText) requires Gradle \(minimum.description) or newer, found \(model.gradleVersion)")
            }
        } else {
            unknown.append("no bundled AGP-to-Gradle row matches AGP \(agpText)")
        }

        guard let daemonJava = SemanticVersion(java: model.daemonJavaVersion) else {
            unknown.append("the Gradle daemon did not report a parseable JDK version")
            return AndroidCompatibilityEvaluation(required: required, violations: violations, unknown: unknown)
        }
        if let agpJDK = minimumJDK(for: agp) {
            required.append("daemon JDK >= \(agpJDK) for AGP \(agpText)")
            if daemonJava.major < agpJDK {
                violations.append("AGP \(agpText) requires JDK \(agpJDK) or newer, found \(model.daemonJavaVersion)")
            }
        } else {
            unknown.append("no bundled AGP-to-JDK row matches AGP \(agpText)")
        }

        switch minimumGradleForJava(daemonJava.major) {
        case .some(let minimum):
            required.append("Gradle >= \(minimum.description) to run on JDK \(daemonJava.major)")
            if gradle < minimum {
                violations.append("JDK \(daemonJava.major) requires Gradle \(minimum.description) or newer, found \(model.gradleVersion)")
            }
            if daemonJava.major <= 16, gradle >= SemanticVersion(major: 9) {
                violations.append("Gradle 9 and newer cannot run its daemon on JDK \(daemonJava.major)")
            }
        case .none:
            unknown.append("the bundled Gradle Java table has no row for JDK \(daemonJava.major)")
        }

        if let compileSDK, let compileSDKLevel = apiLevel(compileSDK),
            let minimum = minimumAGP(for: compileSDKLevel)
        {
            required.append("AGP >= \(minimum.description) for compileSdk \(compileSDK)")
            if agp < minimum {
                violations.append("compileSdk \(compileSDK) requires AGP \(minimum.description) or newer, found \(agpText)")
            }
        } else if let compileSDK {
            unknown.append("the bundled API-level table has no row for compileSdk \(compileSDK)")
        } else {
            unknown.append("the evaluated application module did not report compileSdk")
        }

        return AndroidCompatibilityEvaluation(required: required, violations: violations, unknown: unknown)
    }

    private static func minimumGradle(for agp: SemanticVersion) -> SemanticVersion? {
        guard agp.major >= 7 else { return nil }
        let table: [Int: [Int: String]] = [
            7: [0: "7.0", 1: "7.2", 2: "7.3.3", 3: "7.4", 4: "7.5"],
            8: [
                0: "8.0", 1: "8.0", 2: "8.2", 3: "8.4", 4: "8.6", 5: "8.7",
                6: "8.7", 7: "8.9", 8: "8.10.2", 9: "8.11.1", 10: "8.11.1",
                11: "8.13", 12: "8.13", 13: "8.13",
            ],
            9: [0: "9.1.0", 1: "9.3.1", 2: "9.4.1", 3: "9.5.0"],
        ]
        return table[agp.major]?[agp.minor].flatMap(SemanticVersion.init(_:))
    }

    private static func minimumJDK(for agp: SemanticVersion) -> Int? {
        switch agp.major {
        case 7: 11
        case 8, 9: 17
        default: nil
        }
    }

    private static func minimumGradleForJava(_ java: Int) -> SemanticVersion? {
        let table: [Int: String] = [
            8: "2.0", 9: "4.3", 10: "4.7", 11: "5.0", 12: "5.4", 13: "6.0",
            14: "6.3", 15: "6.7", 16: "7.0", 17: "7.3", 18: "7.5", 19: "7.6",
            20: "8.3", 21: "8.5", 22: "8.8", 23: "8.10", 24: "8.14",
            25: "9.1.0", 26: "9.4.0",
        ]
        return table[java].flatMap(SemanticVersion.init(_:))
    }

    private static func minimumAGP(for api: Double) -> SemanticVersion? {
        switch api {
        case 37...: SemanticVersion("9.1.1")
        case 36.1...: SemanticVersion("8.13.0")
        case 36...: SemanticVersion("8.9.1")
        case 35...: SemanticVersion("8.6.0")
        case 34...: SemanticVersion("8.1.1")
        case 33...: SemanticVersion("7.2.0")
        default: nil
        }
    }

    private static func apiLevel(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: "android-", with: ""))
    }
}

extension SemanticVersion {
    /// Java's version string (JEP 322) can carry a fourth numeric component and a
    /// `-pre`/`+build` suffix (`21.0.12.1+7`); ordering uses the first three. Lock
    /// files and declarations keep the stricter `SemanticVersion(_:)`.
    init?(java text: String) {
        let numeric = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix { $0 != "+" && $0 != "-" }
        self.init(numeric.split(separator: ".", omittingEmptySubsequences: false).prefix(3).joined(separator: "."))
    }
}
