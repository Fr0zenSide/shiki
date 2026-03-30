import SwiftUI

/// Post-ride report showing overall quality, surface distribution, and segment map.
public struct PostRideReportView: View {

    let report: QualityReport
    let comparison: ComparisonResult?

    public init(report: QualityReport, comparison: ComparisonResult? = nil) {
        self.report = report
        self.comparison = comparison
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                overallScoreSection
                surfaceDistributionSection
                segmentMapSection
                if let comparison {
                    comparisonSection(comparison)
                }
                statsSection
            }
            .padding()
        }
        .navigationTitle("Ride Quality")
    }

    // MARK: - Sections

    private var overallScoreSection: some View {
        VStack(spacing: 8) {
            Text("\(report.averageScore)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(QualityColor.color(for: report.averageScore))

            Text(report.overallTier.displayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Overall Quality")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var surfaceDistributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Surface Distribution")
                .font(.headline)

            ForEach(sortedSurfaces, id: \.surface) { entry in
                HStack {
                    Circle()
                        .fill(QualityColor.surfaceColor(for: entry.surface))
                        .frame(width: 12, height: 12)

                    Text(entry.surface.displayName)
                        .font(.subheadline)

                    Spacer()

                    Text(percentText(entry.fraction))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(QualityColor.surfaceColor(for: entry.surface).opacity(0.6))
                        .frame(width: geometry.size.width * entry.fraction)
                }
                .frame(height: 8)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var segmentMapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quality Map")
                .font(.headline)

            QualityMapOverlay(segments: report.segments)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func comparisonSection(_ result: ComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("vs Previous Ride")
                .font(.headline)

            HStack {
                Image(systemName: trendIcon(result.trend))
                    .foregroundStyle(trendColor(result.trend))

                Text(result.trend.displayName)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(deltaText(result.overallScoreDelta))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(result.overallScoreDelta >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ride Stats")
                .font(.headline)

            HStack {
                statItem(title: "Distance", value: distanceText)
                Spacer()
                statItem(title: "Duration", value: durationText)
                Spacer()
                statItem(title: "Segments", value: "\(report.segments.count)")
            }

            if let best = report.bestSegment {
                HStack {
                    statItem(title: "Best", value: "\(best.score.value) — \(best.score.surfaceType.displayName)")
                }
            }

            if let worst = report.worstSegment {
                HStack {
                    statItem(title: "Worst", value: "\(worst.score.value) — \(worst.score.surfaceType.displayName)")
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func statItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private var sortedSurfaces: [(surface: SurfaceType, fraction: Double)] {
        report.surfaceDistribution
            .map { (surface: $0.key, fraction: $0.value) }
            .sorted(by: { $0.fraction > $1.fraction })
    }

    private func percentText(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private var distanceText: String {
        let km = report.totalDistanceMeters / 1_000
        return String(format: "%.1f km", km)
    }

    private var durationText: String {
        let minutes = Int(report.durationSeconds) / 60
        let seconds = Int(report.durationSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func deltaText(_ delta: Int) -> String {
        delta >= 0 ? "+\(delta)" : "\(delta)"
    }

    private func trendIcon(_ trend: Trend) -> String {
        switch trend {
        case .improving: "arrow.up.right.circle.fill"
        case .stable: "equal.circle.fill"
        case .degrading: "arrow.down.right.circle.fill"
        }
    }

    private func trendColor(_ trend: Trend) -> Color {
        switch trend {
        case .improving: .green
        case .stable: .blue
        case .degrading: .red
        }
    }
}
