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
                let _ = try store.setLevel(telemetryLevel)
                let emoji: String
                switch telemetryLevel {
                case .community: emoji = "\u{1F30D}"
                case .local: emoji = "\u{1F4BE}"
                case .off: emoji = "\u{1F6AB}"
                }
                print("\(emoji) Telemetry set to \u{1B}[1m\(level)\u{1B}[0m")
            } else {
                let config = try store.load()
                print("\u{1B}[1mTelemetry Configuration\u{1B}[0m")
                print(String(repeating: "\u{2500}", count: 40))
                print("  Level:       \u{1B}[1m\(config.level.rawValue)\u{1B}[0m")
                print("  Install ID:  \u{1B}[2m\(config.installId)\u{1B}[0m")
                if let consent = config.consentDate {
                    print("  Consent:     \(ISO8601DateFormatter().string(from: consent))")
                }
                print("  Collection:  \(config.isCollectionEnabled ? "enabled" : "disabled")")
                print("  Sharing:     \(config.isSharingEnabled ? "enabled" : "disabled")")
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
            let engine = RiskScoringEngine()

            if files.isEmpty {
                print("\u{1B}[2mUsage: shi flywheel risk <file1> [file2...] [--verbose]\u{1B}[0m")
                print("\u{1B}[2mScores file changes using heuristic risk engine.\u{1B}[0m")
                return
            }

            for filePath in files {
                let input = FileChangeInput(
                    path: filePath,
                    linesAdded: 0,
                    linesRemoved: 0,
                    totalLines: 0,
                    testCoverage: nil
                )
                let profile = engine.score(file: input)
                let tierColor = colorForTier(profile.tier)
                print("\(tierColor)\(profile.tier.rawValue.uppercased())\u{1B}[0m [\(String(format: "%.0f%%", profile.score * 100))] \(filePath)")

                if verbose {
                    for signal in profile.signals {
                        print("  \u{1B}[2m\(signal.name): w=\(String(format: "%.2f", signal.weight)) v=\(String(format: "%.2f", signal.value))\u{1B}[0m")
                    }
                }
            }
        }

        private func colorForTier(_ tier: RiskTier) -> String {
            switch tier {
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

            let config = try telemetryStore.load()
            let stats = try await calibrationStore.computeStats()
            let recordCount = try await calibrationStore.count()

            print("\u{1B}[1m\u{1B}[36mFlywheel Status\u{1B}[0m")
            print(String(repeating: "\u{2500}", count: 40))
            print("  Telemetry:    \u{1B}[1m\(config.level.rawValue)\u{1B}[0m")
            print("  Records:      \(recordCount)")
            print("  Accuracy:     \(String(format: "%.1f%%", stats.accuracy * 100))")
            print("  MAE:          \(String(format: "%.3f", stats.meanAbsoluteError))")
            if stats.totalRecords > 0 {
                print("  Tiers:        \(stats.tierDistribution)")
            } else {
                print("  \u{1B}[2mNo calibration data yet\u{1B}[0m")
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
            let calibrationStore = CalibrationStore()
            let benchmark = CommunityBenchmark()

            let records = try await calibrationStore.loadAll()
            let report = benchmark.generateReport(from: records)

            print("\u{1B}[1m\u{1B}[36mBenchmark Report\u{1B}[0m")
            print(String(repeating: "\u{2500}", count: 50))

            if report.metrics.isEmpty {
                print("  \u{1B}[2mNo benchmark data available. Calibration records will appear")
                print("  after enough outcomes have been collected.\u{1B}[0m")
                return
            }

            for metric in report.metrics {
                print("  \(metric.name): \(String(format: "%.1f", metric.value)) \(metric.unit)")
                if let p = metric.percentile {
                    print("    Percentile: \(String(format: "%.0f%%", p * 100))")
                }
            }

            print(String(repeating: "\u{2500}", count: 50))
            if !report.recommendations.isEmpty {
                print("  Recommendations:")
                for rec in report.recommendations {
                    print("    [\(rec.priority.rawValue)] \(rec.area): \(rec.message)")
                }
            }
        }
    }
}
