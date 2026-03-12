import Foundation
import ImageIO
import CoreGraphics
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public struct CompressionPipeline: Sendable {

    public init() {}

    /// Compresses image data. HEIC passes through (already compressed).
    /// JPEG/PNG are re-encoded to HEIC if available, otherwise JPEG at 0.8 quality.
    public func compress(_ data: Data, mimeType: MIMEType) -> Data {
        switch mimeType {
        case .heic:
            // HEIC is already well-compressed; pass through
            return data

        case .jpeg, .png:
            return recompress(data)
        }
    }

    // MARK: - Private

    private func recompress(_ data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return data
        }

        // Try HEIC first
        if let heicData = encode(cgImage, type: "public.heic", quality: 0.8) {
            return heicData
        }

        // Fallback to JPEG 0.8
        if let jpegData = encode(cgImage, type: "public.jpeg", quality: 0.8) {
            return jpegData
        }

        // If all else fails, return original
        return data
    }

    private func encode(_ image: CGImage, type: String, quality: Double) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            type as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: quality,
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }
}
