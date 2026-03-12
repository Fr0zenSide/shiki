import Foundation

public struct PhotoValidator: Sendable {

    /// 20 MB
    public static let maxFileSizeBytes: Int64 = 20 * 1024 * 1024

    public init() {}

    public func validate(_ data: Data, metadata: PhotoMetadata, mimeType: MIMEType) throws {
        // Check file size
        if data.count > Int(Self.maxFileSizeBytes) {
            throw MediaValidationError.fileTooLarge(maxBytes: Self.maxFileSizeBytes)
        }

        // Check GPS data presence
        guard metadata.latitude != nil, metadata.longitude != nil else {
            throw MediaValidationError.missingGPSData
        }
    }
}
