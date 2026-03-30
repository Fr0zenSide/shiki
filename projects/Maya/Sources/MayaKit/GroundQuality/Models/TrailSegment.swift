import Foundation

/// A scored segment of trail, representing quality data over a fixed distance or time window.
public struct TrailSegment: Sendable, Codable, Identifiable, Equatable {

    public let id: UUID
    public let score: GroundQualityScore
    public let startCoordinate: Coordinate
    public let endCoordinate: Coordinate
    public let startTimestamp: Date
    public let endTimestamp: Date
    public let distanceMeters: Double
    public let sampleCount: Int

    public init(
        id: UUID = UUID(),
        score: GroundQualityScore,
        startCoordinate: Coordinate,
        endCoordinate: Coordinate,
        startTimestamp: Date,
        endTimestamp: Date,
        distanceMeters: Double,
        sampleCount: Int
    ) {
        self.id = id
        self.score = score
        self.startCoordinate = startCoordinate
        self.endCoordinate = endCoordinate
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.distanceMeters = distanceMeters
        self.sampleCount = sampleCount
    }
}
