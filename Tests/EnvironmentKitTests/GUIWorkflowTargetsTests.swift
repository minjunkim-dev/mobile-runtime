import Core
import EnvironmentKit
import Testing

@Suite("GUI selection lists after a workflow")
struct GUIWorkflowTargetsTests {
    private let emulator = RuntimeDeviceCandidate(id: "avd:Pixel", name: "Pixel", detail: "Android 15")

    @Test("an Android build keeps the inspected devices it does not load")
    func androidBuildKeepsDevices() {
        var inspected = WorkflowOperation(id: "inspect", kind: .up, state: "ready")
        inspected.devices = [emulator]
        inspected.modules = ["app"]
        inspected.module = "app"
        var build = WorkflowOperation(id: "build", kind: .build, state: "succeeded")
        build.modules = ["app", "wear"]
        build.module = "wear"

        let targets = WorkflowOperation.guiTargets(inspected, after: build)

        #expect(targets.devices.map(\.id) == ["avd:Pixel"])
        #expect(targets.modules == ["app", "wear"])
        #expect(targets.module == "wear")
    }

    @Test("a failed or cancelled build's next step is not shown as a selection failure", arguments: ["failed", "cancelled"])
    func workflowNextActionStaysInWorkflow(state: String) {
        var inspected = WorkflowOperation(id: "inspect", kind: .build, state: "ready")
        inspected.schemes = ["App"]
        inspected.scheme = "App"
        var build = WorkflowOperation(id: "build", kind: .build, state: state)
        build.schemes = ["App"]
        build.scheme = "App"
        build.nextAction = "Inspect completed stages and run down for any remaining runtime resources."

        let targets = WorkflowOperation.guiTargets(inspected, after: build)

        #expect(targets.nextAction == nil)
        #expect(targets.schemes == ["App"])
    }

    @Test("a workflow that stopped before loading candidates keeps every inspected list")
    func earlyFailureKeepsLists() {
        var inspected = WorkflowOperation(id: "inspect", kind: .up, state: "ready")
        inspected.schemes = ["App"]
        inspected.scheme = "App"
        inspected.configurations = ["Debug"]
        inspected.configuration = "Debug"
        inspected.devices = [emulator]
        let failed = WorkflowOperation(id: "up", kind: .up, state: "failed")

        let targets = WorkflowOperation.guiTargets(inspected, after: failed)

        #expect(targets.schemes == ["App"])
        #expect(targets.scheme == "App")
        #expect(targets.configurations == ["Debug"])
        #expect(targets.configuration == "Debug")
        #expect(targets.devices.map(\.id) == ["avd:Pixel"])
    }

    @Test("devices a workflow loaded replace the inspected list")
    func loadedDevicesReplace() {
        var inspected = WorkflowOperation(id: "inspect", kind: .up, state: "ready")
        inspected.devices = [emulator]
        var up = WorkflowOperation(id: "up", kind: .up, state: "succeeded")
        up.devices = [RuntimeDeviceCandidate(id: "avd:Tablet", name: "Tablet", detail: "Android 15")]

        #expect(WorkflowOperation.guiTargets(inspected, after: up).devices.map(\.id) == ["avd:Tablet"])
    }
}
