import Foundation

// MARK: - ShipService

/// Pipeline-of-gates orchestrator. Runs gates sequentially, aborts on failure.
/// Emits ShipEvents at each step for event bus integration.
public actor ShipService {

    public init() {}

    /// Run the ship pipeline with the given gates and context.
    /// - Parameters:
    ///   - gates: Ordered array of gates to evaluate
    ///   - context: Real or dry-run context
    /// - Returns: Pipeline result with success/failure, warnings, and gate results
    public func run(gates: [any ShipGate], context: ShipContext) async throws -> ShipResult {
        let startTime = Date()

        // Emit shipStarted
        await context.emit(ShikkiEvent(
            source: .process(name: "ship"),
            type: .shipStarted,
            scope: .project(slug: "shikki"),
            payload: [
                "branch": .string(context.branch),
                "target": .string(context.target),
                "dryRun": .bool(context.isDryRun),
                "gateCount": .int(gates.count),
            ]
        ))

        var warnings: [String] = []
        var gateResults: [(gate: String, result: GateResult)] = []

        for gate in gates {
            // Emit gateStarted
            await context.emit(ShikkiEvent(
                source: .process(name: "ship"),
                type: .shipGateStarted,
                scope: .project(slug: "shikki"),
                payload: [
                    "gate": .string(gate.name),
                    "index": .int(gate.index),
                ]
            ))

            let gateStart = Date()
            let result: GateResult

            do {
                result = try await gate.evaluate(context: context)
            } catch {
                // Gate threw an error — treat as failure
                let reason = "Gate '\(gate.name)' threw error: \(error.localizedDescription)"
                await emitGateFailed(gate: gate, reason: reason, context: context)
                await emitShipAborted(gate: gate, reason: reason, context: context)
                return ShipResult(
                    success: false,
                    failedGate: gate.name,
                    failureReason: reason,
                    warnings: warnings,
                    gateResults: gateResults
                )
            }

            let gateDuration = Date().timeIntervalSince(gateStart)
            gateResults.append((gate: gate.name, result: result))

            switch result {
            case .pass(let detail):
                await context.emit(ShikkiEvent(
                    source: .process(name: "ship"),
                    type: .shipGatePassed,
                    scope: .project(slug: "shikki"),
                    payload: [
                        "gate": .string(gate.name),
                        "index": .int(gate.index),
                        "detail": .string(detail ?? ""),
                    ],
                    metadata: EventMetadata(duration: gateDuration)
                ))

            case .warn(let reason):
                warnings.append("\(gate.name): \(reason)")
                // Warn still counts as passed
                await context.emit(ShikkiEvent(
                    source: .process(name: "ship"),
                    type: .shipGatePassed,
                    scope: .project(slug: "shikki"),
                    payload: [
                        "gate": .string(gate.name),
                        "index": .int(gate.index),
                        "warning": .string(reason),
                    ],
                    metadata: EventMetadata(duration: gateDuration)
                ))

            case .fail(let reason):
                await emitGateFailed(gate: gate, reason: reason, context: context)
                await emitShipAborted(gate: gate, reason: reason, context: context)
                return ShipResult(
                    success: false,
                    failedGate: gate.name,
                    failureReason: reason,
                    warnings: warnings,
                    gateResults: gateResults
                )
            }
        }

        // All gates passed — emit shipCompleted
        let totalDuration = Date().timeIntervalSince(startTime)
        await context.emit(ShikkiEvent(
            source: .process(name: "ship"),
            type: .shipCompleted,
            scope: .project(slug: "shikki"),
            payload: [
                "gatesPassed": .int(gates.count),
                "warnings": .int(warnings.count),
                "dryRun": .bool(context.isDryRun),
            ],
            metadata: EventMetadata(duration: totalDuration)
        ))

        return ShipResult(
            success: true,
            warnings: warnings,
            gateResults: gateResults
        )
    }

    // MARK: - Private

    private func emitGateFailed(gate: any ShipGate, reason: String, context: ShipContext) async {
        await context.emit(ShikkiEvent(
            source: .process(name: "ship"),
            type: .shipGateFailed,
            scope: .project(slug: "shikki"),
            payload: [
                "gate": .string(gate.name),
                "index": .int(gate.index),
                "reason": .string(reason),
            ]
        ))
    }

    private func emitShipAborted(gate: any ShipGate, reason: String, context: ShipContext) async {
        await context.emit(ShikkiEvent(
            source: .process(name: "ship"),
            type: .shipAborted,
            scope: .project(slug: "shikki"),
            payload: [
                "gate": .string(gate.name),
                "reason": .string(reason),
            ]
        ))
    }
}
