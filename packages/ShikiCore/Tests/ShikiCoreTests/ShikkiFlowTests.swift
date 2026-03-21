import Testing
import Foundation
@testable import ShikiCore

@Suite("Shikki Flow Protocol — S2")
struct ShikkiFlowTests {

    // MARK: - Mock Flow

    struct MockFlow: ShikkiFlowProtocol {
        var steps: [String] = []

        func spec(featureName: String) async throws -> String {
            "features/\(featureName.lowercased().replacingOccurrences(of: " ", with: "-")).md"
        }

        func validate(specPath: String) async throws -> Bool {
            !specPath.isEmpty
        }

        func dispatch(specPath: String) async throws -> [String] {
            ["agent-1", "agent-2"]
        }

        func monitor(agentIds: [String]) async -> AsyncStream<DispatchEvent> {
            AsyncStream { continuation in
                for id in agentIds {
                    continuation.yield(DispatchEvent(agentId: id, type: .taskCompleted))
                }
                continuation.finish()
            }
        }

        func collect(agentIds: [String]) async throws -> FlowResult {
            FlowResult(
                specPath: "features/test.md",
                agentIds: agentIds,
                totalTests: 53,
                totalFilesChanged: 22,
                prNumbers: [19, 20],
                success: true
            )
        }

        func prePR(epicBranch: String) async throws -> PrePRResult {
            PrePRResult(epicBranch: epicBranch, gatesPassed: 9, gatesTotal: 9, autoFixesApplied: 2)
        }

        func review(prNumber: Int) async throws -> ReviewDecision {
            .approve
        }

        func merge(prNumber: Int) async throws {}

        func ship(target: String, why: String) async throws -> ShipResult {
            ShipResult(target: target, version: "1.0.0", gatesPassed: 8, gatesTotal: 8, success: true)
        }

        func report(result: FlowResult) async -> String {
            "\(result.prNumbers.count) PRs. \(result.totalTests) tests."
        }
    }

    // MARK: - Protocol Conformance

    @Test("Mock flow conforms to ShikkiFlowProtocol")
    func protocolConformance() async throws {
        let flow = MockFlow()

        let specPath = try await flow.spec(featureName: "Maya Animations")
        #expect(specPath == "features/maya-animations.md")

        let valid = try await flow.validate(specPath: specPath)
        #expect(valid)

        let agentIds = try await flow.dispatch(specPath: specPath)
        #expect(agentIds.count == 2)

        let result = try await flow.collect(agentIds: agentIds)
        #expect(result.success)
        #expect(result.totalTests == 53)
    }

    // MARK: - FlowResult Codable

    @Test("FlowResult Codable round-trip")
    func flowResultCodable() throws {
        let result = FlowResult(
            specPath: "features/test.md",
            agentIds: ["a1", "a2"],
            totalTests: 53,
            totalFilesChanged: 22,
            prNumbers: [19, 20],
            blockers: ["flaky test in CI"],
            success: false
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(FlowResult.self, from: data)

        #expect(decoded.specPath == "features/test.md")
        #expect(decoded.agentIds == ["a1", "a2"])
        #expect(decoded.blockers.count == 1)
        #expect(!decoded.success)
    }

    // MARK: - PrePRResult

    @Test("PrePRResult tracks gate progress")
    func prePRResult() throws {
        let passing = PrePRResult(epicBranch: "epic/v1", gatesPassed: 9, gatesTotal: 9, autoFixesApplied: 3)
        #expect(passing.allGatesPassed)

        let failing = PrePRResult(epicBranch: "epic/v1", gatesPassed: 7, gatesTotal: 9, autoFixesApplied: 0, remainingIssues: ["lint", "coverage"])
        #expect(!failing.allGatesPassed)
        #expect(failing.remainingIssues.count == 2)

        // Codable
        let data = try JSONEncoder().encode(passing)
        let decoded = try JSONDecoder().decode(PrePRResult.self, from: data)
        #expect(decoded.allGatesPassed)
    }

    // MARK: - ReviewDecision

    @Test("ReviewDecision raw values are correct")
    func reviewDecisionValues() {
        #expect(ReviewDecision.approve.rawValue == "approve")
        #expect(ReviewDecision.requestChanges.rawValue == "requestChanges")
        #expect(ReviewDecision.comment.rawValue == "comment")
    }

    // MARK: - ShipResult

    @Test("ShipResult Codable round-trip")
    func shipResultCodable() throws {
        let result = ShipResult(target: "v1.0.0", version: "1.0.0", gatesPassed: 8, gatesTotal: 8, success: true)

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ShipResult.self, from: data)

        #expect(decoded.target == "v1.0.0")
        #expect(decoded.version == "1.0.0")
        #expect(decoded.success)
    }
}
