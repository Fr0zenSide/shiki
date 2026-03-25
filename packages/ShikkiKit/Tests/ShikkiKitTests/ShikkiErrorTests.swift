import Testing
import Foundation
@testable import ShikkiKit

@Suite("ShikkiError Types")
struct ShikkiErrorTests {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    // MARK: - Status codes

    @Test("ShikkiError maps to correct HTTP status codes")
    func test_shikiError_statusCodes() {
        #expect(ShikkiError.notFound("x").statusCode == 404)
        #expect(ShikkiError.badRequest("x").statusCode == 400)
        #expect(ShikkiError.validationFailed([]).statusCode == 400)
        #expect(ShikkiError.serviceUnavailable("x").statusCode == 503)
        #expect(ShikkiError.internalError("x").statusCode == 500)
        #expect(ShikkiError.unauthorized("x").statusCode == 401)
    }

    @Test("ShikkiError maps to correct error codes")
    func test_shikiError_codes() {
        #expect(ShikkiError.notFound("x").code == "NOT_FOUND")
        #expect(ShikkiError.badRequest("x").code == "BAD_REQUEST")
        #expect(ShikkiError.validationFailed([]).code == "VALIDATION_FAILED")
        #expect(ShikkiError.serviceUnavailable("x").code == "SERVICE_UNAVAILABLE")
        #expect(ShikkiError.internalError("x").code == "INTERNAL_ERROR")
        #expect(ShikkiError.unauthorized("x").code == "UNAUTHORIZED")
    }

    // MARK: - Codable round-trip

    @Test("ShikkiError.notFound round-trips through JSON")
    func test_notFound_roundTrips() throws {
        let error = ShikkiError.notFound("Pipeline run not found")
        let data = try Self.encoder.encode(error)
        let decoded = try Self.decoder.decode(ShikkiError.self, from: data)
        #expect(decoded == error)
    }

    @Test("ShikkiError.validationFailed round-trips with errors array")
    func test_validationFailed_roundTrips() throws {
        let error = ShikkiError.validationFailed([
            ValidationError(field: "content", message: "content must not be empty"),
            ValidationError(field: "limit", message: "limit must be positive"),
        ])

        let data = try Self.encoder.encode(error)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"errors\""))
        #expect(json.contains("\"VALIDATION_FAILED\""))

        let decoded = try Self.decoder.decode(ShikkiError.self, from: data)
        if case .validationFailed(let errors) = decoded {
            #expect(errors.count == 2)
            #expect(errors[0].field == "content")
            #expect(errors[1].field == "limit")
        } else {
            Issue.record("Expected validationFailed, got \(decoded)")
        }
    }

    @Test("ShikkiError decodes from server JSON")
    func test_shikiError_decodesFromServerJSON() throws {
        let json = """
        {
            "code": "BAD_REQUEST",
            "message": "session_id query param required"
        }
        """

        let error = try Self.decoder.decode(ShikkiError.self, from: Data(json.utf8))
        #expect(error == .badRequest("session_id query param required"))
        #expect(error.statusCode == 400)
    }

    @Test("ShikkiError decodes unknown code as internalError")
    func test_shikiError_unknownCodeFallback() throws {
        let json = """
        {
            "code": "SOME_FUTURE_ERROR",
            "message": "Something went wrong"
        }
        """

        let error = try Self.decoder.decode(ShikkiError.self, from: Data(json.utf8))
        #expect(error == .internalError("Something went wrong"))
    }

    // MARK: - Validation UUID test (from test plan)

    @Test("AgentEventInput rejects invalid UUID string via Validators")
    func test_agentEventInput_rejectsInvalidUUID() {
        #expect(throws: ShikkiValidationError.self) {
            try Validators.requireValidUUID("not-a-uuid", field: "agentId")
        }

        // Valid UUID should not throw
        #expect(throws: Never.self) {
            try Validators.requireValidUUID("11111111-1111-1111-1111-111111111111", field: "agentId")
        }
    }

    // MARK: - fromValidation factory

    @Test("ShikkiError.fromValidation converts ShikkiValidationError correctly")
    func test_fromValidation_converts() {
        let error = ShikkiError.fromValidation(.fieldEmpty("content"))
        if case .validationFailed(let errors) = error {
            #expect(errors.count == 1)
            #expect(errors[0].field == "content")
            #expect(errors[0].message.contains("empty"))
        } else {
            Issue.record("Expected validationFailed")
        }

        let rangeError = ShikkiError.fromValidation(.fieldOutOfRange("limit", min: 1, max: 100))
        if case .validationFailed(let errors) = rangeError {
            #expect(errors[0].message.contains("1.0"))
            #expect(errors[0].message.contains("100.0"))
        } else {
            Issue.record("Expected validationFailed")
        }
    }

    // MARK: - CustomStringConvertible

    @Test("ShikkiError description is readable")
    func test_shikiError_description() {
        let error = ShikkiError.notFound("Pipeline run not found")
        #expect(error.description == "ShikkiError.NOT_FOUND(404): Pipeline run not found")
    }
}
