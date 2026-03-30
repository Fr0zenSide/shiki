import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Message Collector (Sendable helper for async stream consumption)

/// Actor that collects NATSMessages from a stream for test assertions.
private actor MessageCollector {
    private(set) var messages: [NATSMessage] = []

    func append(_ message: NATSMessage) {
        messages.append(message)
    }

    func collect(from stream: AsyncStream<NATSMessage>, max: Int) async {
        var count = 0
        for await msg in stream {
            messages.append(msg)
            count += 1
            if count >= max { break }
        }
    }
}

// MARK: - MockNATSClient Connection Tests

@Suite("MockNATSClient — Connection")
struct MockNATSClientConnectionTests {

    @Test("Connect sets isConnected to true")
    func connectSetsConnected() async throws {
        let client = MockNATSClient()
        #expect(await client.isConnected == false)

        try await client.connect()

        #expect(await client.isConnected == true)
        #expect(await client.connectCalled == true)
    }

    @Test("Disconnect sets isConnected to false")
    func disconnectSetsNotConnected() async throws {
        let client = MockNATSClient()
        try await client.connect()

        await client.disconnect()

        #expect(await client.isConnected == false)
        #expect(await client.disconnectCalled == true)
    }

    @Test("Connect throws configured error")
    func connectThrowsOnError() async {
        let client = MockNATSClient()
        await client.setConnectError(.connectionFailed("test failure"))

        do {
            try await client.connect()
            Issue.record("Expected connect to throw")
        } catch let error as NATSError {
            #expect(error == .connectionFailed("test failure"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Publish fails when not connected")
    func publishFailsWhenNotConnected() async {
        let client = MockNATSClient()

        do {
            try await client.publish(subject: "test", data: Data())
            Issue.record("Expected publish to throw")
        } catch let error as NATSError {
            #expect(error == .notConnected)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Request fails when not connected")
    func requestFailsWhenNotConnected() async {
        let client = MockNATSClient()

        do {
            _ = try await client.request(subject: "test", data: Data(), timeout: .seconds(1))
            Issue.record("Expected request to throw")
        } catch let error as NATSError {
            #expect(error == .notConnected)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - MockNATSClient Pub/Sub Tests

@Suite("MockNATSClient — Pub/Sub")
struct MockNATSClientPubSubTests {

    @Test("Published messages are recorded")
    func publishedMessagesRecorded() async throws {
        let client = MockNATSClient()
        try await client.connect()

        let data1 = Data("hello".utf8)
        let data2 = Data("world".utf8)
        try await client.publish(subject: "test.one", data: data1)
        try await client.publish(subject: "test.two", data: data2)

        let messages = await client.publishedMessages
        #expect(messages.count == 2)
        #expect(messages[0].subject == "test.one")
        #expect(messages[0].data == data1)
        #expect(messages[1].subject == "test.two")
        #expect(messages[1].data == data2)
    }

    @Test("Subscriber receives published messages on exact subject")
    func subscriberReceivesMessages() async throws {
        let client = MockNATSClient()
        try await client.connect()

        let stream = await client.subscribe(subject: "test.subject")
        let payload = Data("event-data".utf8)

        try await client.publish(subject: "test.subject", data: payload)

        let collector = MessageCollector()
        let task = Task { await collector.collect(from: stream, max: 1) }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let received = await collector.messages
        #expect(received.count == 1)
        #expect(received[0].subject == "test.subject")
        #expect(received[0].data == payload)
    }

    @Test("Subscriber does not receive messages on different subject")
    func subscriberFiltersSubject() async throws {
        let client = MockNATSClient()
        try await client.connect()

        let stream = await client.subscribe(subject: "test.alpha")
        try await client.publish(subject: "test.beta", data: Data("other".utf8))

        let collector = MessageCollector()
        let task = Task { await collector.collect(from: stream, max: 1) }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let received = await collector.messages
        #expect(received.isEmpty)
    }

    @Test("Wildcard '>' matches multi-level subjects")
    func wildcardGreaterThanMatches() async throws {
        let client = MockNATSClient()
        try await client.connect()

        let stream = await client.subscribe(subject: "shikki.events.>")

        try await client.publish(
            subject: "shikki.events.maya.lifecycle",
            data: Data("event1".utf8)
        )
        try await client.publish(
            subject: "shikki.events.shiki.agent",
            data: Data("event2".utf8)
        )
        try await client.publish(
            subject: "shikki.commands.node1",
            data: Data("not-an-event".utf8)
        )

        let collector = MessageCollector()
        let task = Task { await collector.collect(from: stream, max: 2) }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let received = await collector.messages
        #expect(received.count == 2)
        #expect(received[0].subject == "shikki.events.maya.lifecycle")
        #expect(received[1].subject == "shikki.events.shiki.agent")
    }

    @Test("Wildcard '*' matches single token")
    func wildcardStarMatchesSingleToken() async throws {
        let client = MockNATSClient()
        try await client.connect()

        let stream = await client.subscribe(subject: "shikki.events.*.lifecycle")

        try await client.publish(
            subject: "shikki.events.maya.lifecycle",
            data: Data("yes".utf8)
        )
        try await client.publish(
            subject: "shikki.events.maya.agent",
            data: Data("no".utf8)
        )

        let collector = MessageCollector()
        let task = Task { await collector.collect(from: stream, max: 1) }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let received = await collector.messages
        #expect(received.count == 1)
        #expect(received[0].subject == "shikki.events.maya.lifecycle")
    }

    @Test("Inject message delivers to matching subscribers")
    func injectMessageWorks() async throws {
        let client = MockNATSClient()
        try await client.connect()

        let stream = await client.subscribe(subject: "test.inject")
        let injected = NATSMessage(
            subject: "test.inject",
            data: Data("injected".utf8)
        )

        await client.injectMessage(injected)

        let collector = MessageCollector()
        let task = Task { await collector.collect(from: stream, max: 1) }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let received = await collector.messages
        #expect(received.count == 1)
        #expect(received[0] == injected)
    }

    @Test("Publish with configured error throws")
    func publishWithErrorThrows() async throws {
        let client = MockNATSClient()
        try await client.connect()
        await client.setPublishError(.publishFailed("disk full"))

        do {
            try await client.publish(subject: "test", data: Data())
            Issue.record("Expected publish to throw")
        } catch let error as NATSError {
            #expect(error == .publishFailed("disk full"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - MockNATSClient Request/Reply Tests

@Suite("MockNATSClient — Request/Reply")
struct MockNATSClientRequestReplyTests {

    @Test("Request returns response from registered responder")
    func requestReturnsResponse() async throws {
        let client = MockNATSClient()
        try await client.connect()

        let responseData = Data("pong".utf8)
        await client.whenRequest(subject: "test.ping") { request in
            NATSMessage(
                subject: request.replyTo ?? "reply",
                data: responseData,
                replyTo: nil
            )
        }

        let response = try await client.request(
            subject: "test.ping",
            data: Data("ping".utf8),
            timeout: .seconds(1)
        )

        #expect(response.data == responseData)
    }

    @Test("Request with no responder times out")
    func requestTimesOutWithNoResponder() async throws {
        let client = MockNATSClient()
        try await client.connect()

        do {
            _ = try await client.request(
                subject: "test.no-responder",
                data: Data(),
                timeout: .seconds(1)
            )
            Issue.record("Expected timeout error")
        } catch let error as NATSError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Request is recorded in published messages")
    func requestRecordedInPublished() async throws {
        let client = MockNATSClient()
        try await client.connect()

        await client.whenRequest(subject: "test.req") { _ in
            NATSMessage(subject: "reply", data: Data(), replyTo: nil)
        }

        _ = try await client.request(
            subject: "test.req",
            data: Data("body".utf8),
            timeout: .seconds(1)
        )

        let messages = await client.publishedMessages
        #expect(messages.count == 1)
        #expect(messages[0].subject == "test.req")
        #expect(messages[0].replyTo != nil)
        #expect(messages[0].replyTo?.hasPrefix("_INBOX.") == true)
    }
}

// MARK: - Subject Matching Tests

@Suite("MockNATSClient — Subject Matching")
struct SubjectMatchingTests {

    @Test("Exact match")
    func exactMatch() {
        #expect(MockNATSClient.subjectMatches(pattern: "a.b.c", subject: "a.b.c") == true)
        #expect(MockNATSClient.subjectMatches(pattern: "a.b.c", subject: "a.b.d") == false)
    }

    @Test("Star wildcard matches single token")
    func starWildcard() {
        #expect(MockNATSClient.subjectMatches(pattern: "a.*.c", subject: "a.b.c") == true)
        #expect(MockNATSClient.subjectMatches(pattern: "a.*.c", subject: "a.b.d") == false)
        #expect(MockNATSClient.subjectMatches(pattern: "a.*", subject: "a.b") == true)
        #expect(MockNATSClient.subjectMatches(pattern: "a.*", subject: "a.b.c") == false)
    }

    @Test("Greater-than wildcard matches tail")
    func greaterThanWildcard() {
        #expect(MockNATSClient.subjectMatches(pattern: "a.>", subject: "a.b") == true)
        #expect(MockNATSClient.subjectMatches(pattern: "a.>", subject: "a.b.c") == true)
        #expect(MockNATSClient.subjectMatches(pattern: "a.>", subject: "a.b.c.d") == true)
        // `>` requires at least one token after prefix
        #expect(MockNATSClient.subjectMatches(pattern: "a.>", subject: "b.c") == false)
    }

    @Test("Greater-than does not match zero tokens")
    func greaterThanRequiresOneToken() {
        // "a.>" should NOT match "a" (needs at least one more token)
        #expect(MockNATSClient.subjectMatches(pattern: "a.>", subject: "a") == false)
    }

    @Test("Pattern shorter than subject does not match")
    func shorterPatternNoMatch() {
        #expect(MockNATSClient.subjectMatches(pattern: "a.b", subject: "a.b.c") == false)
    }

    @Test("Pattern longer than subject does not match")
    func longerPatternNoMatch() {
        #expect(MockNATSClient.subjectMatches(pattern: "a.b.c", subject: "a.b") == false)
    }
}
