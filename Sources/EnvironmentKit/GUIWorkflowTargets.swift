import Core

extension WorkflowOperation {
    /// The window's selection lists after a build or up. Lists the workflow did not load keep the
    /// inspected candidates, and its next step is not a target-discovery failure.
    public static func guiTargets(_ current: WorkflowOperation?, after workflow: WorkflowOperation) -> WorkflowOperation {
        // An empty list means not loaded: Android build loads no devices, and early failures load nothing.
        // Execution validates any kept choice again.
        var targets = current ?? WorkflowOperation(id: workflow.id, kind: workflow.kind, state: workflow.state)
        // Loaded project candidates mean discovery worked, so an earlier discovery failure is stale.
        if !(workflow.schemes + workflow.configurations + workflow.modules + workflow.variants).isEmpty {
            targets.nextAction = nil
        }
        if !workflow.devices.isEmpty { targets.devices = workflow.devices }
        if !workflow.schemes.isEmpty { targets.schemes = workflow.schemes; targets.scheme = workflow.scheme }
        if !workflow.configurations.isEmpty {
            targets.configurations = workflow.configurations
            targets.configuration = workflow.configuration
        }
        if !workflow.modules.isEmpty { targets.modules = workflow.modules; targets.module = workflow.module }
        if !workflow.variants.isEmpty { targets.variants = workflow.variants; targets.variant = workflow.variant }
        return targets
    }
}
