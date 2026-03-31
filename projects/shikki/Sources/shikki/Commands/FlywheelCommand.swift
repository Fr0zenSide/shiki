import ArgumentParser
import Foundation
import ShikkiKit

struct FlywheelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flywheel",
        abstract: "Community data flywheel — telemetry config, risk scoring, benchmarks",
        subcommands: [
            TelemetrySubcommand.self,
            RiskSubcommand.self,
            StatusSubcommand.self,
            BenchmarkSubcommand.self,
        ]
    )
}

// MARK: - Telemetry Subcommand

extension FlywheelCommand {
    struct TelemetrySubcommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "telemetry",
            abstract: "Configure telemetry level: community, local, off"
        )

        @Argument(help: "Telemetry level: community, local, or off")
        var level: String?

        func run() async throws {
            let store = TelemetryConfigStore()

            if let level {
                guard let telemetryLevel = TelemetryLevel(rawValue: level) else {
                    print("\u{1B}[31mError:\u{1B}[0m Invalid level '\(level)'. Use: community, local, or off")
                    throw ExitCode.failure
                }
                try await store.setLevel(telemetryLevel)
                let emoji: String
                switch telemetryLevel {
                case .community: emoji = "\u{1F30D}"
                case .local: emoji = "\u{1F4BE}"
                case .off: emoji = "\u{1F6AB}"
                }
                print("\(emoji) Telemetry set to \u{1B}[1m\(level)\u{1B}[0m")
            } else {
                let config = await store.current()
                print("\u{1B}[1mTelemetry Configuration\u{1B}[0m")
                print(String(repeating: "\u{2500}", count: 40))
                print("  Level:       \u{1B}[1m\(config.level.rawValue)\u{1B}[0m")
                print("  Install ID:  \u{1B}[2m\(config.installId)\u{1B}[0m")
                if let consent = config.consentDate {
                    print("  Consent:     \(ISO8601DateFormatter().string(from: consent))")
                }
                if let lastSync = config.lastSyncDate {
                    print("  Last sync:   \(ISO8601DateFormatter().string(from: lastSync))")
                }
                if config.level == .community {
                    let cats = config.sharedCategories.map(\.rawValue).sorted().joined(separator: ", ")
                    print("  Sharing:     \(cats)")
                }
            }
        }
    }
}

// MARK: - Risk Subcommand

extension FlywheelCommand {
    struct RiskSubcommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "risk",
            abstract: "Score risk for a file or directory of changes"
        )

        @Argument(help: "File paths to score")
        var files: [String] = []

        @Flag(name: .long, help: "Show detailed risk factors")
        var verbose: Bool = false

        func run() async throws {
            let calibrationStore = CalibrationStore()
            let engine = await RiskScoringEngine(calibrationStore: calibrationStore)

            if files.isEmpty {
                print("\u{1B}[2mUsage: shikki flywheel risk <file1> [file2...] [--verbose]\u{1B}[0m")
                print("\u{1B}[2mScores file changes using heuristic risk engine.\u{1B}[0m")
                return
            }

            for filePath in files {
                let change = FileChange(
                    path: filePath,
                    linesAdded: 0,
                    linesDeleted: 0,
                    isNewFile: !FileManager.default.fileExists(atPath: filePath)
                )
                let score = await engine.scoreFile(change)
                let levelColor = colorForLevel(score.level)
                print("\(levelColor)\(score.level.rawValue.uppercased())\u{1B}[0m [\(String(format: "%.0f%%", score.score * 100))] \(filePath)")

                if verbose {
                    for factor in score.factors {
                        let sign = factor.contribution >= 0 ? "+" : ""
                        print("  \u{1B}[2m\(factor.name): \(sign)\(String(format: "%.2f", factor.contribution)) — \(factor.description)\u{1B}[0m")
                    }
                }
            }
        }

        private func colorForLevel(_ level: RiskTier) -> String {
            switch level {
            case .low: return "\u{1B}[32m"
            case .medium: return "\u{1B}[33m"
            case .high: return "\u{1B}[31m"
            case .critical: return "\u{1B}[35m"
            }
        }
    }
}

// MARK: - Status Subcommand

extension FlywheelCommand {
    struct StatusSubcommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show flywheel subsystem status"
        )

        func run() async throws {
            let telemetryStore = TelemetryConfigStore()
            let calibrationStore = CalibrationStore()
            let config = await telemetryStore.current()
            let calibration = await calibrationStore.current()

            print("\u{1B}[1m\u{1B}[36mFlywheel Status\u{1B}[0m")
            print(String(repeating: "\u{2500}", count: 40))
            print("  Telemetry:    \u{1B}[1m\(config.level.rawValue)\u{1B}[0m")
            print("  Calibration:  v\(calibration.version) (\(ISO8601DateFormatter().string(from: calibration.updatedAt)))")
            print("  Risk weights: churn=\(String(format: "%.0f%%", calibration.riskWeights.churnWeight * 100)), "
                + "coverage=\(String(format: "%.0f%%", calibration.riskWeights.testCoverageWeight * 100)), "
                + "type=\(String(format: "%.0f%%", calibration.riskWeights.fileTypeWeight * 100))")

            let baselines = calibration.benchmarkBaselines
            if baselines.sampleCount > 0 {
                print("  Baselines:    \(baselines.sampleCount) samples, "
                    + "\(String(format: "%.0f%%", baselines.taskSuccessRate * 100)) success rate")
            } else {
                print("  Baselines:    \u{1B}[2mno community data yet\u{1B}[0m")
            }
        }
    }
}

// MARK: - Benchmark Subcommand

extension FlywheelCommand {
    struct BenchmarkSubcommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "benchmark",
            abstract: "Compare local metrics against community baselines"
        )

        func run() async throws {
            let telemetryStore = TelemetryConfigStore()
            let calibrationStore = CalibrationStore()
            let outcomeCollector = OutcomeCollector(telemetryStore: telemetryStore)
            let benchmark = CommunityBenchmark(
                calibrationStore: calibrationStore,
                outcomeCollector: outcomeCollector
            )

            let report = await benchmark.generateReport()

            print("\u{1B}[1m\u{1B}[36mBenchmark Report\u{1B}[0m")
            print(String(repeating: "\u{2500}", count: 50))

            if report.comparisons.isEmpty {
                print("  \u{1B}[2mNo benchmark data available. Community baselines will appear")
                print("  after enough anonymized outcomes have been collected.\u{1B}[0m")
                return
            }

            for comparison in report.comparisons {
                let arrow: String
                if comparison.delta > 0 {
                    arrow = "\u{1B}[32m\u{25B2}\u{1B}[0m"
                } else if comparison.delta < 0 {
                    arrow = "\u{1B}[31m\u{25BC}\u{1B}[0m"
                } else {
                    arrow = "\u{1B}[33m\u{25C6}\u{1B}[0m"
                }

                print("  \(arrow) \(comparison.metric)")
                print("    Local: \(String(format: "%.1f%%", comparison.localValue * 100))  "
                    + "Community: \(String(format: "%.1f%%", comparison.communityBaseline * 100))  "
                    + "[\(comparison.percentile.rawValue)]")
            }

            print(String(repeating: "\u{2500}", count: 50))
            print("  Health: \(String(format: "%.0f%%", report.healthScore * 100))  "
                + "Local: \(report.localSampleCount) samples  "
                + "Community: \(report.communitySampleCount) samples")
        }
    }
}
