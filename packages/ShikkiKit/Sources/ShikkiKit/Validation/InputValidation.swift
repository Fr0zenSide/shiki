import Foundation

/// A single validation error with a field path and message.
public struct ValidationError: Codable, Equatable, Sendable {
    public let field: String
    public let message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

/// Protocol for validatable request inputs. Mirrors Zod schema validation.
public protocol Validatable: Sendable {
    /// Validates the input, throwing `ShikkiError.validationFailed` on failure.
    func validate() throws
}

/// Shared validation helpers.
public enum Validators {
    public static func requireNonEmpty(_ value: String, field: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ShikkiValidationError.fieldEmpty(field)
        }
    }

    public static func requirePositive(_ value: Int, field: String) throws {
        if value < 1 {
            throw ShikkiValidationError.fieldMustBePositive(field)
        }
    }

    public static func requireNonNegative(_ value: Int, field: String) throws {
        if value < 0 {
            throw ShikkiValidationError.fieldMustBeNonNegative(field)
        }
    }

    public static func requireRange(_ value: Double, min: Double, max: Double, field: String) throws {
        if value < min || value > max {
            throw ShikkiValidationError.fieldOutOfRange(field, min: min, max: max)
        }
    }

    public static func requireValidUUID(_ string: String, field: String) throws {
        if UUID(uuidString: string) == nil {
            throw ShikkiValidationError.invalidUUID(field)
        }
    }
}

/// Validation errors before they are wrapped into ShikkiError.
public enum ShikkiValidationError: Error, Equatable, Sendable {
    case fieldEmpty(String)
    case fieldMustBePositive(String)
    case fieldMustBeNonNegative(String)
    case fieldOutOfRange(String, min: Double, max: Double)
    case invalidUUID(String)
    case custom(String)
}
