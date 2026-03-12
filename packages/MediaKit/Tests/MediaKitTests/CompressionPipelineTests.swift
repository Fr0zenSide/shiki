import XCTest
import ImageIO
import CoreGraphics
@testable import MediaKit

final class CompressionPipelineTests: XCTestCase {

    private var sut: CompressionPipeline!

    override func setUp() {
        super.setUp()
        sut = CompressionPipeline()
    }

    // MARK: - Helpers

    private func fixtureData(named filename: String) throws -> Data {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures") else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture \(filename) not found"])
        }
        return try Data(contentsOf: url)
    }

    /// Creates a large uncompressed JPEG for testing compression.
    private func makeLargeJPEG() -> Data {
        let width = 200
        let height = 200
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

        // Write at quality 1.0 to make it larger
        let options: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: 1.0,
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        CGImageDestinationFinalize(destination)

        return mutableData as Data
    }

    private func makePNG() -> Data {
        let width = 100
        let height = 100
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
            "public.png" as CFString,
            1,
            nil
        ) else {
            return Data()
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)

        return mutableData as Data
    }

    // MARK: - Tests

    func test_compress_HEICPassthrough() throws {
        let heicData = try fixtureData(named: "test-photo-sample.heic")
        let compressed = sut.compress(heicData, mimeType: .heic)

        // HEIC should pass through unchanged
        XCTAssertEqual(compressed, heicData, "HEIC data should pass through without recompression")
    }

    func test_compress_JPEGReducesSize() {
        let jpegData = makeLargeJPEG()
        let compressed = sut.compress(jpegData, mimeType: .jpeg)

        // Compressed output should be non-empty and not larger
        XCTAssertFalse(compressed.isEmpty)
        XCTAssertLessThanOrEqual(compressed.count, jpegData.count,
            "Compressed JPEG (\(compressed.count)B) should not exceed original (\(jpegData.count)B)")
    }

    func test_compress_PNGProducesCompressedOutput() {
        let pngData = makePNG()
        let compressed = sut.compress(pngData, mimeType: .png)

        // Should produce non-empty output
        XCTAssertFalse(compressed.isEmpty, "PNG compression should produce output")
    }
}
