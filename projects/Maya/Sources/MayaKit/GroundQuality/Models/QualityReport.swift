import Foundation

/// Post-ride report aggregating all trail segments into an overall quality summary.
public struct QualityReport: Sendable, Codable, Identifiable, Equatable {

    public let id: UUID
    public let segments: [TrailSegment]
    public let rideDate: Date
    public let totalDistanceMeters: Double
    public let durationSeconds: TimeInterval

    public init(
        id: UUID = UUID(),
        segments: [TrailSegment],
        rideDate: Date,
        totalDistanceMeters: Double,
        durationSeconds: TimeInterval
    ) {
        self.id = id
        self.segments = segments
        self.rideDate = rideDate
        self.totalDistanceMeters = totalDistanceMeters
        self.durationSeconds = durationSeconds
    }

    // MARK: - Aggregates

    /// Weighted average quality score across all segments.
    public var averageScore: Int {
        guard !segments.isEmpty else { return 0 }
        let totalWeightedScore = segments.reduce(0.0) { acc, segment in
            acc + Double(segment.score.value) * segment.distanceMeters
        }
        return Int((totalWeightedScore / totalDistanceMeters).rounded())
    }

    /// Overall quality tier based on the average score.
    public var overallTier: QualityTier {
        QualityTier(score: averageScore)
    }

    /// Distribution of surface types as a fraction of total distance.
    public var surfaceDistribution: [SurfaceType: Double] {
        guard totalDistanceMeters > 0 else { return [:] }
        var distribution: [SurfaceType: Double] = [:]
        for segment in segments {
            distribution[segment.score.surfaceType, default: 0] += segment.distanceMeters
        }
        return distribution.mapValues { $0 / totalDistanceMeters }
    }

    /// Worst segment by quality score.
    public var worstSegment: TrailSegment? {
        segments.min(by: { $0.score.value < $1.score.value })
    }

    /// Best segment by quality score.
    public var bestSegment: TrailSegment? {
        segments.max(by: { $0.score.value < $1.score.value })
    }
}
