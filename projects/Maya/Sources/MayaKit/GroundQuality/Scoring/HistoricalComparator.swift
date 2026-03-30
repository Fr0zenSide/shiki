import Foundation

/// Compares a new ``QualityReport`` against historical data for the same trail.
///
/// Provides delta analysis: which segments improved or degraded, and overall trend.
public struct HistoricalComparator: Sendable {

    public init() {}

    // MARK: - Comparison

    /// Compare a new report against a previous report for the same trail.
    /// - Parameters:
    ///   - current: The newly completed report.
    ///   - previous: A past report for comparison.
    /// - Returns: A ``ComparisonResult`` with deltas.
    public func compare(current: QualityReport, previous: QualityReport) -> ComparisonResult {
        let scoreDelta = current.averageScore - previous.averageScore
        let trend: Trend = if scoreDelta > 5 {
            .improving
        } else if scoreDelta < -5 {
            .degrading
        } else {
            .stable
        }

        // Match segments by proximity and compute per-segment deltas.
        var segmentDeltas: [SegmentDelta] = []
        for currentSegment in current.segments {
            if let matchedPrevious = findClosestSegment(to: currentSegment, in: previous.segments) {
                let delta = currentSegment.score.value - matchedPrevious.score.value
                segmentDeltas.append(SegmentDelta(
                    segmentID: currentSegment.id,
                    scoreDelta: delta,
                    previousSurface: matchedPrevious.score.surfaceType,
                    currentSurface: currentSegment.score.surfaceType
                ))
            }
        }

        return ComparisonResult(
            overallScoreDelta: scoreDelta,
            trend: trend,
            segmentDeltas: segmentDeltas,
            previousDate: previous.rideDate,
            currentDate: current.rideDate
        )
    }

    // MARK: - Private

    /// Find the segment in `candidates` whose midpoint is closest to `target`'s midpoint.
    private func findClosestSegment(to target: TrailSegment, in candidates: [TrailSegment]) -> TrailSegment? {
        let targetMid = midpoint(target.startCoordinate, target.endCoordinate)

        return candidates.min(by: { a, b in
            let midA = midpoint(a.startCoordinate, a.endCoordinate)
            let midB = midpoint(b.startCoordinate, b.endCoordinate)
            let distA = roughDistance(from: targetMid, to: midA)
            let distB = roughDistance(from: targetMid, to: midB)
            return distA < distB
        })
    }

    private func midpoint(_ a: Coordinate, _ b: Coordinate) -> Coordinate {
        Coordinate(
            latitude: (a.latitude + b.latitude) / 2,
            longitude: (a.longitude + b.longitude) / 2
        )
    }

    /// Cheap squared-distance for comparison purposes (no sqrt needed).
    private func roughDistance(from a: Coordinate, to b: Coordinate) -> Double {
        let dLat = a.latitude - b.latitude
        let dLon = a.longitude - b.longitude
        return dLat * dLat + dLon * dLon
    }
}

// MARK: - Supporting Types

public struct ComparisonResult: Sendable, Equatable {
    public let overallScoreDelta: Int
    public let trend: Trend
    public let segmentDeltas: [SegmentDelta]
    public let previousDate: Date
    public let currentDate: Date
}

public enum Trend: String, Sendable, Codable {
    case improving
    case stable
    case degrading

    public var displayName: String {
        rawValue.capitalized
    }
}

public struct SegmentDelta: Sendable, Equatable {
    public let segmentID: UUID
    public let scoreDelta: Int
    public let previousSurface: SurfaceType
    public let currentSurface: SurfaceType

    public var surfaceChanged: Bool {
        previousSurface != currentSurface
    }
}
