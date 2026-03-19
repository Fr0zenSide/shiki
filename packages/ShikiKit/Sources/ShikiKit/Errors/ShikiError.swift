import Foundation

/// Top-level error type for the Shiki API.
/// Codable for wire format — the server sends these as JSON error responses,
/// and the client decodes them.
public enum ShikiError: Error, Equatable, Sendable {
    /// Resource not found (HTTP 404).
    case notFound(String)

    /// Bad request — invalid input or missing parameters (HTTP 400).
    case badRequest(String)

    /// Validation failed — one or more fields are invalid (HTTP 400).
    case validationFailed([ValidationError])

    /// A required service is unavailable (HTTP 503).
    case serviceUnavailable(String)

    /// Internal server error (HTTP 500).
    case internalError(String)

    /// Unauthorized — missing or invalid authentication (HTTP 401).
    case unauthorized(String)
}

// MARK: - HTTP Status Code Mapping

extension ShikiError {
    /// The HTTP status code corresponding to this error.
    public var statusCode: Int {
        switch self {
        case .notFound: return 404
        case .badRequest: return 400
        case .validationFailed: return 400
        case .serviceUnavailable: return 503
        case .internalError: return 500
        case .unauthorized: return 401
        }
    }

    /// A short error code string suitable for JSON responses.
    public var code: String {
        switch self {
        case .notFound: return "NOT_FOUND"
        case .badRequest: return "BAD_REQUEST"
        case .validationFailed: return "VALIDATION_FAILED"
        case .serviceUnavailable: return "SERVICE_UNAVAILABLE"
        case .internalError: return "INTERNAL_ERROR"
        case .unauthorized: return "UNAUTHORIZED"
        }
    }

    /// The error message.
    public var message: String {
        switch self {
        case .notFound(let msg): return msg
        case .badRequest(let msg): return msg
        case .validationFailed(let errors):
            return errors.map { "\($0.field): \($0.message)" }.joined(separator: "; ")
        case .serviceUnavailable(let msg): return msg
        case .internalError(let msg): return msg
        case .unauthorized(let msg): return msg
        }
    }
}

// MARK: - Codable

extension ShikiError: Codable {
    enum CodingKeys: String, CodingKey {
        case code, message, errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(String.self, forKey: .code)
        let message = try container.decode(String.self, forKey: .message)

        switch code {
        case "NOT_FOUND":
            self = .notFound(message)
        case "BAD_REQUEST":
            self = .badRequest(message)
        case "VALIDATION_FAILED":
            let errors = try container.decodeIfPresent([ValidationError].self, forKey: .errors) ?? []
            self = .validationFailed(errors)
        case "SERVICE_UNAVAILABLE":
            self = .serviceUnavailable(message)
        case "UNAUTHORIZED":
            self = .unauthorized(message)
        default:
            self = .internalError(message)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)

        if case .validationFailed(let errors) = self {
            try container.encode(errors, forKey: .errors)
        }
    }
}

// MARK: - CustomStringConvertible

extension ShikiError: CustomStringConvertible {
    public var description: String {
        "ShikiError.\(code)(\(statusCode)): \(message)"
    }
}

// MARK: - Convenience factories from validation errors

extension ShikiError {
    /// Creates a `.validationFailed` error from a `ShikiValidationError`.
    public static func fromValidation(_ error: ShikiValidationError) -> ShikiError {
        switch error {
        case .fieldEmpty(let field):
            return .validationFailed([ValidationError(field: field, message: "\(field) must not be empty")])
        case .fieldMustBePositive(let field):
            return .validationFailed([ValidationError(field: field, message: "\(field) must be positive")])
        case .fieldMustBeNonNegative(let field):
            return .validationFailed([ValidationError(field: field, message: "\(field) must be non-negative")])
        case .fieldOutOfRange(let field, let min, let max):
            return .validationFailed([ValidationError(field: field, message: "\(field) must be between \(min) and \(max)")])
        case .invalidUUID(let field):
            return .validationFailed([ValidationError(field: field, message: "\(field) must be a valid UUID")])
        case .custom(let msg):
            return .validationFailed([ValidationError(field: "_", message: msg)])
        }
    }
}
