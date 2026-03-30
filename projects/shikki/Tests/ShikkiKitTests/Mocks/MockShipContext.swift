import Foundation
@testable import ShikkiKit

/// Mock context for testing gates without shell side effects.
actor MockShipContext: ShipContext {
    let isDryRun: Bool
    let branch: String
    let target: String
    let projectRoot: URL
    private var _shellResponses: [String: ShellResult] = [:]
    private var _emittedEvents: [ShikkiEvent] = []
    private var _shellCalls: [String] = []

    var emittedEvents: [ShikkiEvent] {
        _emittedEvents
    }

    var shellCalls: [String] {
        _shellCalls
    }

    init(
        isDryRun: Bool = false,
        branch: String = "feature/test",
        target: String = "develop",
        projectRoot: URL = URL(fileURLWithPath: "/tmp/test-project")
    ) {
        self.isDryRun = isDryRun
        self.branch = branch
        self.target = target
        self.projectRoot = projectRoot
    }

    func stubShell(_ command: String, result: ShellResult) {
        _shellResponses[command] = result
    }

    func shell(_ command: String) async throws -> ShellResult {
        _shellCalls.append(command)
        let result = _shellResponses.first(where: { command.contains($0.key) })?.value
            ?? ShellResult(stdout: "", stderr: "", exitCode: 0)
        return result
    }

    func emit(_ event: ShikkiEvent) async {
        _emittedEvents.append(event)
    }
}
