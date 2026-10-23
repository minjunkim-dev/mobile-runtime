import Core
import Foundation

struct AndroidCompatibilityEvaluation: Sendable, Equatable {
    let required: [String]
    let violations: [String]
    let unknown: [String]
}

public enum AndroidCompatibility {
    static let source = CheckSource(
        tier: 2,
        origin: "Android AGP compatibility table + Gradle Java compatibility table (2026-10-15); https://developer.android.com/build/releases/about-agp; https://docs.gradle.org/current/userguide/compatibility.html"
    )

    /// Preparation uses the same official tables as the evaluated build checks.
    /// Unknown compatibility never authorizes a new JDK candidate.
    public static func preparationJDKBlocker(major: Int, gradle: SemanticVersion, agp: SemanticVersion) -> String? {
        guard let agpGradle = minimumGradle(for: agp), let agpJDK = minimumJDK(for: agp),
              let javaGradle = minimumGradleForJava(major) else {
            return "The bundled AGP/Gradle/JDK tables do not cover this exact toolchain"
        }
        guard gradle >= agpGradle else { return "AGP \(agp) requires Gradle \(agpGradle) or newer" }
        guard major >= agpJDK else { return "AGP \(agp) requires JDK \(agpJDK) or newer" }
        guard gradle >= javaGradle else { return "JDK \(major) requires Gradle \(javaGradle) or newer" }
        guard gradle < SemanticVersion(major: 9) || major >= 17 else { return "Gradle 9 and newer require JDK 17 or newer" }
        return nil
    }

    static func effectiveBuildTools(declared: String?, agp: String?) -> String? {
        guard let declared, let version = SemanticVersion(declared) else { return nil }
        // Preserve observed data for doctor. The compatibility evaluation separately
        // blocks preparation when the plugin's version or compatibility row is unknown.
        guard let agp = agp.flatMap(SemanticVersion.init(_:)) else { return declared }
        // Each stable release's Compatibility table gives both minimum and default.
        // https://developer.android.com/build/releases/agp-<major>-<minor>-0-release-notes
        // SdkHandler replaces a revision below the minimum with the default:
        // https://android.googlesource.com/platform/tools/base/+/studio-master-dev/build-system/gradle-core/src/main/java/com/android/build/gradle/internal/SdkHandler.java
        let table: [Int: [Int: String]] = [
            7: [0: "30.0.2", 1: "30.0.3", 2: "30.0.3", 3: "30.0.3", 4: "30.0.3"],
            8: [0: "30.0.3", 1: "33.0.1", 2: "34.0.0", 3: "34.0.0", 4: "34.0.0",
                5: "34.0.0", 6: "34.0.0", 7: "34.0.0", 8: "35.0.0", 9: "35.0.0",
                10: "35.0.0", 11: "35.0.0", 12: "35.0.0", 13: "35.0.0"],
            9: [0: "36.0.0", 1: "36.0.0", 2: "36.0.0", 3: "36.0.0", 4: "36.0.0"],
        ]
        guard let minimumText = table[agp.major]?[agp.minor],
              let minimum = SemanticVersion(minimumText) else { return declared }
        return version < minimum ? minimumText : declared
    }

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

    static func defaultCMake(for agp: SemanticVersion) -> String? {
        // Stable AGP 8.11–8.13 use CmakeLocator.DEFAULT = LATEST_WITH_FILE_API (3.22.1).
        // https://android.googlesource.com/platform/tools/base/+/refs/tags/studio-2025.1.1/build-system/gradle-core/src/main/java/com/android/build/gradle/internal/cxx/configure/CmakeLocator.kt
        // https://android.googlesource.com/platform/tools/base/+/refs/tags/studio-2025.1.2/build-system/gradle-core/src/main/java/com/android/build/gradle/internal/cxx/configure/CmakeLocator.kt
        // https://android.googlesource.com/platform/tools/base/+/refs/tags/studio-2025.1.3/build-system/gradle-core/src/main/java/com/android/build/gradle/internal/cxx/configure/CmakeLocator.kt
        // AGP 9.2.1 CmakeLocator.kt keeps the same default in its official sources:
        // https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/9.2.1/gradle-9.2.1-sources.jar
        let table: [Int: [Int: String]] = [
            8: [11: "3.22.1", 12: "3.22.1", 13: "3.22.1"],
            9: [2: "3.22.1"],
        ]
        return table[agp.major]?[agp.minor]
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
            9: [0: "9.1.0", 1: "9.3.1", 2: "9.4.1", 3: "9.5.0", 4: "9.6.0"],
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
        let parts = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.dropFirst(3).allSatisfy({ Int($0) != nil }) else { return nil }
        self.init(parts.prefix(3).joined(separator: "."))
    }
}
