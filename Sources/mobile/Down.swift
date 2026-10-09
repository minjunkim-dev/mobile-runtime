import ArgumentParser
import Core

struct Down: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop runtime resources owned by this project's selected platform.")
    @OptionGroup var options: WorkflowOptions
    func run() async throws { try await options.run(.down) }
}
