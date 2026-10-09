import ArgumentParser
import Core

struct Up: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Build, install and launch on the selected Simulator or Emulator.")
    @OptionGroup var options: WorkflowOptions
    func run() async throws { try await options.run(.up) }
}
