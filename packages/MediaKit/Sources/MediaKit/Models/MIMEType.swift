import Foundation

public enum MIMEType: String, Sendable, Hashable, Codable {
    case heic
    case jpeg
    case png

    public var contentType: String {
        switch self {
        case .heic: return "image/heic"
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        }
    }
}
