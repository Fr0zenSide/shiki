import Foundation

public protocol GPSCorridorMatcher: Sendable {
    func isWithinCorridor(_ metadata: PhotoMetadata, config: CorridorConfig) -> Bool
    func isWithinTimeWindow(_ metadata: PhotoMetadata, config: CorridorConfig) -> Bool
    func validate(_ metadata: PhotoMetadata, config: CorridorConfig) throws
}
