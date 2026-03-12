import Foundation

/// Model for displaying photo pins on a map.
public struct PhotoPinAnnotation: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let latitude: Double
    public let longitude: Double
    public let thumbnailData: Data?
    public let capturedAt: Date
    public let s3Key: String?

    public init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        thumbnailData: Data? = nil,
        capturedAt: Date,
        s3Key: String? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.thumbnailData = thumbnailData
        self.capturedAt = capturedAt
        self.s3Key = s3Key
    }
}
