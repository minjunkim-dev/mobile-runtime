import ArgumentParser
import Core

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Build the project without installing or launching it.")
    @OptionGroup var options: WorkflowOptions
    func run() async throws { try await options.run(.build) }
}
