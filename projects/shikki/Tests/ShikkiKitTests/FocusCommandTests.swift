import Foundation
import Testing
@testable import ShikkiKit

@Suite("FocusCommand — BR-EM-14 focus mode")
struct FocusCommandTests {

    // MARK: - Helpers

    /// Creates a temporary directory unique per test invocation.
    private func makeTempDir() throws -> String {
        let base = FileManager.default.temporaryDirectory.path
        let dir = "\(base)/shikki-focus-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - testFocusStart_createsStateFile

    @Test("focus start creates state file on disk")
    func testFocusStart_createsStateFile() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let manager = FocusManager(directory: dir)
        let state = FocusState(startedAt: Date(), durationSeconds: 1200, active: true)
        try manager.save(state)

        let loaded = try manager.load()
        #expect(loaded != nil)
        #expect(loaded?.active == true)
        #expect(loaded?.durationSeconds == 1200)
    }

    // MARK: - testFocusWithDuration_parsesMinutes

    @Test("DurationParser parses minutes correctly")
    func testFocusWithDuration_parsesMinutes() {
        let result = DurationParser.parse("20m")
        #expect(result == 1200.0)
    }

    // MARK: - testFocusWithDuration_parsesSeconds

    @Test("DurationParser parses seconds correctly")
    func testFocusWithDuration_parsesSeconds() {
        let result = DurationParser.parse("90s")
        #expect(result == 90.0)
    }

    // MARK: - testFocusStop_removesStateFile

    @Test("focus stop removes state file")
    func testFocusStop_removesStateFile() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let manager = FocusManager(directory: dir)

        // Save an active state
        let state = FocusState(startedAt: Date(), durationSeconds: 600, active: true)
        try manager.save(state)
        #expect(manager.isActive() == true)

        // Delete (simulates `focus stop`)
        try manager.delete()
        #expect(manager.isActive() == false)

        let loaded = try manager.load()
        #expect(loaded == nil)
    }

    // MARK: - testFocusNoArgs_showsElapsed (when active)

    @Test("focus with no args reflects active state")
    func testFocusNoArgs_showsElapsed() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let manager = FocusManager(directory: dir)
        let start = Date().addingTimeInterval(-300) // 5 minutes ago
        let state = FocusState(startedAt: start, durationSeconds: 1200, active: true)
        try manager.save(state)

        let loaded = try manager.load()
        #expect(loaded?.active == true)

        let elapsed = Date().timeIntervalSince(loaded!.startedAt)
        #expect(elapsed >= 299.0) // at least ~5 minutes
    }

    // MARK: - testFocusNoArgs_showsNotActive (when inactive)

    @Test("focus with no args shows not active when no state file")
    func testFocusNoArgs_showsNotActive() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let manager = FocusManager(directory: dir)
        #expect(manager.isActive() == false)

        let loaded = try manager.load()
        #expect(loaded == nil)
    }

    // MARK: - testDurationParsing_10s_20m_1h

    @Test("DurationParser handles 10s, 20m, 1h, bare number, invalid")
    func testDurationParsing_10s_20m_1h() {
        #expect(DurationParser.parse("10s") == 10.0)
        #expect(DurationParser.parse("20m") == 1200.0)
        #expect(DurationParser.parse("1h") == 3600.0)
        #expect(DurationParser.parse("90") == 90.0)   // bare number → seconds
        #expect(DurationParser.parse("stop") == nil)
        #expect(DurationParser.parse("") == nil)
        #expect(DurationParser.parse("2h") == 7200.0)
        #expect(DurationParser.parse("1.5h") == 5400.0)
        #expect(DurationParser.parse("30m") == 1800.0)
    }
}
