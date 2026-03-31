import Foundation
import Testing

@testable import ShikkiTestRunner

@Suite("AgentTestHandoff")
struct AgentTestHandoffTests {

    // MARK: - Report Creation

    @Test("Create report with all fields")
    func createReportAllFields() {
        let report = AgentTestReport(
            agentID: "w2-1-nats",
            branch: "feature/nats-reconnect",
            commit: "abc123f",
            scopes: ["nats", "observatory"],
            attempt: 2,
            isRacer: true,
            wonRace: false,
            tmpDBPath: "/tmp/shikki-test-w2-1-nats.sqlite"
        )

        #expect(report.agentID == "w2-1-nats")
        #expect(report.branch == "feature/nats-reconnect")
        #expect(report.commit == "abc123f")
        #expect(report.scopes == ["nats", "observatory"])
        #expect(report.attempt == 2)
        #expect(report.isRacer == true)
        #expect(report.wonRace == false)
        #expect(report.tmpDBPath == "/tmp/shikki-test-w2-1-nats.sqlite")
    }

    @Test("Default values for optional fields")
    func defaultValues() {
        let report = AgentTestReport(
            agentID: "w1-kernel",
            branch: "feature/kernel-fix",
            commit: "def456",
            scopes: ["kernel"],
            tmpDBPath: "/tmp/test.sqlite"
        )

        #expect(report.attempt == 1)
        #expect(report.isRacer == false)
        #expect(report.wonRace == false)
    }

    @Test("Report is Codable round-trip")
    func reportCodable() throws {
        let original = AgentTestReport(
            agentID: "w3-tui",
            branch: "feature/tui-progress",
            commit: "789abc",
            scopes: ["tui"],
            attempt: 1,
            isRacer: false,
            wonRace: false,
            tmpDBPath: "/tmp/shikki-test-w3-tui.sqlite",
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentTestReport.self, from: data)

        #expect(decoded.agentID == original.agentID)
        #expect(decoded.branch == original.branch)
        #expect(decoded.commit == original.commit)
        #expect(decoded.scopes == original.scopes)
        #expect(decoded.attempt == original.attempt)
        #expect(decoded.isRacer == original.isRacer)
        #expect(decoded.wonRace == original.wonRace)
        #expect(decoded.tmpDBPath == original.tmpDBPath)
    }

    // MARK: - Convenience Factory

    @Test("Factory creates report with standard tmp path")
    func factoryCreateReport() {
        let handoff = AgentTestHandoff()
        let report = handoff.createReport(
            agentID: "w5-dispatch",
            branch: "feature/test-runner-w5",
            commit: "aaa111",
            scopes: ["nats", "kernel"]
        )

        #expect(report.agentID == "w5-dispatch")
        #expect(report.tmpDBPath.contains("shikki-test-w5-dispatch"))
        #expect(report.tmpDBPath.hasSuffix(".sqlite"))
        #expect(report.attempt == 1)
        #expect(report.isRacer == false)
    }

    @Test("Factory creates racer report")
    func factoryRacerReport() {
        let handoff = AgentTestHandoff()
        let report = handoff.createReport(
            agentID: "w3-racer-a",
            branch: "feature/parallel-race",
            commit: "bbb222",
            scopes: ["safety"],
            isRacer: true,
            wonRace: true
        )

        #expect(report.isRacer == true)
        #expect(report.wonRace == true)
    }

    // MARK: - Merge

    @Test("Merge agent report into persistent DB")
    func mergeAgentReport() throws {
        // Create agent's temp DB with a test run
        let tmpPath = NSTemporaryDirectory() + "shikki-test-merge-\(UUID().uuidString).sqlite"
        let historyPath = NSTemporaryDirectory() + "shikki-history-merge-\(UUID().uuidString).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: tmpPath)
            try? FileManager.default.removeItem(atPath: historyPath)
        }

        // Populate temp DB
        let tmpStore = try SQLiteStore(path: tmpPath)
        let runID = try tmpStore.recordRun(gitHash: "abc123", branch: "feature/test")
        let groupID = try tmpStore.recordGroup(runID: runID, scope: "nats")
        try tmpStore.recordResult(
            runID: runID,
            groupID: groupID,
            testFile: "NATSTests.swift",
            testName: "testConnection",
            status: .passed,
            durationMs: 42
        )
        try tmpStore.finishGroup(groupID: groupID, totalTests: 1, passed: 1, failed: 0, skipped: 0, durationMs: 42)
        try tmpStore.finishRun(runID: runID, totalTests: 1, passed: 1, failed: 0, skipped: 0, durationMs: 42)

        // Create report and merge
        let report = AgentTestReport(
            agentID: "w2-nats",
            branch: "feature/test",
            commit: "abc123",
            scopes: ["nats"],
            attempt: 1,
            isRacer: false,
            wonRace: false,
            tmpDBPath: tmpPath
        )

        let handoff = AgentTestHandoff()
        let mergedCount = try handoff.mergeAgentReport(
            report: report,
            historyDBPath: historyPath
        )

        #expect(mergedCount == 1)

        // Verify the persistent DB has the data with agent metadata
        let historyStore = try SQLiteStore(path: historyPath)
        let runs = try historyStore.allRuns()
        #expect(runs.count == 1)
        #expect(runs[0].agentID == "w2-nats")
        #expect(runs[0].attempt == 1)
        #expect(runs[0].isRacer == false)
        #expect(runs[0].wonRace == false)

        let results = try historyStore.resultsForRun(runs[0].runID)
        #expect(results.count == 1)
        #expect(results[0].testName == "testConnection")
        #expect(results[0].status == .passed)
    }

    @Test("Merge tags racer metadata correctly")
    func mergeRacerMetadata() throws {
        let tmpPath = NSTemporaryDirectory() + "shikki-test-racer-\(UUID().uuidString).sqlite"
        let historyPath = NSTemporaryDirectory() + "shikki-history-racer-\(UUID().uuidString).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: tmpPath)
            try? FileManager.default.removeItem(atPath: historyPath)
        }

        let tmpStore = try SQLiteStore(path: tmpPath)
        let runID = try tmpStore.recordRun(gitHash: "def456", branch: "feature/race")
        try tmpStore.recordResult(
            runID: runID,
            testFile: "SafetyTests.swift",
            testName: "testACL",
            status: .passed,
            durationMs: 10
        )

        let report = AgentTestReport(
            agentID: "w3-racer-b",
            branch: "feature/race",
            commit: "def456",
            scopes: ["safety"],
            attempt: 3,
            isRacer: true,
            wonRace: true,
            tmpDBPath: tmpPath
        )

        let handoff = AgentTestHandoff()
        try handoff.mergeAgentReport(report: report, historyDBPath: historyPath)

        let historyStore = try SQLiteStore(path: historyPath)
        let runs = try historyStore.allRuns()
        #expect(runs.count == 1)
        #expect(runs[0].agentID == "w3-racer-b")
        #expect(runs[0].attempt == 3)
        #expect(runs[0].isRacer == true)
        #expect(runs[0].wonRace == true)
    }
}
