import Foundation

/// Accumulates ``GroundQualityScore`` readings and produces ``TrailSegment`` objects
/// when a distance or time threshold is reached.
public actor SegmentScorer {

    // MARK: - Configuration

    /// Distance in meters per segment.
    public let segmentDistance: Double

    // MARK: - State

    private var pendingScores: [GroundQualityScore] = []
    private var segmentStartCoordinate: Coordinate?
    private var segmentStartTime: Date?
    private var accumulatedDistance: Double = 0
    private var lastCoordinate: Coordinate?

    // MARK: - Init

    public init(segmentDistance: Double = 50) {
        self.segmentDistance = max(segmentDistance, 1)
    }

    // MARK: - Accumulation

    /// Add a quality score with its associated GPS coordinate.
    /// - Parameters:
    ///   - score: The quality score for this window.
    ///   - coordinate: GPS coordinate at the time of scoring.
    /// - Returns: A completed ``TrailSegment`` if the distance threshold was reached, otherwise nil.
    public func addScore(_ score: GroundQualityScore, coordinate: Coordinate) -> TrailSegment? {
        if segmentStartCoordinate == nil {
            segmentStartCoordinate = coordinate
            segmentStartTime = score.timestamp
        }

        pendingScores.append(score)

        // Accumulate distance from last known coordinate.
        if let last = lastCoordinate {
            accumulatedDistance += haversineDistance(from: last, to: coordinate)
        }
        lastCoordinate = coordinate

        // Emit segment when distance threshold is reached.
        guard accumulatedDistance >= segmentDistance else { return nil }

        return finaliseSegment(endCoordinate: coordinate, endTime: score.timestamp)
    }

    /// Force-close the current segment (e.g. at ride end). Returns nil if no data accumulated.
    public func finaliseCurrentSegment() -> TrailSegment? {
        guard let endCoordinate = lastCoordinate else { return nil }
        return finaliseSegment(endCoordinate: endCoordinate, endTime: .now)
    }

    /// Reset scorer state for a new ride.
    public func reset() {
        pendingScores.removeAll()
        segmentStartCoordinate = nil
        segmentStartTime = nil
        accumulatedDistance = 0
        lastCoordinate = nil
    }

    // MARK: - Private

    private func finaliseSegment(endCoordinate: Coordinate, endTime: Date) -> TrailSegment? {
        guard
            let startCoord = segmentStartCoordinate,
            let startTime = segmentStartTime,
            !pendingScores.isEmpty
        else { return nil }

        // Compute weighted average score.
        let avgValue = pendingScores.reduce(0) { $0 + $1.value } / pendingScores.count
        let avgConfidence = pendingScores.reduce(0.0) { $0 + $1.confidence } / Double(pendingScores.count)

        // Dominant surface type by frequency.
        let surfaceCounts = Dictionary(grouping: pendingScores, by: \.surfaceType)
            .mapValues(\.count)
        let dominantSurface = surfaceCounts.max(by: { $0.value < $1.value })?.key ?? .smooth

        let aggregateScore = GroundQualityScore(
            value: avgValue,
            confidence: avgConfidence,
            surfaceType: dominantSurface,
            timestamp: endTime
        )

        let segment = TrailSegment(
            score: aggregateScore,
            startCoordinate: startCoord,
            endCoordinate: endCoordinate,
            startTimestamp: startTime,
            endTimestamp: endTime,
            distanceMeters: accumulatedDistance,
            sampleCount: pendingScores.count
        )

        // Reset for next segment.
        pendingScores.removeAll()
        segmentStartCoordinate = endCoordinate
        segmentStartTime = endTime
        accumulatedDistance = 0

        return segment
    }

    // MARK: - Haversine

    private func haversineDistance(from a: Coordinate, to b: Coordinate) -> Double {
        let earthRadius = 6_371_000.0 // meters
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180

        let sinDLat = sin(dLat / 2)
        let sinDLon = sin(dLon / 2)
        let h = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLon * sinDLon
        let c = 2 * atan2(h.squareRoot(), (1 - h).squareRoot())

        return earthRadius * c
    }
}
