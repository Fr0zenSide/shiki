import XCTest
@testable import MediaKit

final class FailedUploadManagerTests: XCTestCase {

    private struct MockUploadable: MediaUploadable {
        let data: Data
        let mimeType: MIMEType
        let metadata: PhotoMetadata
        let bucket: MediaBucket
    }

    func test_record_addsToList() async {
        let sut = FailedUploadManager()
        let uploadable = MockUploadable(
            data: Data([0xFF]),
            mimeType: .jpeg,
            metadata: PhotoMetadata(latitude: 48.0, longitude: 2.0),
            bucket: .mayaPhotos
        )

        await sut.record(
            uploadable: uploadable,
            error: NSError(domain: "test", code: 1)
        )

        let uploads = await sut.failedUploads
        XCTAssertEqual(uploads.count, 1)
        XCTAssertEqual(uploads.first?.retryCount, 0)
    }

    func test_remove_clearsEntry() async {
        let sut = FailedUploadManager()
        let uploadable = MockUploadable(
            data: Data([0xFF]),
            mimeType: .jpeg,
            metadata: PhotoMetadata(latitude: 48.0, longitude: 2.0),
            bucket: .mayaPhotos
        )

        await sut.record(
            uploadable: uploadable,
            error: NSError(domain: "test", code: 1)
        )

        let uploads = await sut.failedUploads
        XCTAssertEqual(uploads.count, 1)

        let id = uploads.first!.id
        await sut.remove(id: id)

        let remaining = await sut.failedUploads
        XCTAssertTrue(remaining.isEmpty)
    }
}
