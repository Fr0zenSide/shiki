import Foundation

/// A normalised 0-100 score representing trail surface quality for a single segment.
///
/// Higher values indicate smoother, more rideable terrain.
/// The score combines vibration intensity, surface regularity and surface type penalty.
public struct GroundQualityScore: Sendable, Codable, Equatable {

    // MARK: - Properties

    /// Normalised score in the range 0...100.
    public let value: Int

    /// Confidence of the classification (0.0...1.0).
    public let confidence: Double

    /// Dominant surface type detected during this scoring window.
    public let surfaceType: SurfaceType

    /// Timestamp when this score was computed.
    public let timestamp: Date

    // MARK: - Init

    public init(value: Int, confidence: Double, surfaceType: SurfaceType, timestamp: Date = .now) {
        self.value = min(max(value, 0), 100)
        self.confidence = min(max(confidence, 0), 1)
        self.surfaceType = surfaceType
        self.timestamp = timestamp
    }

    // MARK: - Convenience

    /// Human-readable quality tier.
    public var tier: QualityTier {
        QualityTier(score: value)
    }
}

// MARK: - QualityTier

public enum QualityTier: String, Sendable, Codable, CaseIterable {
    case excellent
    case good
    case fair
    case poor
    case terrible

    public init(score: Int) {
        switch score {
        case 80...100: self = .excellent
        case 60..<80: self = .good
        case 40..<60: self = .fair
        case 20..<40: self = .poor
        default: self = .terrible
        }
    }

    public var displayName: String {
        rawValue.capitalized
    }
}
