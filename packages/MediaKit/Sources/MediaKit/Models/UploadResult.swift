import Foundation

public struct UploadResult: Sendable, Hashable, Codable {
    public let s3Key: String
    public let bucket: MediaBucket
    public let eTag: String?

    public init(s3Key: String, bucket: MediaBucket, eTag: String? = nil) {
        self.s3Key = s3Key
        self.bucket = bucket
        self.eTag = eTag
    }
}
