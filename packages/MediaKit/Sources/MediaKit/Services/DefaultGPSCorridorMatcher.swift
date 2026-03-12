import Foundation

public struct DefaultGPSCorridorMatcher: GPSCorridorMatcher, Sendable {

    public init() {}

    public func isWithinCorridor(_ metadata: PhotoMetadata, config: CorridorConfig) -> Bool {
        guard let lat = metadata.latitude, let lon = metadata.longitude else {
            return false
        }

        for point in config.routeCoordinates {
            let distance = HaversineCalculator.distance(
                lat1: lat, lon1: lon,
                lat2: point.latitude, lon2: point.longitude
            )
            if distance <= config.corridorWidthMeters {
                return true
            }
        }
        return false
    }

    public func isWithinTimeWindow(_ metadata: PhotoMetadata, config: CorridorConfig) -> Bool {
        guard let capturedAt = metadata.capturedAt else {
            // If no capture date, we can't validate time — treat as valid
            return true
        }

        let windowStart = config.sessionStart.addingTimeInterval(-config.timeBufferSeconds)
        let windowEnd = config.sessionEnd.addingTimeInterval(config.timeBufferSeconds)

        return capturedAt >= windowStart && capturedAt <= windowEnd
    }

    public func validate(_ metadata: PhotoMetadata, config: CorridorConfig) throws {
        guard metadata.latitude != nil, metadata.longitude != nil else {
            throw MediaValidationError.missingGPSData
        }

        guard isWithinCorridor(metadata, config: config) else {
            throw MediaValidationError.outsideGPSCorridor
        }

        guard isWithinTimeWindow(metadata, config: config) else {
            throw MediaValidationError.outsideTimeWindow
        }
    }
}
