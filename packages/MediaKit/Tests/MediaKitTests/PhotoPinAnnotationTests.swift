import XCTest
@testable import MediaKit

final class PhotoPinAnnotationTests: XCTestCase {

    func test_creation_andIdentifiableConformance() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)

        let pin = PhotoPinAnnotation(
            id: id,
            latitude: 48.8566,
            longitude: 2.3522,
            thumbnailData: Data([0xFF]),
            capturedAt: date,
            s3Key: "photos/test.heic"
        )

        XCTAssertEqual(pin.id, id)
        XCTAssertEqual(pin.latitude, 48.8566)
        XCTAssertEqual(pin.longitude, 2.3522)
        XCTAssertEqual(pin.thumbnailData, Data([0xFF]))
        XCTAssertEqual(pin.capturedAt, date)
        XCTAssertEqual(pin.s3Key, "photos/test.heic")

        // Identifiable: id is non-nil and unique
        let pin2 = PhotoPinAnnotation(latitude: 35.0, longitude: 139.0, capturedAt: date)
        XCTAssertNotEqual(pin.id, pin2.id)

        // Hashable
        let set: Set<PhotoPinAnnotation> = [pin, pin2]
        XCTAssertEqual(set.count, 2)
    }
}
