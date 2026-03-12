import Foundation

public struct CorridorConfig: Sendable {
    public let routeCoordinates: [(latitude: Double, longitude: Double)]
    public let corridorWidthMeters: Double
    public let sessionStart: Date
    public let sessionEnd: Date
    public let timeBufferSeconds: TimeInterval

    public init(
        routeCoordinates: [(latitude: Double, longitude: Double)],
        corridorWidthMeters: Double = 100,
        sessionStart: Date,
        sessionEnd: Date,
        timeBufferSeconds: TimeInterval = 300
    ) {
        self.routeCoordinates = routeCoordinates
        self.corridorWidthMeters = corridorWidthMeters
        self.sessionStart = sessionStart
        self.sessionEnd = sessionEnd
        self.timeBufferSeconds = timeBufferSeconds
    }
}
