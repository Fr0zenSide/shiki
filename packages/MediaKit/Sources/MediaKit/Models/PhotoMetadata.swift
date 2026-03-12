import Foundation

public struct PhotoMetadata: Sendable, Hashable, Codable {
    public let latitude: Double?
    public let longitude: Double?
    public let altitude: Double?
    public let capturedAt: Date?
    public let cameraModel: String?
    public let originalFilename: String?

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        capturedAt: Date? = nil,
        cameraModel: String? = nil,
        originalFilename: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.capturedAt = capturedAt
        self.cameraModel = cameraModel
        self.originalFilename = originalFilename
    }
}
