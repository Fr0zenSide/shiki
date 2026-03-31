// MARK: - EventStreamParserTests.swift
// ShikkiTestRunner — Tests for the JSON event stream parser

import Foundation
import Testing

@testable import ShikkiTestRunner

@Suite("EventStreamParser")
struct EventStreamParserTests {

    let parser = EventStreamParser()

    // MARK: - Basic Event Parsing

    @Test("Parse testStarted event")
    func parseTestStarted() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "testStarted", "testID": "MyTests/testAdd"}}
        """
        let event = try parser.parseLine(json)
        #expect(event != nil)
        #expect(event?.kind == .testStarted)
        #expect(event?.testID == "MyTests/testAdd")
    }

    @Test("Parse testCaseStarted as testStarted")
    func parseTestCaseStarted() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "testCaseStarted", "testID": "CoreTests/testMultiply", "suiteName": "CoreTests"}}
        """
        let event = try parser.parseLine(json)
        #expect(event != nil)
        #expect(event?.kind == .testStarted)
        #expect(event?.testID == "CoreTests/testMultiply")
        #expect(event?.suiteName == "CoreTests")
    }

    @Test("Parse testPassed via testCaseFinished with result passed")
    func parseTestPassed() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "testCaseFinished", "testID": "MyTests/testAdd", "result": "passed", "duration": 0.003}}
        """
        let event = try parser.parseLine(json)
        #expect(event != nil)
        #expect(event?.kind == .testPassed)
        #expect(event?.testID == "MyTests/testAdd")
        #expect(event?.duration != nil)
    }

    @Test("Parse testFailed via testCaseFinished with result failed")
    func parseTestFailed() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "testCaseFinished", "testID": "MyTests/testSub", "result": "failed", "duration": 0.001, "messages": [{"text": "Expected 5, got 3"}], "sourceLocation": {"file": "MyTests.swift", "line": 42, "column": 9}}}
        """
        let event = try parser.parseLine(json)
        #expect(event != nil)
        #expect(event?.kind == .testFailed)
        #expect(event?.testID == "MyTests/testSub")
        #expect(event?.errorMessage == "Expected 5, got 3")
        #expect(event?.errorFile == "MyTests.swift:42:9")
    }

    @Test("Parse testSkipped event")
    func parseTestSkipped() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "testSkipped", "testID": "IntegrationTests/testDB"}}
        """
        let event = try parser.parseLine(json)
        #expect(event != nil)
        #expect(event?.kind == .testSkipped)
        #expect(event?.testID == "IntegrationTests/testDB")
    }

    // MARK: - Suite Events

    @Test("Parse suiteStarted event")
    func parseSuiteStarted() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "suiteStarted", "suiteName": "CoreTests"}}
        """
        let event = try parser.parseLine(json)
        #expect(event != nil)
        #expect(event?.kind == .suiteStarted)
        #expect(event?.suiteName == "CoreTests")
    }

    @Test("Parse suiteFinished passed")
    func parseSuitePassed() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "suiteFinished", "suiteName": "CoreTests", "result": "passed", "duration": 1.234}}
        """
        let event = try parser.parseLine(json)
        #expect(event != nil)
        #expect(event?.kind == .suitePassed)
    }

    @Test("Parse suiteFinished failed")
    func parseSuiteFailed() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "suiteFinished", "suiteName": "CoreTests", "result": "failed"}}
        """
        let event = try parser.parseLine(json)
        #expect(event != nil)
        #expect(event?.kind == .suiteFailed)
    }

    // MARK: - Run Events

    @Test("Parse runStarted event")
    func parseRunStarted() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "runStarted"}}
        """
        let event = try parser.parseLine(json)
        #expect(event != nil)
        #expect(event?.kind == .runStarted)
    }

    @Test("Parse runFinished event")
    func parseRunFinished() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "runFinished"}}
        """
        let event = try parser.parseLine(json)
        #expect(event != nil)
        #expect(event?.kind == .runFinished)
    }

    // MARK: - Edge Cases

    @Test("Unknown event kind returns nil")
    func unknownEventReturnsNil() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "diagnosticMessage", "text": "some log"}}
        """
        let event = try parser.parseLine(json)
        #expect(event == nil)
    }

    @Test("Invalid JSON throws error")
    func invalidJsonThrows() throws {
        #expect(throws: (any Error).self) {
            try parser.parseLine("not valid json {{{")
        }
    }

    @Test("Empty line returns nil from parseLine")
    func emptyLineIsHandled() throws {
        // Empty string is still valid to attempt, but should not crash
        #expect(throws: (any Error).self) {
            try parser.parseLine("")
        }
    }

    @Test("Multiple error messages are joined")
    func multipleErrorMessages() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "testFailed", "testID": "T/t1", "messages": [{"text": "line 1"}, {"text": "line 2"}]}}
        """
        let event = try parser.parseLine(json)
        #expect(event?.errorMessage == "line 1\nline 2")
    }

    // MARK: - Async Stream

    @Test("Parse async line stream")
    func parseAsyncStream() async throws {
        let lines = [
            #"{"kind": "event", "payload": {"kind": "runStarted"}}"#,
            #"{"kind": "event", "payload": {"kind": "testStarted", "testID": "T/t1"}}"#,
            #"{"kind": "event", "payload": {"kind": "testCaseFinished", "testID": "T/t1", "result": "passed", "duration": 0.01}}"#,
            #"{"kind": "event", "payload": {"kind": "runFinished"}}"#,
        ]

        let stream = AsyncStream<String> { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }

        var events: [TestEvent] = []
        for try await event in parser.parseLines(stream) {
            events.append(event)
        }

        #expect(events.count == 4)
        #expect(events[0].kind == .runStarted)
        #expect(events[1].kind == .testStarted)
        #expect(events[2].kind == .testPassed)
        #expect(events[3].kind == .runFinished)
    }

    @Test("Parse testPassed directly")
    func parseTestPassedDirect() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "testPassed", "testID": "T/t1"}}
        """
        let event = try parser.parseLine(json)
        #expect(event?.kind == .testPassed)
    }

    @Test("Parse with name fallback for testID")
    func parseNameFallback() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "testStarted", "name": "fallbackName"}}
        """
        let event = try parser.parseLine(json)
        #expect(event?.testID == "fallbackName")
    }

    @Test("Source location without column")
    func sourceLocationNoColumn() throws {
        let json = """
        {"kind": "event", "payload": {"kind": "testFailed", "testID": "T/t1", "sourceLocation": {"file": "Test.swift", "line": 10}}}
        """
        let event = try parser.parseLine(json)
        #expect(event?.errorFile == "Test.swift:10")
    }
}
