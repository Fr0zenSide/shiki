import Foundation
import Testing

@testable import ShikkiKit

@Suite("CommandLogger")
struct CommandLoggerTests {
    /// Create a fresh temp directory for each test.
    private func makeTempLogDir() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-cmdlog-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private func readLines(_ path: String) -> [String] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private func decodeEntry(_ jsonLine: String) -> CommandLogEntry? {
        guard let data = jsonLine.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(CommandLogEntry.self, from: data)
    }

    // MARK: - start + complete writes one line to JSONL

    @Test("start + complete writes one line to JSONL file")
    func startAndCompleteWritesOneLine() throws {
        let dir = makeTempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let token = CommandLogger.start(command: "shi inbox", workspace: "wabisabi", logDir: dir)
        CommandLogger.complete(token, exitCode: 0)

        let logPath = "\(dir)/command-history.jsonl"
        let lines = readLines(logPath)
        #expect(lines.count == 1)
    }

    // MARK: - Log entry has correct command name

    @Test("log entry has correct command name")
    func logEntryHasCorrectCommandName() throws {
        let dir = makeTempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let token = CommandLogger.start(command: "shi spec", workspace: nil, logDir: dir)
        CommandLogger.complete(token, exitCode: 0)

        let lines = readLines("\(dir)/command-history.jsonl")
        let entry = try #require(decodeEntry(lines[0]))
        #expect(entry.cmd == "shi spec")
    }

    // MARK: - Log entry has duration_ms > 0

    @Test("log entry has duration_ms > 0")
    func logEntryHasDuration() throws {
        let dir = makeTempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let token = CommandLogger.start(command: "shi quick", workspace: nil, logDir: dir)
        // Small delay to ensure measurable duration
        Thread.sleep(forTimeInterval: 0.01)
        CommandLogger.complete(token, exitCode: 0)

        let lines = readLines("\(dir)/command-history.jsonl")
        let entry = try #require(decodeEntry(lines[0]))
        #expect(entry.duration_ms > 0)
    }

    // MARK: - Log entry has exit code

    @Test("log entry has exit code")
    func logEntryHasExitCode() throws {
        let dir = makeTempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let token = CommandLogger.start(command: "shi ship", workspace: nil, logDir: dir)
        CommandLogger.complete(token, exitCode: 42)

        let lines = readLines("\(dir)/command-history.jsonl")
        let entry = try #require(decodeEntry(lines[0]))
        #expect(entry.exit == 42)
    }

    // MARK: - Workspace detected from $SHI_WS when set

    @Test("workspace detected from SHI_WS environment variable")
    func workspaceDetectedFromEnv() throws {
        let dir = makeTempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        // Test the detectWorkspace helper directly with a known path
        let cwd = FileManager.default.currentDirectoryPath
        let ws = CommandLogger.detectWorkspace(cwd: cwd, shiWs: cwd)
        // cwd == shiWs, so relative is empty → no workspace component
        #expect(ws == nil)

        // Simulate cwd being inside a workspace subtree
        let parentDir = (cwd as NSString).deletingLastPathComponent
        let ws2 = CommandLogger.detectWorkspace(
            cwd: cwd,
            shiWs: parentDir
        )
        // The first component after parentDir should be the folder name
        let expected = (cwd as NSString).lastPathComponent
        #expect(ws2 == expected)
    }

    // MARK: - Workspace nil when $SHI_WS not set

    @Test("workspace nil when SHI_WS is not set")
    func workspaceNilWithoutEnv() {
        let ws = CommandLogger.detectWorkspace(cwd: "/some/path", shiWs: nil)
        #expect(ws == nil)
    }

    // MARK: - Multiple commands append (don't overwrite)

    @Test("multiple commands append without overwriting")
    func multipleCommandsAppend() throws {
        let dir = makeTempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let token1 = CommandLogger.start(command: "shi inbox", workspace: nil, logDir: dir)
        CommandLogger.complete(token1, exitCode: 0)

        let token2 = CommandLogger.start(command: "shi spec", workspace: nil, logDir: dir)
        CommandLogger.complete(token2, exitCode: 0)

        let token3 = CommandLogger.start(command: "shi quick", workspace: nil, logDir: dir)
        CommandLogger.complete(token3, exitCode: 1)

        let lines = readLines("\(dir)/command-history.jsonl")
        #expect(lines.count == 3)

        let entry1 = try #require(decodeEntry(lines[0]))
        let entry2 = try #require(decodeEntry(lines[1]))
        let entry3 = try #require(decodeEntry(lines[2]))

        #expect(entry1.cmd == "shi inbox")
        #expect(entry2.cmd == "shi spec")
        #expect(entry3.cmd == "shi quick")
        #expect(entry3.exit == 1)
    }

    // MARK: - Creates logs directory if missing

    @Test("creates logs directory if missing")
    func createsLogsDirectoryIfMissing() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-cmdlog-test-\(UUID().uuidString)")
        let dir = base.appendingPathComponent("nested/logs").path
        defer { try? FileManager.default.removeItem(at: base) }

        let token = CommandLogger.start(command: "shi review", workspace: nil, logDir: dir)
        CommandLogger.complete(token, exitCode: 0)

        let logPath = "\(dir)/command-history.jsonl"
        #expect(FileManager.default.fileExists(atPath: logPath))
    }

    // MARK: - Log entry is valid JSON (parseable back to CommandLogEntry)

    @Test("log entry is valid JSON parseable to CommandLogEntry")
    func logEntryIsValidJSON() throws {
        let dir = makeTempLogDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let token = CommandLogger.start(command: "shi dispatch", workspace: "brainy", logDir: dir)
        CommandLogger.complete(token, exitCode: 0)

        let lines = readLines("\(dir)/command-history.jsonl")
        #expect(lines.count == 1)

        let entry = try #require(decodeEntry(lines[0]))
        #expect(entry.cmd == "shi dispatch")
        #expect(entry.ws == "brainy")
        #expect(entry.exit == 0)
        // ISO8601 timestamp should be non-empty
        #expect(!entry.ts.isEmpty)
        // Should contain fractional seconds
        #expect(entry.ts.contains("."))
    }
}
