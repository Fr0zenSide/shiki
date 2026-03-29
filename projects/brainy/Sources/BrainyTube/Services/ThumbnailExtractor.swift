import AppKit
import AVFoundation
import BrainyCore
import Foundation

/// Extracts JPEG thumbnail frames from video files using AVAssetImageGenerator.
///
/// Eliminates the need for multiple live AVPlayer instances in grid mode.
/// Each thumbnail is stored alongside the video at `{videoId}/thumbnail.jpg`.
public struct ThumbnailExtractor: Sendable {

    /// Default thumbnail dimensions — sufficient for grid cells, small file size.
    public static let defaultMaxSize = CGSize(width: 640, height: 360)

    /// Default JPEG compression quality.
    public static let defaultCompression: Double = 0.85

    // MARK: - Single Extraction

    /// Extract a single frame from a video at a relative position (0.0-1.0).
    ///
    /// - Parameters:
    ///   - videoURL: Local file URL of the video.
    ///   - relativePosition: Position in the video (0.0 = start, 1.0 = end). Defaults to 0.1.
    ///   - maxSize: Maximum thumbnail dimensions. Defaults to 640x360.
    /// - Returns: The extracted frame as an NSImage.
    public static func extractThumbnail(
        from videoURL: URL,
        at relativePosition: Double = 0.1,
        maxSize: CGSize = defaultMaxSize
    ) async throws -> NSImage {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            throw ThumbnailError.invalidDuration
        }

        let targetTime = CMTime(
            seconds: durationSeconds * relativePosition,
            preferredTimescale: 600
        )

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize

        let (cgImage, _) = try await generator.image(at: targetTime)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Save

    /// Save an NSImage as a JPEG file.
    ///
    /// - Parameters:
    ///   - image: The image to save.
    ///   - directory: Directory to write the file into.
    ///   - filename: Output filename. Defaults to "thumbnail.jpg".
    ///   - compressionFactor: JPEG quality (0.0-1.0). Defaults to 0.85.
    /// - Returns: The URL of the saved JPEG file.
    @discardableResult
    public static func saveThumbnail(
        _ image: NSImage,
        to directory: URL,
        filename: String = "thumbnail.jpg",
        compressionFactor: Double = defaultCompression
    ) throws -> URL {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: compressionFactor]
              )
        else {
            throw ThumbnailError.encodingFailed
        }

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let fileURL = directory.appendingPathComponent(filename)
        try jpegData.write(to: fileURL)
        return fileURL
    }

    // MARK: - Batch Extraction

    /// Extract thumbnails for videos that have a video file but no thumbnail.
    ///
    /// Runs concurrently with limited parallelism to avoid GPU contention.
    /// - Parameters:
    ///   - videos: The full list of videos to check.
    ///   - videosDirectory: Root directory containing `{videoId}/` subdirectories.
    /// - Returns: A dictionary mapping video ID to the generated thumbnail URL.
    public static func extractMissing(
        videos: [Video],
        videosDirectory: URL
    ) async -> [String: URL] {
        let candidates = videos.filter { video in
            video.videoPath != nil && video.thumbnailPath == nil
        }

        guard !candidates.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, URL?).self) { group in
            for video in candidates {
                group.addTask {
                    guard let videoPath = video.videoPath else { return (video.id, nil) }
                    let videoURL = videosDirectory.appendingPathComponent(videoPath)
                    let thumbDir = videosDirectory.appendingPathComponent(video.id)

                    do {
                        let image = try await extractThumbnail(from: videoURL)
                        let url = try saveThumbnail(image, to: thumbDir)
                        return (video.id, url)
                    } catch {
                        return (video.id, nil)
                    }
                }
            }

            var results: [String: URL] = [:]
            for await (videoId, url) in group {
                if let url {
                    results[videoId] = url
                }
            }
            return results
        }
    }
}

// MARK: - Errors

public enum ThumbnailError: Error, Sendable {
    case invalidDuration
    case encodingFailed
    case extractionFailed(String)
}
