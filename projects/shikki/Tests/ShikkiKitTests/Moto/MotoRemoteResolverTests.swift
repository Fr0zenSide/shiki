import Foundation
import Testing
@testable import ShikkiKit

// MARK: - MotoRemoteResolverTests

@Suite("MotoRemoteResolver")
struct MotoRemoteResolverTests {

    // MARK: - Helpers

    private func makeSuccessResponse(
        nodeId: String = "remote-node",
        cacheVersion: String = "1.0.0",
        data: Data? = nil
    ) -> MotoQueryResponse {
        MotoQueryResponse(
            ok: true,
            data: data ?? "{}".data(using: .utf8)!,
            error: nil,
            nodeId: nodeId,
            cacheVersion: cacheVersion
        )
    }

    private func makeErrorResponse(
        nodeId: String = "remote-node",
        error: String = "Type not found"
    ) -> MotoQueryResponse {
        MotoQueryResponse(
            ok: false,
            data: nil,
            error: error,
            nodeId: nodeId,
            cacheVersion: "1.0.0"
        )
    }

    // MARK: - Tests

    @Test("Query specific node publishes to correct subject")
    func querySpecificNodePublishesToCorrectSubject() async throws {
        let nats = MockNATSClient()
        try await nats.connect()

        // Set up reply handler
        let response = makeSuccessResponse()
        let responseData = try JSONEncoder().encode(response)

        await nats.whenRequest(subject: "shikki.moto.query.node-42") { _ in
            NATSMessage(
                subject: "_INBOX.reply",
                data: responseData
            )
        }

        let resolver = MotoRemoteResolver(nats: nats)

        let result = try await resolver.query(
            nodeId: "node-42",
            tool: "moto_get_type",
            args: ["name": "ShikkiKernel"]
        )

        // Verify the response was returned as raw data
        let decoded = try JSONDecoder().decode(MotoQueryResponse.self, from: result)
        #expect(decoded.ok == true)
        #expect(decoded.nodeId == "remote-node")
    }

    @Test("Query any publishes to broadcast subject")
    func queryAnyPublishesToBroadcastSubject() async throws {
        let nats = MockNATSClient()
        try await nats.connect()

        let response = makeSuccessResponse(nodeId: "first-responder")
        let responseData = try JSONEncoder().encode(response)

        await nats.whenRequest(subject: "shikki.moto.query.available") { _ in
            NATSMessage(
                subject: "_INBOX.reply",
                data: responseData
            )
        }

        let resolver = MotoRemoteResolver(nats: nats)

        let result = try await resolver.queryAny(
            tool: "moto_get_protocol",
            args: ["name": "NATSClientProtocol"]
        )

        let decoded = try JSONDecoder().decode(MotoQueryResponse.self, from: result)
        #expect(decoded.ok == true)
        #expect(decoded.nodeId == "first-responder")
    }

    @Test("Timeout when no response throws error")
    func timeoutWhenNoResponse() async throws {
        let nats = MockNATSClient()
        try await nats.connect()

        // No reply handler — request will timeout
        let resolver = MotoRemoteResolver(nats: nats)

        do {
            _ = try await resolver.query(
                nodeId: "offline-node",
                tool: "moto_get_type",
                args: ["name": "Missing"],
                timeout: .milliseconds(100)
            )
            Issue.record("Expected MotoQueryError.timeout")
        } catch {
            #expect(error is MotoQueryError)
            if let queryError = error as? MotoQueryError {
                #expect(queryError == .timeout)
            }
        }
    }

    @Test("Valid response decoded correctly")
    func validResponseDecodedCorrectly() async throws {
        let nats = MockNATSClient()
        try await nats.connect()

        // Create a response with real data
        let typeDescriptor = TypeDescriptor(
            name: "ShikkiKernel",
            kind: .class,
            file: "ShikkiKernel.swift",
            module: "ShikkiKit",
            conformances: ["Sendable"]
        )
        let typeData = try JSONEncoder().encode(typeDescriptor)
        let response = makeSuccessResponse(
            nodeId: "data-node",
            cacheVersion: "3.0.0",
            data: typeData
        )
        let responseData = try JSONEncoder().encode(response)

        await nats.whenRequest(subject: "shikki.moto.query.data-node") { _ in
            NATSMessage(subject: "_INBOX.reply", data: responseData)
        }

        let resolver = MotoRemoteResolver(nats: nats)

        let result = try await resolver.query(
            nodeId: "data-node",
            tool: "moto_get_type",
            args: ["name": "ShikkiKernel"]
        )

        let decoded = try JSONDecoder().decode(MotoQueryResponse.self, from: result)
        #expect(decoded.ok == true)
        #expect(decoded.nodeId == "data-node")
        #expect(decoded.cacheVersion == "3.0.0")
        #expect(decoded.data != nil)

        // Verify the nested data
        let type = try JSONDecoder().decode(TypeDescriptor.self, from: decoded.data!)
        #expect(type.name == "ShikkiKernel")
        #expect(type.kind == .class)
    }

    @Test("Error response surfaces error message")
    func errorResponseSurfacesErrorMessage() async throws {
        let nats = MockNATSClient()
        try await nats.connect()

        let response = makeErrorResponse(error: "Type not found: MissingType")
        let responseData = try JSONEncoder().encode(response)

        await nats.whenRequest(subject: "shikki.moto.query.error-node") { _ in
            NATSMessage(subject: "_INBOX.reply", data: responseData)
        }

        let resolver = MotoRemoteResolver(nats: nats)

        do {
            _ = try await resolver.query(
                nodeId: "error-node",
                tool: "moto_get_type",
                args: ["name": "MissingType"]
            )
            Issue.record("Expected MotoQueryError.remoteError")
        } catch {
            #expect(error is MotoQueryError)
            if let queryError = error as? MotoQueryError {
                #expect(queryError == .remoteError("Type not found: MissingType"))
            }
        }
    }

    @Test("QueryAny timeout throws error")
    func queryAnyTimeoutThrowsError() async throws {
        let nats = MockNATSClient()
        try await nats.connect()

        let resolver = MotoRemoteResolver(nats: nats)

        do {
            _ = try await resolver.queryAny(
                tool: "moto_get_context",
                args: ["scope": "all"],
                timeout: .milliseconds(100)
            )
            Issue.record("Expected MotoQueryError.timeout")
        } catch {
            #expect(error is MotoQueryError)
            if let queryError = error as? MotoQueryError {
                #expect(queryError == .timeout)
            }
        }
    }
}
