import XCTest
@testable import MediaKit

final class CameraCaptureServiceTests: XCTestCase {

    func test_capturedPhoto_conformsToSendable() {
        // Compile-time check: CapturedPhoto is Sendable.
        // If this compiles, Sendable conformance is verified.
        let photo = CapturedPhoto(
            imageData: Data([0xFF, 0xD8]),
            metadata: PhotoMetadata(latitude: 35.6762, longitude: 139.6503),
            mimeType: .jpeg
        )

        // Transfer across isolation boundary
        let sendableRef: any Sendable = photo
        XCTAssertNotNil(sendableRef)
    }

    func test_capturedPhoto_storesCorrectData() {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let metadata = PhotoMetadata(
            latitude: 48.8566,
            longitude: 2.3522,
            capturedAt: Date(timeIntervalSince1970: 1_000_000)
        )

        let photo = CapturedPhoto(
            imageData: imageData,
            metadata: metadata,
            mimeType: .heic
        )

        XCTAssertEqual(photo.imageData, imageData)
        XCTAssertEqual(photo.metadata.latitude, 48.8566)
        XCTAssertEqual(photo.metadata.longitude, 2.3522)
        XCTAssertEqual(photo.mimeType, .heic)
    }
}
