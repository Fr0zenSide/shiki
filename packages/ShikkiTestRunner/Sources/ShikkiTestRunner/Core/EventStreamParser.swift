// MARK: - EventStreamParser.swift
// ShikkiTestRunner — Parse swift test --experimental-event-stream-output JSON events

import Foundation

// MARK: - Public Models

/// Status of a test result.
public enum TestStatus: String, Sendable, Codable {
    case passed
    case failed
    case skipped
    case timeout
}

/// A parsed test event emitted by `swift test --experimental-event-stream-output`.
///
/// The event stream format uses a `kind` envelope with nested payload objects.
/// Each JSON line has the structure: `{"kind": "<kind>", "<kind>": { ... }}`.
public struct TestEvent: Sendable, Equatable {
    public let kind: Kind
    public let testID: String?
    public let suiteName: String?
    public let duration: Duration?
    public let errorMessage: String?
    public let errorFile: String?
    public let timestamp: Date

    public enum Kind: String, Sendable, Codable {
        case runStarted
        case testStarted
        case testPassed = "testCaseFinished_passed"
        case testFailed = "testCaseFinished_failed"
        case testSkipped = "testSkipped"
        case suiteStarted
        case suitePassed = "suiteFinished_passed"
        case suiteFailed = "suiteFinished_failed"
        case runFinished
    }

    public init(
        kind: Kind,
        testID: String? = nil,
        suiteName: String? = nil,
        duration: Duration? = nil,
        errorMessage: String? = nil,
        errorFile: String? = nil,
        timestamp: Date = Date()
    ) {
        self.kind = kind
        self.testID = testID
        self.suiteName = suiteName
        self.duration = duration
        self.errorMessage = errorMessage
        self.errorFile = errorFile
        self.timestamp = timestamp
    }
}

// MARK: - Raw JSON Wire Format

/// The raw JSON envelope from `swift test --experimental-event-stream-output`.
private struct RawEventEnvelope: Decodable {
    let kind: String
    let payload: RawPayload?

    enum CodingKeys: String, CodingKey {
        case kind
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        payload = try container.decodeIfPresent(RawPayload.self, forKey: .payload)
    }
}

private struct RawPayload: Decodable {
    let kind: String?
    let testID: String?
    let suiteName: String?
    let messages: [RawMessage]?
    let sourceLocation: RawSourceLocation?
    let duration: Double?
    let result: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case testID
        case suiteName
        case messages
        case sourceLocation
        case duration
        case result
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        testID = try container.decodeIfPresent(String.self, forKey: .testID)
        suiteName = try container.decodeIfPresent(String.self, forKey: .suiteName)
        messages = try container.decodeIfPresent([RawMessage].self, forKey: .messages)
        sourceLocation = try container.decodeIfPresent(RawSourceLocation.self, forKey: .sourceLocation)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        result = try container.decodeIfPresent(String.self, forKey: .result)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

private struct RawMessage: Decodable {
    let text: String?
}

private struct RawSourceLocation: Decodable {
    let file: String?
    let line: Int?
    let column: Int?

    var formatted: String? {
        guard let file else { return nil }
        var result = file
        if let line { result += ":\(line)" }
        if let column { result += ":\(column)" }
        return result
    }
}

// MARK: - EventStreamParser

/// Parses JSON lines from `swift test --experimental-event-stream-output`
/// into a stream of `TestEvent` values.
public struct EventStreamParser: Sendable {

    public init() {}

    /// Parse a single JSON line into a `TestEvent`, or `nil` if not a recognized event.
    public func parseLine(_ line: String) throws -> TestEvent? {
        let data = Data(line.utf8)
        return try parseData(data)
    }

    /// Parse raw JSON data into a `TestEvent`, or `nil` if not a recognized event.
    public func parseData(_ data: Data) throws -> TestEvent? {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(RawEventEnvelope.self, from: data)
        return mapEnvelope(envelope)
    }

    /// Parse an async sequence of lines into an `AsyncStream` of `TestEvent`.
    public func parseLines<S: AsyncSequence & Sendable>(
        _ lines: S
    ) -> AsyncThrowingStream<TestEvent, Error> where S.Element == String {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        if let event = try parseLine(trimmed) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private

    private func mapEnvelope(_ envelope: RawEventEnvelope) -> TestEvent? {
        let payload = envelope.payload

        let eventKind: TestEvent.Kind?
        let payloadKind = payload?.kind ?? envelope.kind
        let result = payload?.result

        switch payloadKind {
        case "runStarted":
            eventKind = .runStarted
        case "testStarted", "testCaseStarted":
            eventKind = .testStarted
        case "testCaseFinished", "testFinished", "testEnded":
            if result == "failed" {
                eventKind = .testFailed
            } else {
                eventKind = .testPassed
            }
        case "testPassed":
            eventKind = .testPassed
        case "testFailed":
            eventKind = .testFailed
        case "testSkipped":
            eventKind = .testSkipped
        case "suiteStarted":
            eventKind = .suiteStarted
        case "suiteFinished", "suiteEnded":
            if result == "failed" {
                eventKind = .suiteFailed
            } else {
                eventKind = .suitePassed
            }
        case "suitePassed":
            eventKind = .suitePassed
        case "suiteFailed":
            eventKind = .suiteFailed
        case "runFinished", "runEnded":
            eventKind = .runFinished
        default:
            return nil
        }

        guard let kind = eventKind else { return nil }

        let errorMessage = payload?.messages?.compactMap(\.text).joined(separator: "\n")

        let duration: Duration?
        if let secs = payload?.duration {
            let attoseconds = Int64(secs * 1_000_000_000) * 1_000_000_000
            duration = Duration(
                secondsComponent: Int64(secs),
                attosecondsComponent: attoseconds % 1_000_000_000_000_000_000
            )
        } else {
            duration = nil
        }

        return TestEvent(
            kind: kind,
            testID: payload?.testID ?? payload?.name,
            suiteName: payload?.suiteName,
            duration: duration,
            errorMessage: errorMessage?.isEmpty == true ? nil : errorMessage,
            errorFile: payload?.sourceLocation?.formatted,
            timestamp: Date()
        )
    }
}
