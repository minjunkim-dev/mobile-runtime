import Core
import Foundation

/// What `down` aims at on iOS, assembled next to the jobs themselves the way
/// `iOSUpStages` is — so adding one is never a CLI edit.
///
/// Metro first: it is the half that can fail, and a reader watching two lines land
/// should see the one with news first.
public func iOSTeardown(
    anchor: ProjectAnchor,
    runner: any ProcessRunner,
    locator: XcodeLocator,
    logs: RunLogs? = nil,
    grace: Duration = MetroTeardown.defaultGrace
) -> Teardown {
    let logs = logs ?? RunLogs(project: anchor.directory)
    let metro = MetroTeardown(anchor: anchor.directory, runner: runner, grace: grace)
    let app = AppTeardown(logs: logs, runner: runner, locator: locator)

    return Teardown(jobs: [
        (id: MetroTeardown.id, run: { @Sendable in try await metro.run() }),
        (id: AppTeardown.id, run: { @Sendable in await app.run() }),
    ])
}
