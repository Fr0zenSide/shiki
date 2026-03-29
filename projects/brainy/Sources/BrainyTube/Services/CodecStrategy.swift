import BrainyCore
import Foundation

/// Builds yt-dlp format and sort strings based on codec preference and quality settings.
public struct CodecStrategy: Sendable {

    // MARK: - Format String

    /// Builds the `-f` format string for yt-dlp.
    ///
    /// When ffmpeg is available, requests separate video+audio streams with merge.
    /// Without ffmpeg, falls back to pre-merged formats only.
    public static func formatString(
        quality: VideoQuality,
        codec: VideoCodecPreference,
        hasFfmpeg: Bool
    ) -> String {
        guard hasFfmpeg else {
            return "b"
        }

        if let height = quality.heightLimit {
            return "bv*[height<=\(height)]+ba/b"
        }
        return "bv*+ba/b"
    }

    /// Builds the `-S` sort string for yt-dlp.
    ///
    /// In `.native` mode, tells yt-dlp to prefer AV1 then H.264, effectively
    /// skipping VP9 unless nothing else is available.
    /// In `.universal` mode, returns `nil` (no sort preference).
    public static func sortString(codec: VideoCodecPreference) -> String? {
        switch codec {
        case .native:
            return "vcodec:av01,vcodec:avc1"
        case .universal:
            return nil
        }
    }

    /// Builds the complete set of yt-dlp arguments for downloading.
    public static func downloadArguments(
        quality: VideoQuality,
        codec: VideoCodecPreference,
        hasFfmpeg: Bool
    ) -> [String] {
        var args: [String] = []

        // Sort preference (codec selection)
        if let sort = sortString(codec: codec) {
            args.append(contentsOf: ["-S", sort])
        }

        // Format string
        let format = formatString(quality: quality, codec: codec, hasFfmpeg: hasFfmpeg)
        args.append(contentsOf: ["-f", format])

        // Merge output format (only when ffmpeg is available)
        if hasFfmpeg {
            args.append(contentsOf: ["--merge-output-format", "mp4"])
        }

        return args
    }
}
