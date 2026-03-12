import Testing
import Foundation
@testable import ShikiKit

@Suite("ShikiError Types")
struct ShikiErrorTests {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    // MARK: - Status codes

    @Test("ShikiError maps to correct HTTP status codes")
    func test_shikiError_statusCodes() {
        #expect(ShikiError.notFound("x").statusCode == 404)
        #expect(ShikiError.badRequest("x").statusCode == 400)
        #expect(ShikiError.validationFailed([]).statusCode == 400)
        #expect(ShikiError.serviceUnavailable("x").statusCode == 503)
        #expect(ShikiError.internalError("x").statusCode == 500)
        #expect(ShikiError.unauthorized("x").statusCode == 401)
    }

    @Test("ShikiError maps to correct error codes")
    func test_shikiError_codes() {
        #expect(ShikiError.notFound("x").code == "NOT_FOUND")
        #expect(ShikiError.badRequest("x").code == "BAD_REQUEST")
        #expect(ShikiError.validationFailed([]).code == "VALIDATION_FAILED")
        #expect(ShikiError.serviceUnavailable("x").code == "SERVICE_UNAVAILABLE")
        #expect(ShikiError.internalError("x").code == "INTERNAL_ERROR")
        #expect(ShikiError.unauthorized("x").code == "UNAUTHORIZED")
    }

    // MARK: - Codable round-trip

    @Test("ShikiError.notFound round-trips through JSON")
    func test_notFound_roundTrips() throws {
        let error = ShikiError.notFound("Pipeline run not found")
        let data = try Self.encoder.encode(error)
        let decoded = try Self.decoder.decode(ShikiError.self, from: data)
        #expect(decoded == error)
    }

    @Test("ShikiError.validationFailed round-trips with errors array")
    func test_validationFailed_roundTrips() throws {
        let error = ShikiError.validationFailed([
            ValidationError(field: "content", message: "content must not be empty"),
            ValidationError(field: "limit", message: "limit must be positive"),
        ])

        let data = try Self.encoder.encode(error)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"errors\""))
        #expect(json.contains("\"VALIDATION_FAILED\""))

        let decoded = try Self.decoder.decode(ShikiError.self, from: data)
        if case .validationFailed(let errors) = decoded {
            #expect(errors.count == 2)
            #expect(errors[0].field == "content")
            #expect(errors[1].field == "limit")
        } else {
            Issue.record("Expected validationFailed, got \(decoded)")
        }
    }

    @Test("ShikiError decodes from server JSON")
    func test_shikiError_decodesFromServerJSON() throws {
        let json = """
        {
            "code": "BAD_REQUEST",
            "message": "session_id query param required"
        }
        """

        let error = try Self.decoder.decode(ShikiError.self, from: Data(json.utf8))
        #expect(error == .badRequest("session_id query param required"))
        #expect(error.statusCode == 400)
    }

    @Test("ShikiError decodes unknown code as internalError")
    func test_shikiError_unknownCodeFallback() throws {
        let json = """
        {
            "code": "SOME_FUTURE_ERROR",
            "message": "Something went wrong"
        }
        """

        let error = try Self.decoder.decode(ShikiError.self, from: Data(json.utf8))
        #expect(error == .internalError("Something went wrong"))
    }

    // MARK: - Validation UUID test (from test plan)

    @Test("AgentEventInput rejects invalid UUID string via Validators")
    func test_agentEventInput_rejectsInvalidUUID() {
        #expect(throws: ShikiValidationError.self) {
            try Validators.requireValidUUID("not-a-uuid", field: "agentId")
        }

        // Valid UUID should not throw
        #expect(throws: Never.self) {
            try Validators.requireValidUUID("11111111-1111-1111-1111-111111111111", field: "agentId")
        }
    }

    // MARK: - fromValidation factory

    @Test("ShikiError.fromValidation converts ShikiValidationError correctly")
    func test_fromValidation_converts() {
        let error = ShikiError.fromValidation(.fieldEmpty("content"))
        if case .validationFailed(let errors) = error {
            #expect(errors.count == 1)
            #expect(errors[0].field == "content")
            #expect(errors[0].message.contains("empty"))
        } else {
            Issue.record("Expected validationFailed")
        }

        let rangeError = ShikiError.fromValidation(.fieldOutOfRange("limit", min: 1, max: 100))
        if case .validationFailed(let errors) = rangeError {
            #expect(errors[0].message.contains("1.0"))
            #expect(errors[0].message.contains("100.0"))
        } else {
            Issue.record("Expected validationFailed")
        }
    }

    // MARK: - CustomStringConvertible

    @Test("ShikiError description is readable")
    func test_shikiError_description() {
        let error = ShikiError.notFound("Pipeline run not found")
        #expect(error.description == "ShikiError.NOT_FOUND(404): Pipeline run not found")
    }
}
