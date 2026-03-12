import Foundation

/// Protocol for uploading media items (photos) to remote storage.
public protocol MediaUploaderProtocol: Sendable {
    func upload(
        _ uploadable: MediaUploadable,
        progress: @Sendable (UploadProgress) -> Void
    ) async throws -> UploadResult
}

/// Stub implementation for development/testing. Will be replaced with PocketBase API integration.
public final class StubMediaUploader: MediaUploaderProtocol, @unchecked Sendable {

    public enum UploadError: Error {
        case cancelled
    }

    public var shouldFail: Bool = false

    public init() {}

    public func upload(
        _ uploadable: MediaUploadable,
        progress: @Sendable (UploadProgress) -> Void
    ) async throws -> UploadResult {
        if shouldFail {
            throw UploadError.cancelled
        }

        let totalBytes = Int64(uploadable.data.count)

        // Simulate progress
        progress(UploadProgress(bytesUploaded: totalBytes / 2, totalBytes: totalBytes))
        progress(UploadProgress(bytesUploaded: totalBytes, totalBytes: totalBytes))

        return UploadResult(
            s3Key: "stub/\(UUID().uuidString)",
            bucket: uploadable.bucket,
            eTag: "\"stub-etag\""
        )
    }
}
