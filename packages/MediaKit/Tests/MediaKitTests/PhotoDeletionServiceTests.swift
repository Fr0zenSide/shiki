import XCTest
@testable import MediaKit

final class PhotoDeletionServiceTests: XCTestCase {

    func test_stubDelete_doesNotCrash() async throws {
        let sut = StubPhotoDeletionService()

        // Should not throw
        try await sut.delete(s3Key: "photos/test-123.heic", from: .mayaPhotos)

        XCTAssertEqual(sut.deletedKeys, ["photos/test-123.heic"])
    }
}
