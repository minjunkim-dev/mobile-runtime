import Core
import Foundation

/// A read-only projection. Gradle's private paths and process environment never leave the actor.
public struct AndroidSDKRequirements: Codable, Sendable {
    public let sdkRoot: URL?
    public let packages: [AndroidSDKPackageRequirement]
    public let modules: [AndroidSDKModuleRequirements]
    public let blockers: [String]
}

public struct AndroidSDKPackageRequirement: Codable, Sendable, Equatable {
    public let packagePath: String
    public let requiredFile: String
    public let executable: Bool
    public let source: CheckSource
}

public struct AndroidSDKModuleRequirements: Codable, Sendable {
    public let module: String
    public let agpVersion: String?
    public let gradleVersion: String
    public let daemonJDKVersion: String
    public let compileSDKs: [String]
    public let buildToolsVersion: String?
    public let ndkVersion: String?
    public let cmakeVersion: String?
    public let compatibilityRequirements: [String]
    public let source: CheckSource
}

extension AndroidDoctorContext {
    public func sdkRequirements(includeRuntimeTools: Bool = false) async throws -> AndroidSDKRequirements {
        var blockers: [String] = []
        let sdk: URL?
        switch sdkRoot() {
        case .resolved(let root, _): sdk = root
        case .missing(let reason), .conflict(let reason): sdk = nil; blockers.append(reason)
        }
        guard case .success(let wrapper) = wrapper(), case .model(let model) = try await model() else {
            return AndroidSDKRequirements(sdkRoot: sdk, packages: [], modules: [],
                blockers: blockers + ["An exact locally evaluated Gradle model and wrapper are required; setup does not guess SDK requirements."])
        }
        var packages: [AndroidSDKPackageRequirement] = []
        var modules: [AndroidSDKModuleRequirements] = []
        func add(_ path: String, _ file: String, executable: Bool = false, source: CheckSource) {
            guard !packages.contains(where: { $0.packagePath == path }) else { return }
            packages.append(AndroidSDKPackageRequirement(packagePath: path, requiredFile: file,
                                                         executable: executable, source: source))
        }
        for module in model.modules.sorted(by: { $0.path < $1.path }) {
            let compileSDKs = Set(module.variants.filter(\.debuggable).compactMap(\.compileSdk)
                + [module.compileSdk].compactMap { $0 }).sorted()
            let source = CheckSource(tier: 1, origin: "evaluated Gradle application \(module.path); AGP \(module.agpVersion ?? "unknown"); \(AndroidCompatibility.source.origin)")
            if compileSDKs.isEmpty { blockers.append("\(module.path): compileSdk is unknown") }
            var compatibility: [String] = []
            for compileSDK in compileSDKs {
                let evaluation = AndroidCompatibility.evaluate(wrapper: wrapper, model: model, module: module, compileSDK: compileSDK)
                compatibility += evaluation.required
                blockers += (evaluation.violations + evaluation.unknown).map { "\(module.path): \($0)" }
                let value = compileSDK.replacingOccurrences(of: "android-", with: "")
                if value.range(of: #"^[0-9]+(?:\.[0-9]+)?(?:-ext[0-9]+)?$"#, options: .regularExpression) != nil {
                    add("platforms;android-\(value)", "android.jar", source: source)
                } else { blockers.append("\(module.path): compileSdk does not identify an exact platform package") }
            }
            if let tools = module.buildToolsVersion, tools.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil {
                add("build-tools;\(tools)", "aapt2", executable: true, source: source)
            } else { blockers.append("\(module.path): effective Build Tools version is unknown") }
            var cmake = module.cmakeVersion
            if module.nativeBuildConfigured {
                if let ndk = module.ndkVersion, ndk.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil {
                    add("ndk;\(ndk)", "source.properties", source: source)
                } else { blockers.append("\(module.path): effective NDK revision is unknown") }
                if module.cmakeConfigured == true {
                    var custom = false
                    if cmake == nil {
                        do { custom = try await cmakeDirectory() != nil }
                        catch { blockers.append("\(module.path): declared cmake.dir could not be verified") }
                    }
                    if !custom {
                        if cmake == nil, let agp = module.agpVersion.flatMap({ SemanticVersion($0) }) {
                            cmake = AndroidCompatibility.defaultCMake(for: agp)
                        }
                        if let cmake, cmake.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil {
                            add("cmake;\(cmake)", "bin/cmake", executable: true, source: source)
                        } else { blockers.append("\(module.path): exact CMake requirement is unknown") }
                    }
                }
            }
            modules.append(AndroidSDKModuleRequirements(module: module.path, agpVersion: module.agpVersion,
                gradleVersion: model.gradleVersion, daemonJDKVersion: model.daemonJavaVersion, compileSDKs: compileSDKs,
                buildToolsVersion: module.buildToolsVersion, ndkVersion: module.ndkVersion, cmakeVersion: cmake,
                compatibilityRequirements: Set(compatibility).sorted(), source: source))
        }
        if modules.isEmpty { blockers.append("No evaluated application module supplies SDK requirements") }
        if includeRuntimeTools {
            let source = CheckSource(origin: "Android runtime tools for the selected SDK")
            add("platform-tools", "adb", executable: true, source: source)
            add("emulator", "emulator", executable: true, source: source)
        }
        return AndroidSDKRequirements(sdkRoot: sdk, packages: packages.sorted { $0.packagePath < $1.packagePath },
                                      modules: modules, blockers: Set(blockers).sorted())
    }
}
