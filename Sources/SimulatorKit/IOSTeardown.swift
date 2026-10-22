import Core
import Foundation

/// What `down` aims at on iOS, assembled next to the jobs themselves the way
/// `iOSStages` is — so adding one is never a CLI edit.
///
/// Metro first: it is the half that can fail, and a reader watching two lines land
/// should see the one with news first.
public func iOSTeardown(
    anchor: ProjectAnchor,
    runner: any ProcessRunner,
    locator: XcodeLocator,
    logs: RunLogs? = nil,
    grace: Duration = MetroTeardown.defaultGrace,
    leases: ResourceLeases = .user,
    ownerProject: String? = nil
) -> Teardown {
    let logs = logs ?? RunLogs(project: anchor.directory)
    let app = AppTeardown(logs: logs, runner: runner, locator: locator, leases: leases,
        ownerProject: ownerProject ?? (anchor.workspaceRoot?.directory ?? anchor.directory).standardizedFileURL.resolvingSymlinksInPath().path)
    guard anchor.framework == .reactNative else {
        return Teardown(jobs: [(id: AppTeardown.id, run: { @Sendable in await app.run() })])
    }
    return Teardown(jobs: [
        (id: MetroTeardown.id, run: { @Sendable in
            try await MetroTeardown(anchor: anchor.directory, runner: runner, grace: grace,
                port: logs.metroPort() ?? MetroVerdict.port).run()
        }),
        (id: AppTeardown.id, run: { @Sendable in await app.run() }),
    ])
}
