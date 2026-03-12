import Foundation

public struct UploadProgress: Sendable, Hashable {
    public let bytesUploaded: Int64
    public let totalBytes: Int64

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesUploaded) / Double(totalBytes)
    }

    public init(bytesUploaded: Int64, totalBytes: Int64) {
        self.bytesUploaded = bytesUploaded
        self.totalBytes = totalBytes
    }
}
