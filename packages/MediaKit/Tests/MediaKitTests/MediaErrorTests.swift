import XCTest
@testable import MediaKit

final class MediaErrorTests: XCTestCase {

    func test_allCasesConstructible_andHaveDescriptions() {
        let cases: [MediaError] = [
            .validation(.missingGPSData),
            .validation(.outsideGPSCorridor),
            .validation(.outsideTimeWindow),
            .validation(.unsupportedFormat),
            .validation(.fileTooLarge(maxBytes: 20_000_000)),
            .upload(NSError(domain: "test", code: 1)),
            .importFailed("PHAsset fetch returned nil"),
            .unauthorized,
            .networkUnavailable,
            .storageFull,
            .photoNotFound(s3Key: "photos/abc.heic"),
        ]

        for error in cases {
            // Each case should produce a non-empty description
            XCTAssertFalse(error.description.isEmpty, "Description for \(error) should not be empty")
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        // Verify specific descriptions
        XCTAssertTrue(MediaError.unauthorized.description.contains("denied"))
        XCTAssertTrue(MediaError.photoNotFound(s3Key: "x").description.contains("x"))
    }
}
