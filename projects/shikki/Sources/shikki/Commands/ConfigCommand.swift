import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki config` — manage Shikki configuration settings.
///
/// Examples:
///   shikki config --telemetry community    # share anonymized outcomes
///   shikki config --telemetry local        # local only (default)
///   shikki config --telemetry off          # no collection
///   shikki config --show                   # show current config
struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage Shikki configuration (telemetry, calibration)"
    )

    @Option(name: .long, help: "Set telemetry level: community, local, off")
    var telemetry: String?

    @Flag(name: .long, help: "Show current configuration")
    var show: Bool = false

    @Flag(name: .long, help: "Show calibration statistics")
    var calibrationStats: Bool = false

    @Option(name: .long, help: "Custom config path (for testing)")
    var configPath: String?

    @Option(name: .long, help: "Custom calibration path (for testing)")
    var calibrationPath: String?

    func run() async throws {
        let store = TelemetryConfigStore(configPath: configPath)

        if let levelStr = telemetry {
            guard let level = TelemetryLevel(rawValue: levelStr) else {
                print("Unknown telemetry level: '\(levelStr)'")
                print("Valid options: community, local, off")
                throw ExitCode(1)
            }

            let config = try store.setLevel(level)
            printTelemetryStatus(config)
            return
        }

        if calibrationStats {
            let calibStore = CalibrationStore(filePath: calibrationPath)
            let stats = try await calibStore.computeStats()
            printCalibrationStats(stats)
            return
        }

        if show {
            let config = try store.load()
            printFullConfig(config)
            return
        }

        // Default: show current telemetry status
        let config = try store.load()
        printTelemetryStatus(config)
    }

    // MARK: - Output

    private func printTelemetryStatus(_ config: TelemetryConfig) {
        let icon: String
        switch config.level {
        case .community: icon = "\u{1B}[32m[community]\u{1B}[0m"
        case .local: icon = "\u{1B}[33m[local]\u{1B}[0m"
        case .off: icon = "\u{1B}[31m[off]\u{1B}[0m"
        }

        print("Telemetry: \(icon) \(config.level.rawValue)")
        if config.level == .community, let date = config.consentDate {
            let formatter = ISO8601DateFormatter()
            print("  Consent given: \(formatter.string(from: date))")
        }
    }

    private func printFullConfig(_ config: TelemetryConfig) {
        print("Shikki Configuration")
        print("--------------------")
        print("Telemetry level : \(config.level.rawValue)")
        print("Install ID      : \(config.installId)")
        print("Collection      : \(config.isCollectionEnabled ? "enabled" : "disabled")")
        print("Sharing         : \(config.isSharingEnabled ? "enabled" : "disabled")")
        print("Schema version  : \(config.version)")
        if let date = config.consentDate {
            let formatter = ISO8601DateFormatter()
            print("Consent date    : \(formatter.string(from: date))")
        }
    }

    private func printCalibrationStats(_ stats: CalibrationStats) {
        print("Calibration Statistics")
        print("----------------------")
        print("Total records   : \(stats.totalRecords)")
        print("Accuracy        : \(String(format: "%.1f", stats.accuracy * 100))%")
        print("Mean abs. error : \(String(format: "%.3f", stats.meanAbsoluteError))")

        if !stats.tierDistribution.isEmpty {
            print("\nPredicted tier distribution:")
            for (tier, count) in stats.tierDistribution.sorted(by: { $0.key < $1.key }) {
                print("  \(tier): \(count)")
            }
        }

        if !stats.outcomeDistribution.isEmpty {
            print("\nActual outcome distribution:")
            for (outcome, count) in stats.outcomeDistribution.sorted(by: { $0.key < $1.key }) {
                print("  \(outcome): \(count)")
            }
        }
    }
}
