import XCTest
@testable import MediaKit

final class MediaUploaderTests: XCTestCase {

    private var sut: StubMediaUploader!

    override func setUp() {
        super.setUp()
        sut = StubMediaUploader()
    }

    // MARK: - Test helper

    private func makeUploadable() -> TestUploadable {
        TestUploadable(
            data: Data("test-image".utf8),
            mimeType: .jpeg,
            metadata: PhotoMetadata(latitude: 48.8566, longitude: 2.3522),
            bucket: .mayaPhotos
        )
    }

    // MARK: - Tests

    func test_upload_returnsResult() async throws {
        let uploadable = makeUploadable()
        let result = try await sut.upload(uploadable) { _ in }

        XCTAssertFalse(result.s3Key.isEmpty, "Upload should return a non-empty s3Key")
        XCTAssertEqual(result.bucket, .mayaPhotos)
    }

    func test_upload_progressCallbackFires() async throws {
        let uploadable = makeUploadable()
        nonisolated(unsafe) var progressUpdates: [UploadProgress] = []

        _ = try await sut.upload(uploadable) { progress in
            progressUpdates.append(progress)
        }

        XCTAssertFalse(progressUpdates.isEmpty, "Progress callback should fire at least once")
        let lastFraction = try XCTUnwrap(progressUpdates.last?.fraction)
        XCTAssertEqual(lastFraction, 1.0, accuracy: 0.01)
    }

    func test_upload_cancelledUploader_throws() async {
        let uploadable = makeUploadable()
        sut.shouldFail = true

        do {
            _ = try await sut.upload(uploadable) { _ in }
            XCTFail("Should have thrown")
        } catch {
            // Expected
            XCTAssertTrue(error is StubMediaUploader.UploadError)
        }
    }
}

// MARK: - Test doubles

struct TestUploadable: MediaUploadable {
    let data: Data
    let mimeType: MIMEType
    let metadata: PhotoMetadata
    let bucket: MediaBucket
}
