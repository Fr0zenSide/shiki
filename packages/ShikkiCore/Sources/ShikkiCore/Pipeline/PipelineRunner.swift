import Foundation

// MARK: - Gate Evaluation

/// Structured replacement for the former tuple `(gate: String, result: PipelineGateResult, duration: Duration)`.
/// Codable + Sendable so pipeline results can be serialized to JSON for event persistence.
public struct GateEvaluation: Codable, Sendable {
    public let gate: String
    public let result: PipelineGateResult
    public let duration: Duration

    public init(gate: String, result: PipelineGateResult, duration: Duration) {
        self.gate = gate
        self.result = result
        self.duration = duration
    }
}

// MARK: - Pipeline Runner

public actor PipelineRunner {
    private let persister: (any EventPersisting)?

    public init(persister: (any EventPersisting)? = nil) {
        self.persister = persister
    }

    public func run(gates: [PipelineGate], context: PipelineContext) async throws -> PipelineResult {
        var results: [GateEvaluation] = []

        for gate in gates {
            let start = ContinuousClock.now
            let result = try await gate.evaluate(context: context)
            let duration = ContinuousClock.now - start

            results.append(GateEvaluation(gate: gate.name, result: result, duration: duration))

            if let persister {
                let payload = CoreEvent.gateEvaluated(
                    featureId: context.featureId,
                    gate: gate.name,
                    passed: result.passed,
                    detail: describeResult(result)
                )
                await persister.persist(payload)
            }

            if case .fail = result {
                return PipelineResult(success: false, gateResults: results, failedGate: gate.name)
            }
        }

        return PipelineResult(success: true, gateResults: results, failedGate: nil)
    }

    private func describeResult(_ result: PipelineGateResult) -> String {
        switch result {
        case .pass(let d): return d ?? "passed"
        case .warn(let r): return "warn: \(r)"
        case .fail(let r): return "fail: \(r)"
        }
    }
}

// MARK: - Pipeline Result

public struct PipelineResult: Codable, Sendable {
    public let success: Bool
    public let gateResults: [GateEvaluation]
    public let failedGate: String?
}
