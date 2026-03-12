import XCTest
@testable import MediaKit

final class BackgroundRetryQueueTests: XCTestCase {

    // MARK: - Tests

    func test_enqueue_increasesCount() async {
        let uploader = StubMediaUploader()
        let sut = BackgroundRetryQueue(uploader: uploader)

        let item = TestUploadable(
            data: Data("test".utf8),
            mimeType: .jpeg,
            metadata: PhotoMetadata(latitude: 48.8, longitude: 2.3),
            bucket: .mayaPhotos
        )

        await sut.enqueue(item)
        let count = await sut.pendingCount

        XCTAssertEqual(count, 1)
    }

    func test_failedUpload_retries() async throws {
        let uploader = StubMediaUploader()
        uploader.shouldFail = true

        let sut = BackgroundRetryQueue(uploader: uploader, maxRetries: 3, baseDelay: 0.01)

        let item = TestUploadable(
            data: Data("test".utf8),
            mimeType: .jpeg,
            metadata: PhotoMetadata(latitude: 48.8, longitude: 2.3),
            bucket: .mayaPhotos
        )

        await sut.enqueue(item)
        await sut.processQueue()

        // After processing with failures, queue should be drained (max retries exhausted)
        let count = await sut.pendingCount
        XCTAssertEqual(count, 0, "Queue should be empty after max retries exhausted")
    }
}
