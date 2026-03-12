import Foundation

public enum MediaValidationError: Error, Sendable, Hashable {
    case outsideGPSCorridor
    case outsideTimeWindow
    case missingGPSData
    case unsupportedFormat
    case fileTooLarge(maxBytes: Int64)
}
