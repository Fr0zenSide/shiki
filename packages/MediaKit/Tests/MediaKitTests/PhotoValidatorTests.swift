import XCTest
@testable import MediaKit

final class PhotoValidatorTests: XCTestCase {

    private var sut: PhotoValidator!

    override func setUp() {
        super.setUp()
        sut = PhotoValidator()
    }

    func test_validate_validPhoto_passes() throws {
        let data = Data(repeating: 0xFF, count: 1024)
        let metadata = PhotoMetadata(latitude: 48.8566, longitude: 2.3522)

        XCTAssertNoThrow(
            try sut.validate(data, metadata: metadata, mimeType: .heic)
        )
    }

    func test_validate_oversizedFile_throws() {
        let maxBytes = PhotoValidator.maxFileSizeBytes
        let data = Data(repeating: 0xFF, count: Int(maxBytes) + 1)
        let metadata = PhotoMetadata(latitude: 48.8566, longitude: 2.3522)

        XCTAssertThrowsError(try sut.validate(data, metadata: metadata, mimeType: .heic)) { error in
            guard let validationError = error as? MediaValidationError else {
                XCTFail("Expected MediaValidationError")
                return
            }
            if case .fileTooLarge(let max) = validationError {
                XCTAssertEqual(max, maxBytes)
            } else {
                XCTFail("Expected fileTooLarge, got \(validationError)")
            }
        }
    }

    func test_validate_missingGPS_throws() {
        let data = Data(repeating: 0xFF, count: 1024)
        let metadata = PhotoMetadata() // no GPS

        XCTAssertThrowsError(try sut.validate(data, metadata: metadata, mimeType: .heic)) { error in
            XCTAssertEqual(error as? MediaValidationError, .missingGPSData)
        }
    }
}
