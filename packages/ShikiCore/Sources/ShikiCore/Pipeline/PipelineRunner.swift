import Foundation

// MARK: - Pipeline Runner

public actor PipelineRunner {
    private let persister: (any EventPersisting)?

    public init(persister: (any EventPersisting)? = nil) {
        self.persister = persister
    }

    public func run(gates: [PipelineGate], context: PipelineContext) async throws -> PipelineResult {
        var results: [(gate: String, result: PipelineGateResult, duration: Duration)] = []

        for gate in gates {
            let start = ContinuousClock.now
            let result = try await gate.evaluate(context: context)
            let duration = ContinuousClock.now - start

            results.append((gate.name, result, duration))

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

public struct PipelineResult: Sendable {
    public let success: Bool
    public let gateResults: [(gate: String, result: PipelineGateResult, duration: Duration)]
    public let failedGate: String?
}
