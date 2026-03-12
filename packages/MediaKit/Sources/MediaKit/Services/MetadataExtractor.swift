import Foundation
import ImageIO
import CoreGraphics

public struct MetadataExtractor: Sendable {

    public init() {}

    public func extract(from data: Data) -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return PhotoMetadata()
        }

        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        // GPS extraction
        let latitude = extractLatitude(from: gps)
        let longitude = extractLongitude(from: gps)
        let altitude = gps?[kCGImagePropertyGPSAltitude as String] as? Double

        // Date extraction from EXIF
        let capturedAt = extractDate(from: exif)

        // Camera model from TIFF
        let cameraModel = tiff?[kCGImagePropertyTIFFModel as String] as? String

        return PhotoMetadata(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            capturedAt: capturedAt,
            cameraModel: cameraModel
        )
    }

    // MARK: - Private

    private func extractLatitude(from gps: [String: Any]?) -> Double? {
        guard let gps,
              let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let ref = gps[kCGImagePropertyGPSLatitudeRef as String] as? String else {
            return nil
        }
        return ref == "S" ? -lat : lat
    }

    private func extractLongitude(from gps: [String: Any]?) -> Double? {
        guard let gps,
              let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
              let ref = gps[kCGImagePropertyGPSLongitudeRef as String] as? String else {
            return nil
        }
        return ref == "W" ? -lon : lon
    }

    private func extractDate(from exif: [String: Any]?) -> Date? {
        guard let dateString = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }
}
