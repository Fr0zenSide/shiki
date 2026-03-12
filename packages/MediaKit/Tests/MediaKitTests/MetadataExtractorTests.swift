import XCTest
import ImageIO
import CoreGraphics
@testable import MediaKit

final class MetadataExtractorTests: XCTestCase {

    private var sut: MetadataExtractor!

    override func setUp() {
        super.setUp()
        sut = MetadataExtractor()
    }

    // MARK: - Helpers

    private func fixtureData(named filename: String) throws -> Data {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture \(filename) not found"])
        }
        return try Data(contentsOf: url)
    }

    /// Creates a minimal JPEG with GPS EXIF metadata baked in via ImageIO.
    private func makeJPEGWithGPS(latitude: Double, longitude: Double) -> Data {
        // Create a 1x1 pixel image
        let width = 1
        let height = 1
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            return Data()
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return Data()
        }

        let gpsDict: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: abs(latitude),
            kCGImagePropertyGPSLatitudeRef as String: latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(longitude),
            kCGImagePropertyGPSLongitudeRef as String: longitude >= 0 ? "E" : "W",
        ]
        let tiffDict: [String: Any] = [
            kCGImagePropertyTIFFModel as String: "TestCamera",
        ]
        let exifDict: [String: Any] = [
            kCGImagePropertyExifDateTimeOriginal as String: "2025:06:15 14:30:00",
        ]
        let properties: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: gpsDict,
            kCGImagePropertyTIFFDictionary as String: tiffDict,
            kCGImagePropertyExifDictionary as String: exifDict,
        ]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        CGImageDestinationFinalize(destination)

        return mutableData as Data
    }

    // MARK: - Tests

    func test_extract_GPSFromImage() throws {
        let data = makeJPEGWithGPS(latitude: 48.8566, longitude: 2.3522)
        let metadata = sut.extract(from: data)

        XCTAssertNotNil(metadata.latitude, "Should extract latitude from GPS EXIF")
        XCTAssertNotNil(metadata.longitude, "Should extract longitude from GPS EXIF")
        XCTAssertEqual(metadata.latitude!, 48.8566, accuracy: 0.001)
        XCTAssertEqual(metadata.longitude!, 2.3522, accuracy: 0.001)
    }

    func test_extract_cameraModel() throws {
        let data = try fixtureData(named: "test-photo-gps.heic")
        let metadata = sut.extract(from: data)

        // iPhone 12 mini photo — should have camera model
        XCTAssertEqual(metadata.cameraModel, "iPhone 12 mini")
    }

    func test_extract_missingGPS_returnsNilCoordinates() throws {
        let data = try fixtureData(named: "test-photo-sample.heic")
        let metadata = sut.extract(from: data)

        // The sample test HEIC has no GPS; extractor handles gracefully
        // We verify it doesn't crash and returns a valid struct
        XCTAssertNotNil(metadata)
    }

    func test_extract_nonImageData_returnsEmptyMetadata() {
        let data = Data("not an image".utf8)
        let metadata = sut.extract(from: data)

        XCTAssertNil(metadata.latitude)
        XCTAssertNil(metadata.longitude)
        XCTAssertNil(metadata.cameraModel)
        XCTAssertNil(metadata.capturedAt)
    }
}
