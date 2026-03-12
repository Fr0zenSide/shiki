import Foundation

/// Actor-based retry queue for failed media uploads.
/// Uses exponential backoff: baseDelay * 2^attempt (1s, 2s, 4s by default).
public actor BackgroundRetryQueue {

    private struct QueueItem {
        let uploadable: any MediaUploadable
        var retryCount: Int = 0
    }

    private let uploader: any MediaUploaderProtocol
    private let maxRetries: Int
    private let baseDelay: TimeInterval
    private var items: [QueueItem] = []

    public var pendingCount: Int {
        items.count
    }

    public init(
        uploader: any MediaUploaderProtocol,
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0
    ) {
        self.uploader = uploader
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
    }

    public func enqueue(_ uploadable: any MediaUploadable) {
        items.append(QueueItem(uploadable: uploadable))
    }

    /// Called when an upload exhausts all retries and is permanently dropped.
    public var onRetriesExhausted: (@Sendable (_ uploadable: any MediaUploadable) -> Void)?

    public func processQueue() async {
        for var item in items {
            var succeeded = false

            while item.retryCount < maxRetries {
                do {
                    _ = try await uploader.upload(item.uploadable) { _ in }
                    succeeded = true
                    break
                } catch {
                    item.retryCount += 1
                    if item.retryCount < maxRetries {
                        let delay = baseDelay * pow(2.0, Double(item.retryCount - 1))
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
            }

            if !succeeded {
                onRetriesExhausted?(item.uploadable)
            }
        }

        items = []
    }
}
