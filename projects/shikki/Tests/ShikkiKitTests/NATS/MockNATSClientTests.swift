import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Thread-safe message collector

private final class MessageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [NATSMessage] = []

    var messages: [NATSMessage] {
        lock.withLock { _messages }
    }

    var count: Int {
        lock.withLock { _messages.count }
    }

    func append(_ msg: NATSMessage) {
        lock.withLock { _messages.append(msg) }
    }
}

@Suite("MockNATSClient")
struct MockNATSClientTests {

    // MARK: - Connection

    @Test("Connect sets isConnected to true")
    func connectSetsConnected() async throws {
        let client = MockNATSClient()
        #expect(await client.isConnected == false)
        try await client.connect()
        #expect(await client.isConnected == true)
    }

    @Test("Disconnect sets isConnected to false")
    func disconnectSetsNotConnected() async throws {
        let client = MockNATSClient()
        try await client.connect()
        await client.disconnect()
        #expect(await client.isConnected == false)
    }

    @Test("Connect throws when shouldFailConnect is set")
    func connectThrowsOnFailure() async {
        let client = MockNATSClient()
        await client.setShouldFailConnect(true)
        do {
            try await client.connect()
            Issue.record("Expected connect to throw")
        } catch {
            #expect(error is NATSClientError)
        }
    }

    // MARK: - Publish

    @Test("Publish records messages")
    func publishRecordsMessages() async throws {
        let client = MockNATSClient()
        try await client.connect()

        let data = Data("test payload".utf8)
        try await client.publish(subject: "shikki.events.maya.lifecycle", data: data)

        let published = await client.publishedMessages
        #expect(published.count == 1)
        #expect(published[0].subject == "shikki.events.maya.lifecycle")
    }

    @Test("Publish throws when not connected")
    func publishThrowsWhenNotConnected() async {
        let client = MockNATSClient()
        do {
            try await client.publish(subject: "test", data: Data())
            Issue.record("Expected publish to throw")
        } catch {
            #expect(error as? NATSClientError == .notConnected)
        }
    }

    @Test("Publish throws when shouldFailPublish is set")
    func publishThrowsOnFailure() async throws {
        let client = MockNATSClient()
        try await client.connect()
        await client.setShouldFailPublish(true)
        do {
            try await client.publish(subject: "test", data: Data())
            Issue.record("Expected publish to throw")
        } catch {
            #expect(error is NATSClientError)
        }
    }

    // MARK: - Subscribe

    @Test("Subscribe records the subject")
    func subscribeRecordsSubject() async throws {
        let client = MockNATSClient()
        _ = client.subscribe(subject: "shikki.events.>")

        // Let the subscription register
        try await Task.sleep(for: .milliseconds(50))

        let subs = await client.subscribedSubjects
        #expect(subs.contains("shikki.events.>"))
    }

    @Test("Published messages are delivered to matching subscribers")
    func publishRoutesToSubscribers() async throws {
        let client = MockNATSClient()
        try await client.connect()

        let stream = client.subscribe(subject: "shikki.events.>")
        try await Task.sleep(for: .milliseconds(50))

        let data = Data("{\"test\": true}".utf8)
        try await client.publish(subject: "shikki.events.maya.lifecycle", data: data)

        let collector = MessageCollector()
        let collectTask = Task { @Sendable in
            for await msg in stream {
                collector.append(msg)
                break  // Only collect one
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        collectTask.cancel()

        #expect(collector.count == 1)
        #expect(collector.messages[0].subject == "shikki.events.maya.lifecycle")
    }

    @Test("Non-matching subscribers do not receive messages")
    func nonMatchingSubscribersFiltered() async throws {
        let client = MockNATSClient()
        try await client.connect()

        let stream = client.subscribe(subject: "shikki.events.shiki.>")
        try await Task.sleep(for: .milliseconds(50))

        // Publish to maya (should NOT match shiki subscriber)
        try await client.publish(subject: "shikki.events.maya.lifecycle", data: Data())

        let collector = MessageCollector()
        let collectTask = Task { @Sendable in
            for await msg in stream {
                collector.append(msg)
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        collectTask.cancel()

        #expect(collector.messages.isEmpty)
    }

    // MARK: - Request/Reply

    @Test("Request returns reply from handler")
    func requestReturnsReply() async throws {
        let client = MockNATSClient()
        try await client.connect()

        let replyData = Data("reply".utf8)
        await client.setReplyHandler { subject, _ in
            NATSMessage(subject: subject, data: replyData)
        }

        let reply = try await client.request(
            subject: "shikki.commands.test",
            data: Data(),
            timeout: .seconds(1)
        )
        #expect(String(data: reply.data, encoding: .utf8) == "reply")
    }

    @Test("Request throws timeout when no handler is set")
    func requestThrowsTimeoutWithoutHandler() async throws {
        let client = MockNATSClient()
        try await client.connect()

        do {
            _ = try await client.request(
                subject: "shikki.commands.test",
                data: Data(),
                timeout: .seconds(1)
            )
            Issue.record("Expected timeout error")
        } catch {
            #expect(error as? NATSClientError == .timeout)
        }
    }

    // MARK: - Wildcard Matching

    @Test("Exact match")
    func exactMatch() {
        #expect(MockNATSClient.matches(subject: "a.b.c", pattern: "a.b.c"))
        #expect(!MockNATSClient.matches(subject: "a.b.c", pattern: "a.b.d"))
    }

    @Test("Tail wildcard > matches remaining tokens")
    func tailWildcard() {
        #expect(MockNATSClient.matches(subject: "shikki.events.maya.agent", pattern: "shikki.events.>"))
        #expect(MockNATSClient.matches(subject: "shikki.events.maya.agent", pattern: "shikki.events.maya.>"))
        #expect(!MockNATSClient.matches(subject: "shikki.events.maya.agent", pattern: "shikki.commands.>"))
    }

    @Test("Single token wildcard * matches one token")
    func singleWildcard() {
        #expect(MockNATSClient.matches(subject: "shikki.events.maya.agent", pattern: "shikki.events.*.agent"))
        #expect(!MockNATSClient.matches(subject: "shikki.events.maya.agent", pattern: "shikki.events.*.lifecycle"))
    }

    @Test("Pattern shorter than subject without > does not match")
    func shorterPatternNoMatch() {
        #expect(!MockNATSClient.matches(subject: "a.b.c", pattern: "a.b"))
    }

    @Test("Pattern longer than subject does not match")
    func longerPatternNoMatch() {
        #expect(!MockNATSClient.matches(subject: "a.b", pattern: "a.b.c"))
    }

    // MARK: - Inject Message

    @Test("injectMessage routes to matching subscribers")
    func injectMessageRoutes() async throws {
        let client = MockNATSClient()
        let stream = client.subscribe(subject: "shikki.events.>")
        try await Task.sleep(for: .milliseconds(50))

        let msg = NATSMessage(subject: "shikki.events.maya.lifecycle", data: Data("test".utf8))
        await client.injectMessage(msg)

        let collector = MessageCollector()
        let collectTask = Task { @Sendable in
            for await m in stream {
                collector.append(m)
                break
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        collectTask.cancel()

        #expect(collector.count == 1)
    }
}

// MARK: - Helper extensions for test configuration

extension MockNATSClient {
    func setShouldFailConnect(_ value: Bool) {
        self.shouldFailConnect = value
    }
    func setShouldFailPublish(_ value: Bool) {
        self.shouldFailPublish = value
    }
    func setReplyHandler(_ handler: @escaping @Sendable (String, Data) -> NATSMessage?) {
        self.replyHandler = handler
    }
}
