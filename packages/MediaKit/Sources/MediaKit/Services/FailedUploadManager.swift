import Foundation

/// Actor that tracks failed uploads for retry UI display.
public actor FailedUploadManager {

    public struct FailedUpload: Sendable, Identifiable {
        public let id: UUID
        public let uploadable: any MediaUploadable
        public let error: any Error
        public let failedAt: Date
        public var retryCount: Int

        public init(
            id: UUID = UUID(),
            uploadable: any MediaUploadable,
            error: any Error,
            failedAt: Date = Date(),
            retryCount: Int = 0
        ) {
            self.id = id
            self.uploadable = uploadable
            self.error = error
            self.failedAt = failedAt
            self.retryCount = retryCount
        }
    }

    private var items: [FailedUpload] = []

    public var failedUploads: [FailedUpload] {
        items
    }

    public init() {}

    public func record(uploadable: any MediaUploadable, error: any Error) {
        items.append(FailedUpload(uploadable: uploadable, error: error))
    }

    public func retry(id: UUID, using uploader: any MediaUploaderProtocol) async throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        items[index].retryCount += 1

        _ = try await uploader.upload(item.uploadable) { _ in }

        // If upload succeeds, remove from list
        items.removeAll { $0.id == id }
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }
}
