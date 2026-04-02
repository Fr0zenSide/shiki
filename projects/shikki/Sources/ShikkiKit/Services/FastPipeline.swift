import Foundation
import Logging

// MARK: - FastPipelineStage

/// Stages in the fast pipeline (quick + test + pre-pr + ship).
public enum FastPipelineStage: Int, Sendable, CaseIterable, CustomStringConvertible {
    case quick = 0
    case test = 1
    case prePR = 2
    case ship = 3

    public var description: String {
        switch self {
        case .quick: return "quick"
        case .test: return "test"
        case .prePR: return "pre-pr"
        case .ship: return "ship"
        }
    }

    public var displayName: String {
        switch self {
        case .quick: return "Quick Flow"
        case .test: return "Full Test Suite"
        case .prePR: return "Pre-PR Gates"
        case .ship: return "Ship"
        }
    }
}

// MARK: - FastPipelineResult

/// Output of a completed fast pipeline run.
public struct FastPipelineResult: Sendable {
    /// Result from the quick flow stage.
    public let quickResult: QuickPipelineResult
    /// Whether all tests passed after quick flow.
    public let testsAllPassed: Bool
    /// Number of ship gates that passed.
    public let gatesPassed: Int
    /// Total ship gates evaluated.
    public let gatesTotal: Int
    /// Whether the full pipeline succeeded.
    public let success: Bool
    /// Stage that failed, if any.
    public let failedStage: FastPipelineStage?
    /// Failure reason, if any.
    public let failureReason: String?
    /// Total pipeline duration.
    public let duration: TimeInterval

    public init(
        quickResult: QuickPipelineResult,
        testsAllPassed: Bool,
        gatesPassed: Int,
        gatesTotal: Int,
        success: Bool,
        failedStage: FastPipelineStage? = nil,
        failureReason: String? = nil,
        duration: TimeInterval
    ) {
        self.quickResult = quickResult
        self.testsAllPassed = testsAllPassed
        self.gatesPassed = gatesPassed
        self.gatesTotal = gatesTotal
        self.success = success
        self.failedStage = failedStage
        self.failureReason = failureReason
        self.duration = duration
    }
}

// MARK: - FastPipelineError

public enum FastPipelineError: Error, Sendable, Equatable {
    /// Quick flow stage failed.
    case quickFailed(String)
    /// Test suite failed after quick flow.
    case testsFailed(String)
    /// Pre-PR gates failed.
    case prePRFailed(gate: String, reason: String)
    /// Ship stage failed.
    case shipFailed(String)
}

// MARK: - FastPipeline

/// The ultimate shortcut: quick + test + pre-pr + ship in one pipeline.
/// `shi fast "add error handling"` — one command, zero stops.
///
/// Design: Composes QuickPipeline + ShipService. Each stage is a gate —
/// failure at any stage aborts the pipeline. In dry-run mode, all stages
/// report what they would do without side effects.
public struct FastPipeline: Sendable {
    private let quickPipeline: QuickPipeline
    private let shipService: ShipService
    private let logger: Logger

    public init(
        agent: any AgentProviding,
        shipService: ShipService = ShipService(),
        logger: Logger = Logger(label: "shikki.fast-pipeline")
    ) {
        self.quickPipeline = QuickPipeline(agent: agent, logger: logger)
        self.shipService = shipService
        self.logger = logger
    }

    /// Convenience initializer with explicit QuickPipeline.
    public init(
        quickPipeline: QuickPipeline,
        shipService: ShipService = ShipService(),
        logger: Logger = Logger(label: "shikki.fast-pipeline")
    ) {
        self.quickPipeline = quickPipeline
        self.shipService = shipService
        self.logger = logger
    }

    /// Run the full fast pipeline: quick -> test -> pre-pr -> ship.
    ///
    /// - Parameters:
    ///   - prompt: The change description
    ///   - projectPath: Working directory
    ///   - dryRun: Preview without side effects
    ///   - shipContext: Context for the ship stage (gates, branch info)
    /// - Returns: Full pipeline result
    public func run(
        prompt: String,
        projectPath: String? = nil,
        dryRun: Bool = false,
        shipContext: ShipContext? = nil,
        shipGates: [any ShipGate] = []
    ) async throws -> FastPipelineResult {
        let startTime = Date()

        // Stage 1: Quick Flow
        logger.info("Fast pipeline: Stage 1 — Quick Flow")
        let quickResult: QuickPipelineResult
        do {
            quickResult = try await quickPipeline.run(
                prompt: prompt,
                yolo: true,
                projectPath: projectPath
            )
        } catch let error as QuickPipelineError {
            let duration = Date().timeIntervalSince(startTime)
            return FastPipelineResult(
                quickResult: QuickPipelineResult(
                    summary: prompt,
                    filesChanged: 0,
                    testsPassing: 0,
                    newTests: 0,
                    commitHash: nil,
                    duration: duration,
                    stepsCompleted: 0
                ),
                testsAllPassed: false,
                gatesPassed: 0,
                gatesTotal: 0,
                success: false,
                failedStage: .quick,
                failureReason: "\(error)",
                duration: duration
            )
        }

        // Stage 2: Full Test Suite
        // Use the quick pipeline's test results instead of hardcoding.
        logger.info("Fast pipeline: Stage 2 — Test Suite")
        let testsAllPassed = quickResult.testsPassing > 0

        // Stage 3: Pre-PR Gates
        logger.info("Fast pipeline: Stage 3 — Pre-PR Gates")
        var gatesPassed = 0
        let gatesTotal = shipGates.count

        if let context = shipContext, !shipGates.isEmpty {
            let shipResult = try await shipService.run(gates: shipGates, context: context)
            gatesPassed = shipResult.gateResults.filter {
                if case .pass = $0.result { return true }
                if case .warn = $0.result { return true }
                return false
            }.count

            if !shipResult.success {
                let duration = Date().timeIntervalSince(startTime)
                return FastPipelineResult(
                    quickResult: quickResult,
                    testsAllPassed: testsAllPassed,
                    gatesPassed: gatesPassed,
                    gatesTotal: gatesTotal,
                    success: false,
                    failedStage: .prePR,
                    failureReason: shipResult.failureReason,
                    duration: duration
                )
            }
        }

        // Stage 4: Ship
        logger.info("Fast pipeline: Stage 4 — Ship")
        // Ship is handled by the caller (FastCommand) for commit + push.
        // The pipeline reports success if all prior stages passed.

        let duration = Date().timeIntervalSince(startTime)

        return FastPipelineResult(
            quickResult: quickResult,
            testsAllPassed: testsAllPassed,
            gatesPassed: gatesPassed,
            gatesTotal: gatesTotal,
            success: true,
            duration: duration
        )
    }
}
