import Foundation

/// Unified error type combining validation, upload, import, and deletion errors.
public enum MediaError: Error, Sendable, CustomStringConvertible {
    case validation(MediaValidationError)
    case upload(any Error)
    case importFailed(String)
    case unauthorized
    case networkUnavailable
    case storageFull
    case photoNotFound(s3Key: String)

    public var description: String {
        switch self {
        case .validation(let error):
            return "Validation error: \(error)"
        case .upload(let error):
            return "Upload error: \(error.localizedDescription)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        case .unauthorized:
            return "Photo library access denied"
        case .networkUnavailable:
            return "Network unavailable"
        case .storageFull:
            return "Storage full"
        case .photoNotFound(let s3Key):
            return "Photo not found: \(s3Key)"
        }
    }

    public var localizedDescription: String {
        description
    }
}
