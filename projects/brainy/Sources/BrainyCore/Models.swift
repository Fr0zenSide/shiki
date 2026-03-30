import Foundation

// MARK: - Video Quality

public enum VideoQuality: String, Codable, CaseIterable, Sendable {
    case best
    case hd1080 = "1080p"
    case hd720 = "720p"
    case sd480 = "480p"

    public var heightLimit: Int? {
        switch self {
        case .best: nil
        case .hd1080: 1080
        case .hd720: 720
        case .sd480: 480
        }
    }
}

// MARK: - Codec Preference

public enum VideoCodecPreference: String, Codable, CaseIterable, Sendable {
    /// AV1 + H.264 only — AVPlayer hardware decode
    case native
    /// Adds VP9 via software decode fallback
    case universal
}

// MARK: - Video Format Info

public struct VideoFormatInfo: Codable, Equatable, Sendable {
    public let resolution: String
    public let codec: String
    public let fileSize: Int64?
    public let formatId: String

    public init(resolution: String, codec: String, fileSize: Int64?, formatId: String) {
        self.resolution = resolution
        self.codec = codec
        self.fileSize = fileSize
        self.formatId = formatId
    }

    public var displayLabel: String {
        var label = "\(resolution) \(codec.uppercased())"
        if let size = fileSize {
            let megabytes = Double(size) / 1_048_576
            label += " (~\(Int(megabytes)) MB)"
        }
        return label
    }
}

// MARK: - Video Metadata

public struct VideoMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var duration: TimeInterval
    public var channelName: String?
    public var uploadDate: String?
    public var availableFormats: [VideoFormatInfo]

    public init(
        title: String,
        duration: TimeInterval,
        channelName: String? = nil,
        uploadDate: String? = nil,
        availableFormats: [VideoFormatInfo] = []
    ) {
        self.title = title
        self.duration = duration
        self.channelName = channelName
        self.uploadDate = uploadDate
        self.availableFormats = availableFormats
    }
}

// MARK: - Video

public struct Video: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var url: String
    public var metadata: VideoMetadata?
    public var videoPath: String?
    public var thumbnailPath: String?
    public var codecPreference: VideoCodecPreference
    public var detectedCodec: String?

    public init(
        id: String,
        url: String,
        metadata: VideoMetadata? = nil,
        videoPath: String? = nil,
        thumbnailPath: String? = nil,
        codecPreference: VideoCodecPreference = .native,
        detectedCodec: String? = nil
    ) {
        self.id = id
        self.url = url
        self.metadata = metadata
        self.videoPath = videoPath
        self.thumbnailPath = thumbnailPath
        self.codecPreference = codecPreference
        self.detectedCodec = detectedCodec
    }
}

// MARK: - Region / Geo-bypass

public enum GeoBypassCountry: String, Codable, CaseIterable, Sendable {
    case none = ""
    case us = "US"
    case uk = "GB"
    case jp = "JP"
    case kr = "KR"
    case de = "DE"
    case fr = "FR"
    case ca = "CA"
    case au = "AU"

    public var label: String {
        switch self {
        case .none: "None"
        case .us: "United States"
        case .uk: "United Kingdom"
        case .jp: "Japan"
        case .kr: "South Korea"
        case .de: "Germany"
        case .fr: "France"
        case .ca: "Canada"
        case .au: "Australia"
        }
    }
}

// MARK: - Download Error

public enum DownloadError: Error, Equatable, Sendable {
    case regionLocked(country: String?)
    case formatUnavailable(String)
    case networkError(String)
    case ytdlpNotFound
    case ffmpegNotFound
    case unknown(String)

    public var userMessage: String {
        switch self {
        case .regionLocked(let country):
            if let country {
                return "This video is region-locked to \(country). Configure a proxy or geo-bypass in Settings."
            }
            return "This video is region-locked. Configure a proxy or geo-bypass in Settings."
        case .formatUnavailable(let format):
            return "Requested format unavailable: \(format)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .ytdlpNotFound:
            return "yt-dlp not found. Install via: brew install yt-dlp"
        case .ffmpegNotFound:
            return "ffmpeg not found. Install via: brew install ffmpeg"
        case .unknown(let message):
            return "Download failed: \(message)"
        }
    }
}
