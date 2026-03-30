import SwiftUI

/// Maps ``QualityTier`` and quality scores to colours for map overlays and indicators.
public enum QualityColor {

    /// Colour for a given quality score (0-100).
    public static func color(for score: Int) -> Color {
        color(for: QualityTier(score: score))
    }

    /// Colour for a given quality tier.
    public static func color(for tier: QualityTier) -> Color {
        switch tier {
        case .excellent: .green
        case .good: .mint
        case .fair: .yellow
        case .poor: .orange
        case .terrible: .red
        }
    }

    /// Colour for a given surface type.
    public static func surfaceColor(for surface: SurfaceType) -> Color {
        switch surface {
        case .smooth: .green
        case .gravel: .brown
        case .rocky: .gray
        case .roots: .orange
        case .mud: Color(red: 0.4, green: 0.3, blue: 0.2)
        case .sand: .yellow
        }
    }
}
