import Foundation

/// Protocol for deleting uploaded photos (both remote S3 and local reference).
public protocol PhotoDeletionService: Sendable {
    func delete(s3Key: String, from bucket: MediaBucket) async throws
}

/// Stub implementation for development/testing.
/// Actual S3 deletion will come with PocketBase integration.
public final class StubPhotoDeletionService: PhotoDeletionService, @unchecked Sendable {

    public private(set) var deletedKeys: [String] = []

    public init() {}

    public func delete(s3Key: String, from bucket: MediaBucket) async throws {
        deletedKeys.append(s3Key)
    }
}
