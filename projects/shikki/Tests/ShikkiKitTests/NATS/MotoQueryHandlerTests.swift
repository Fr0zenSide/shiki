import Foundation
import Testing
@testable import ShikkiKit

// MARK: - MotoQueryHandlerTests

@Suite("MotoQueryHandler")
struct MotoQueryHandlerTests {

    // MARK: - Helpers

    /// Create a MotoMCPInterface backed by the test fixture cache.
    private func makeInterface() -> MotoMCPInterface {
        // Use a minimal in-memory approach: create temp cache files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moto-query-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Write minimal cache files
        let manifest = MotoCacheManifest(
            project: "test-project",
            gitCommit: "abc123",
            builtAt: "2026-04-03T00:00:00Z",
            builder: "test"
        )
        let manifestData = try! JSONEncoder().encode(manifest)
        try! manifestData.write(to: tempDir.appendingPathComponent("manifest.json"))

        let types: [TypeDescriptor] = [
            TypeDescriptor(
                name: "ShikkiKernel",
                kind: .class,
                file: "ShikkiKernel.swift",
                module: "ShikkiKit",
                conformances: ["Sendable"]
            ),
        ]
        let typesData = try! JSONEncoder().encode(types)
        try! typesData.write(to: tempDir.appendingPathComponent("types.json"))

        let protocols: [ProtocolDescriptor] = [
            ProtocolDescriptor(
                name: "NATSClientProtocol",
                file: "NATSClientProtocol.swift",
                conformers: ["MockNATSClient"],
                module: "ShikkiKit"
            ),
        ]
        let protocolsData = try! JSONEncoder().encode(protocols)
        try! protocolsData.write(to: tempDir.appendingPathComponent("protocols.json"))

        return MotoMCPInterface(cachePath: tempDir.path)
    }

    // MARK: - Tests

    @Test("Handler subscribes to correct subject")
    func handlerSubscribesToCorrectSubject() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let motoInterface = makeInterface()
        let handler = MotoQueryHandler(
            nats: nats,
            motoInterface: motoInterface,
            nodeId: "node-alpha",
            cacheVersion: "1.0.0"
        )

        await handler.start()

        // Give subscription time to register
        try await Task.sleep(for: .milliseconds(50))

        let subscribed = await nats.subscribedSubjects
        #expect(subscribed.contains("shikki.moto.query.node-alpha"))
        #expect(subscribed.contains("shikki.moto.query.available"))

        await handler.stop()
    }

    @Test("Valid query returns tool result")
    func validQueryReturnsResult() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let motoInterface = makeInterface()
        let handler = MotoQueryHandler(
            nats: nats,
            motoInterface: motoInterface,
            nodeId: "node-alpha",
            cacheVersion: "1.0.0"
        )

        await handler.start()
        try await Task.sleep(for: .milliseconds(50))

        // Build a query request
        let request = MotoQueryRequest(tool: "moto_get_type", args: ["name": "ShikkiKernel"])
        let requestData = try JSONEncoder().encode(request)
        let replySubject = "_INBOX.reply-123"

        // Inject message with replyTo
        await nats.injectMessage(NATSMessage(
            subject: MotoQuerySubjects.targeted(nodeId: "node-alpha"),
            data: requestData,
            replyTo: replySubject
        ))

        // Give handler time to process
        try await Task.sleep(for: .milliseconds(100))

        // Check that a response was published to the reply subject
        let published = await nats.publishedMessages
        let replies = published.filter { $0.subject == replySubject }
        #expect(replies.count == 1)

        // Decode the response
        let response = try JSONDecoder().decode(MotoQueryResponse.self, from: replies[0].data)
        #expect(response.ok == true)
        #expect(response.nodeId == "node-alpha")
        #expect(response.cacheVersion == "1.0.0")
        #expect(response.data != nil)
        #expect(response.error == nil)

        // The data should contain the type descriptor
        if let data = response.data {
            let type = try JSONDecoder().decode(TypeDescriptor.self, from: data)
            #expect(type.name == "ShikkiKernel")
        }

        await handler.stop()
    }

    @Test("Unknown tool returns error response")
    func unknownToolReturnsError() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let motoInterface = makeInterface()
        let handler = MotoQueryHandler(
            nats: nats,
            motoInterface: motoInterface,
            nodeId: "node-beta",
            cacheVersion: "1.0.0"
        )

        await handler.start()
        try await Task.sleep(for: .milliseconds(50))

        let request = MotoQueryRequest(tool: "moto_nonexistent_tool", args: [:])
        let requestData = try JSONEncoder().encode(request)
        let replySubject = "_INBOX.reply-456"

        await nats.injectMessage(NATSMessage(
            subject: MotoQuerySubjects.targeted(nodeId: "node-beta"),
            data: requestData,
            replyTo: replySubject
        ))

        try await Task.sleep(for: .milliseconds(100))

        let published = await nats.publishedMessages
        let replies = published.filter { $0.subject == replySubject }
        #expect(replies.count == 1)

        let response = try JSONDecoder().decode(MotoQueryResponse.self, from: replies[0].data)
        #expect(response.ok == false)
        #expect(response.error != nil)
        #expect(response.error!.contains("Unknown tool"))
        #expect(response.data == nil)
        #expect(response.nodeId == "node-beta")

        await handler.stop()
    }

    @Test("Query with missing args returns error")
    func queryWithMissingArgsReturnsError() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let motoInterface = makeInterface()
        let handler = MotoQueryHandler(
            nats: nats,
            motoInterface: motoInterface,
            nodeId: "node-gamma",
            cacheVersion: "1.0.0"
        )

        await handler.start()
        try await Task.sleep(for: .milliseconds(50))

        // moto_get_type requires "name" arg — send without it
        let request = MotoQueryRequest(tool: "moto_get_type", args: [:])
        let requestData = try JSONEncoder().encode(request)
        let replySubject = "_INBOX.reply-789"

        await nats.injectMessage(NATSMessage(
            subject: MotoQuerySubjects.targeted(nodeId: "node-gamma"),
            data: requestData,
            replyTo: replySubject
        ))

        try await Task.sleep(for: .milliseconds(100))

        let published = await nats.publishedMessages
        let replies = published.filter { $0.subject == replySubject }
        #expect(replies.count == 1)

        let response = try JSONDecoder().decode(MotoQueryResponse.self, from: replies[0].data)
        #expect(response.ok == false)
        #expect(response.error != nil)
        #expect(response.error!.contains("Missing required argument"))

        await handler.stop()
    }

    @Test("Handler ignores messages without replyTo")
    func handlerIgnoresMessagesWithoutReplyTo() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let motoInterface = makeInterface()
        let handler = MotoQueryHandler(
            nats: nats,
            motoInterface: motoInterface,
            nodeId: "node-delta",
            cacheVersion: "1.0.0"
        )

        await handler.start()
        try await Task.sleep(for: .milliseconds(50))

        let request = MotoQueryRequest(tool: "moto_get_type", args: ["name": "ShikkiKernel"])
        let requestData = try JSONEncoder().encode(request)

        // No replyTo — handler should silently ignore
        await nats.injectMessage(NATSMessage(
            subject: MotoQuerySubjects.targeted(nodeId: "node-delta"),
            data: requestData,
            replyTo: nil
        ))

        try await Task.sleep(for: .milliseconds(100))

        let published = await nats.publishedMessages
        #expect(published.isEmpty)

        await handler.stop()
    }

    @Test("Handler responds to broadcast subject")
    func handlerRespondsToBroadcastSubject() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let motoInterface = makeInterface()
        let handler = MotoQueryHandler(
            nats: nats,
            motoInterface: motoInterface,
            nodeId: "node-epsilon",
            cacheVersion: "2.0.0"
        )

        await handler.start()
        try await Task.sleep(for: .milliseconds(50))

        let request = MotoQueryRequest(tool: "moto_get_context", args: ["scope": "manifest"])
        let requestData = try JSONEncoder().encode(request)
        let replySubject = "_INBOX.reply-broadcast"

        await nats.injectMessage(NATSMessage(
            subject: MotoQuerySubjects.available,
            data: requestData,
            replyTo: replySubject
        ))

        try await Task.sleep(for: .milliseconds(100))

        let published = await nats.publishedMessages
        let replies = published.filter { $0.subject == replySubject }
        #expect(replies.count == 1)

        let response = try JSONDecoder().decode(MotoQueryResponse.self, from: replies[0].data)
        #expect(response.ok == true)
        #expect(response.nodeId == "node-epsilon")
        #expect(response.cacheVersion == "2.0.0")

        await handler.stop()
    }
}
