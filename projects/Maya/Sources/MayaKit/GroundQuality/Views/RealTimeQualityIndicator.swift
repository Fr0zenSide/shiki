import SwiftUI

/// Compact real-time quality indicator shown during an active ride.
///
/// Displays the current quality score, surface type icon, and a colour-coded ring.
public struct RealTimeQualityIndicator: View {

    let score: GroundQualityScore?

    public init(score: GroundQualityScore?) {
        self.score = score
    }

    public var body: some View {
        ZStack {
            // Background ring.
            Circle()
                .stroke(ringColor.opacity(0.3), lineWidth: 4)
                .frame(width: 64, height: 64)

            // Progress ring.
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(-90))

            // Center content.
            VStack(spacing: 2) {
                Text(scoreText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(ringColor)

                Text(surfaceText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: score?.value)
    }

    // MARK: - Computed

    private var scoreText: String {
        guard let score else { return "--" }
        return "\(score.value)"
    }

    private var surfaceText: String {
        guard let score else { return "Waiting" }
        return score.surfaceType.displayName
    }

    private var ringColor: Color {
        guard let score else { return .gray }
        return QualityColor.color(for: score.value)
    }

    private var ringProgress: CGFloat {
        guard let score else { return 0 }
        return CGFloat(score.value) / 100.0
    }
}
