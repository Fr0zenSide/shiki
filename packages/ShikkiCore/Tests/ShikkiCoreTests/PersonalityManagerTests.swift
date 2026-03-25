import Foundation
import Testing
@testable import ShikkiCore

@Suite("PersonalityManager")
struct PersonalityManagerTests {

    private func tempPath() -> String {
        let dir = NSTemporaryDirectory() + "shikki-personality-\(UUID().uuidString)"
        return "\(dir)/personality.md"
    }

    @Test("Append observation creates file and writes entry")
    func appendObservation() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = PersonalityManager(personalityPath: path)
        try manager.observe("User prefers concise output")

        let content = try manager.loadPersonality()
        #expect(content.contains("# Personality Observations"))
        #expect(content.contains("User prefers concise output"))
    }

    @Test("Load round-trip preserves all observations")
    func loadRoundTrip() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = PersonalityManager(personalityPath: path)
        try manager.observe("Prefers parallel dispatch")
        try manager.observe("Dislikes verbose confirmations")

        let content = try manager.loadPersonality()
        #expect(content.contains("Prefers parallel dispatch"))
        #expect(content.contains("Dislikes verbose confirmations"))
    }

    @Test("Creates file if missing")
    func createsFileIfMissing() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = PersonalityManager(personalityPath: path)
        #expect(!FileManager.default.fileExists(atPath: path))

        try manager.observe("First observation")
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test("Count observations returns correct number")
    func countObservations() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = PersonalityManager(personalityPath: path)
        #expect(try manager.observationCount() == 0)

        try manager.observe("First")
        try manager.observe("Second")
        try manager.observe("Third")

        #expect(try manager.observationCount() == 3)
    }
}
