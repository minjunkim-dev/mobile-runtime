import Core
import Foundation

public struct AndroidWorkflowTarget: Sendable {
    public let module: String?
    public let variant: String?
    public let modules: [String]
    public let variants: [String]
    public let requiredInput: [String]

    public static func load(anchor: ProjectAnchor, config: ConfigContext, hostRunner: any ProcessRunner,
                            projectRunner: any ProcessRunner, environment: AndroidEnvironment) async throws -> Self {
        let context = AndroidDoctorContext(anchor: anchor, config: config, hostRunner: hostRunner,
                                           projectRunner: projectRunner, environment: environment)
        let model: AndroidGradleModel
        switch try await context.model() {
        case .model(let value): model = value
        case .unavailable(let reason), .failure(let reason):
            throw DomainError(summary: reason, remediation: Remediation(summary: "Prepare the declared Gradle inputs. Run mobile doctor --platform android and follow its setup instructions."))
        }
        let modules = model.modules.map(\.path).sorted()
        switch AndroidTargetSelector.resolve(model: model, configuration: config.configuration,
                                             configFile: config.display(anchor.directory.appendingPathComponent(MobileConfig.fileName))) {
        case .selected(let module, let variant, _):
            return Self(module: module.path, variant: variant.name, modules: modules,
                        variants: module.variants.filter { $0.debuggable && $0.assembleTask != nil && $0.installTask != nil }.map(\.name).sorted(),
                        requiredInput: [])
        case .warning(_, let required, _, _):
            let module = config.configuration?.androidModule.flatMap { name in
                model.modules.first { $0.path == name || $0.path == ":\(name)" }
            } ?? (model.modules.count == 1 ? model.modules.first : nil)
            return Self(module: module?.path, variant: nil, modules: modules,
                        variants: module?.variants.filter { $0.debuggable && $0.assembleTask != nil && $0.installTask != nil }.map(\.name).sorted() ?? [],
                        requiredInput: [required.contains("android.module") ? "--module" : "--variant"])
        case .error(let observed, _, let remediation, _):
            throw DomainError(summary: observed, remediation: remediation)
        }
    }
}

public func androidWorkflowDevices(anchor: ProjectAnchor, config: ConfigContext,
                                   runner: any ProcessRunner, environment: AndroidEnvironment) async throws -> [RuntimeDeviceCandidate] {
    let context = AndroidDoctorContext(anchor: anchor, config: config, hostRunner: runner,
                                       projectRunner: runner, environment: environment)
    let sdk: URL
    switch context.sdkRoot() {
    case .resolved(let root, _): sdk = root
    case .missing(let reason), .conflict(let reason):
        throw DomainError(summary: reason, remediation: Remediation(summary: "Prepare the Android SDK. Run mobile doctor --platform android and follow the setup instructions."))
    }
    let command = context.toolCommand("emulator", ["-list-avds"], sdk: sdk)
    let result = try await runner.run(command)
    guard result.terminationStatus.isSuccess else {
        throw AndroidObservationFailure("Could not list Android AVD identities. Run mobile doctor --platform android.")
    }
    let names = result.standardOutput.split(whereSeparator: \.isNewline).map(String.init)
    return context.avds(names: names, sdk: sdk).filter { $0.config != nil && $0.systemImagePresent }
        .map { RuntimeDeviceCandidate(id: "avd:\($0.name)", name: $0.name,
                                      detail: "API \($0.apiLevel.map(String.init) ?? "unknown") / \($0.abi ?? "unknown")") }
        .sorted { $0.id < $1.id }
}
