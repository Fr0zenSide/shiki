import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Test Helpers

/// A gate that always passes.
struct PassGate: ShipGate, Sendable {
    let name: String
    let index: Int

    func evaluate(context: ShipContext) async throws -> GateResult {
        .pass(detail: "\(name) OK")
    }
}

/// A gate that always fails.
struct FailGate: ShipGate, Sendable {
    let name: String
    let index: Int
    let reason: String

    func evaluate(context: ShipContext) async throws -> GateResult {
        .fail(reason: reason)
    }
}

/// A gate that always warns.
struct WarnGate: ShipGate, Sendable {
    let name: String
    let index: Int
    let reason: String

    func evaluate(context: ShipContext) async throws -> GateResult {
        .warn(reason: reason)
    }
}

/// A gate that throws.
struct ThrowGate: ShipGate, Sendable {
    let name: String
    let index: Int

    func evaluate(context: ShipContext) async throws -> GateResult {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
    }
}

// MARK: - ShipService Tests

@Suite("ShipService -- Pipeline")
struct ShipServiceTests {

    @Test("Pipeline emits events per gate")
    func emitsEventsPerGate() async throws {
        let ctx = MockShipContext()
        let service = ShipService()
        let gates: [any ShipGate] = [
            PassGate(name: "Gate1", index: 0),
            PassGate(name: "Gate2", index: 1),
            PassGate(name: "Gate3", index: 2),
        ]

        let result = try await service.run(gates: gates, context: ctx)

        // Should have: shipStarted + (gateStarted + gatePassed) * 3 + shipCompleted = 8
        let events = await ctx.emittedEvents
        #expect(events.count >= 8)
        #expect(events.first?.type == .shipStarted)
        #expect(events.last?.type == .shipCompleted)
        #expect(result.success)
    }

    @Test("Gate failure aborts immediately")
    func gateFailureAbortsImmediately() async throws {
        let ctx = MockShipContext()
        let service = ShipService()
        let gates: [any ShipGate] = [
            PassGate(name: "Gate1", index: 0),
            FailGate(name: "Gate2", index: 1, reason: "tests failed"),
            PassGate(name: "Gate3", index: 2),
        ]

        let result = try await service.run(gates: gates, context: ctx)

        #expect(!result.success)
        #expect(result.failedGate == "Gate2")
        // Gate3 should never have been evaluated
        let gateStartEvents = await ctx.emittedEvents.filter { $0.type == .shipGateStarted }
        #expect(gateStartEvents.count == 2) // Gate1 and Gate2 only
    }

    @Test("Gate failure emits abort event")
    func gateFailureEmitsAbortEvent() async throws {
        let ctx = MockShipContext()
        let service = ShipService()
        let gates: [any ShipGate] = [
            FailGate(name: "CleanBranch", index: 0, reason: "working tree dirty"),
        ]

        let result = try await service.run(gates: gates, context: ctx)

        #expect(!result.success)
        let events = await ctx.emittedEvents
        #expect(events.contains { $0.type == .shipAborted })
        #expect(events.contains { $0.type == .shipGateFailed })
    }

    @Test("Dry-run runs same validation")
    func dryRunSameValidation() async throws {
        let ctx = MockShipContext(isDryRun: true)
        let service = ShipService()
        let gates: [any ShipGate] = [
            PassGate(name: "Gate1", index: 0),
            PassGate(name: "Gate2", index: 1),
        ]

        let result = try await service.run(gates: gates, context: ctx)

        #expect(result.success)
        let events = await ctx.emittedEvents
        #expect(events.contains { $0.type == .shipStarted })
        #expect(events.contains { $0.type == .shipCompleted })
    }

    @Test("Warn gate does not abort pipeline")
    func warnGateDoesNotAbort() async throws {
        let ctx = MockShipContext()
        let service = ShipService()
        let gates: [any ShipGate] = [
            PassGate(name: "Gate1", index: 0),
            WarnGate(name: "Coverage", index: 1, reason: "below threshold"),
            PassGate(name: "Gate3", index: 2),
        ]

        let result = try await service.run(gates: gates, context: ctx)

        #expect(result.success)
        #expect(result.warnings.count == 1)
    }

    @Test("Gate exception treated as failure")
    func gateExceptionTreatedAsFailure() async throws {
        let ctx = MockShipContext()
        let service = ShipService()
        let gates: [any ShipGate] = [
            ThrowGate(name: "Broken", index: 0),
            PassGate(name: "Gate2", index: 1),
        ]

        let result = try await service.run(gates: gates, context: ctx)

        #expect(!result.success)
        #expect(result.failedGate == "Broken")
        let events = await ctx.emittedEvents
        #expect(events.contains { $0.type == .shipAborted })
    }

    @Test("Empty gate list succeeds immediately")
    func emptyGateListSucceeds() async throws {
        let ctx = MockShipContext()
        let service = ShipService()

        let result = try await service.run(gates: [], context: ctx)

        #expect(result.success)
        #expect(result.gateResults.isEmpty)
    }

    @Test("12-gate pipeline with TestFlight runs all gates")
    func fullPipelineWith12Gates() async throws {
        let ctx = MockShipContext()
        let service = ShipService()
        let gates: [any ShipGate] = (0..<12).map { PassGate(name: "Gate\($0)", index: $0) }

        let result = try await service.run(gates: gates, context: ctx)

        #expect(result.success)
        #expect(result.gateResults.count == 12)
    }

    @Test("Gate failure at gate 9 skips gates 10-12")
    func failureAtGate9SkipsRest() async throws {
        let ctx = MockShipContext()
        let service = ShipService()
        var gates: [any ShipGate] = (0..<8).map { PassGate(name: "Core\($0)", index: $0) }
        gates.append(FailGate(name: "Archive", index: 8, reason: "signing error"))
        gates.append(PassGate(name: "Export", index: 9))
        gates.append(PassGate(name: "Upload", index: 10))
        gates.append(PassGate(name: "Distribute", index: 11))

        let result = try await service.run(gates: gates, context: ctx)

        #expect(!result.success)
        #expect(result.failedGate == "Archive")
        #expect(result.gateResults.count == 9) // 8 pass + 1 fail
    }
}

// MARK: - ShipLog Tests

@Suite("ShipLog")
struct ShipLogTests {

    @Test("Ship log appends entry with mandatory why")
    func shipLogAppendsEntry() throws {
        let tempPath = NSTemporaryDirectory() + "ship-log-test-\(UUID().uuidString).md"
        let log = ShipLog(path: tempPath)

        try log.append(ShipLogEntry(
            date: Date(),
            version: "1.2.0",
            project: "shikki",
            branch: "feature/ship",
            why: "First release with ship command",
            riskScore: 3,
            gateSummary: "8/8 passed"
        ))

        let contents = try String(contentsOfFile: tempPath, encoding: .utf8)
        #expect(contents.contains("1.2.0"))
        #expect(contents.contains("First release with ship command"))
        #expect(contents.contains("shikki"))

        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @Test("Ship log creates file if not exists")
    func createsFile() throws {
        let tempPath = NSTemporaryDirectory() + "ship-log-new-\(UUID().uuidString).md"
        let log = ShipLog(path: tempPath)

        try log.append(ShipLogEntry(
            date: Date(),
            version: "0.1.0",
            project: "test",
            branch: "main",
            why: "test entry",
            riskScore: 0,
            gateSummary: "1/1 passed"
        ))

        #expect(FileManager.default.fileExists(atPath: tempPath))
        let contents = try String(contentsOfFile: tempPath, encoding: .utf8)
        #expect(contents.contains("# Ship Log"))

        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @Test("Read history returns contents")
    func readHistoryReturnsContents() throws {
        let tempPath = NSTemporaryDirectory() + "ship-log-read-\(UUID().uuidString).md"
        try "# Ship Log\n\n## 1.0.0\n".write(toFile: tempPath, atomically: true, encoding: .utf8)

        let log = ShipLog(path: tempPath)
        let history = try log.readHistory()
        #expect(history.contains("Ship Log"))

        try? FileManager.default.removeItem(atPath: tempPath)
    }

    @Test("Read history returns message when file missing")
    func readHistoryMissingFile() throws {
        let log = ShipLog(path: "/tmp/nonexistent-\(UUID().uuidString).md")
        let history = try log.readHistory()
        #expect(history.contains("No ship log found"))
    }
}
