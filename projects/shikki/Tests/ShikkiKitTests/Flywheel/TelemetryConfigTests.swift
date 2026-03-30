import Foundation
import Testing
@testable import ShikkiKit

@Suite("TelemetryConfig")
struct TelemetryConfigTests {

    // MARK: - TelemetryLevel

    @Test("Default level is local")
    func defaultLevel() {
        let config = TelemetryConfig()
        #expect(config.level == .local)
    }

    @Test("All telemetry levels are available")
    func allLevels() {
        let levels = TelemetryLevel.allCases
        #expect(levels.count == 3)
        #expect(levels.contains(.community))
        #expect(levels.contains(.local))
        #expect(levels.contains(.off))
    }

    @Test("Collection enabled for local and community")
    func collectionEnabled() {
        let local = TelemetryConfig(level: .local)
        let community = TelemetryConfig(level: .community)
        let off = TelemetryConfig(level: .off)

        #expect(local.isCollectionEnabled == true)
        #expect(community.isCollectionEnabled == true)
        #expect(off.isCollectionEnabled == false)
    }

    @Test("Sharing enabled only for community")
    func sharingEnabled() {
        let local = TelemetryConfig(level: .local)
        let community = TelemetryConfig(level: .community)
        let off = TelemetryConfig(level: .off)

        #expect(local.isSharingEnabled == false)
        #expect(community.isSharingEnabled == true)
        #expect(off.isSharingEnabled == false)
    }

    @Test("Config has unique install ID")
    func uniqueInstallId() {
        let a = TelemetryConfig()
        let b = TelemetryConfig()
        #expect(a.installId != b.installId)
    }

    @Test("Config version is current")
    func configVersion() {
        let config = TelemetryConfig()
        #expect(config.version == TelemetryConfig.currentVersion)
    }

    // MARK: - TelemetryConfigStore

    @Test("Store round-trips config")
    func storeRoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-test-\(UUID().uuidString)")
        let path = tmpDir.appendingPathComponent("telemetry.json").path

        let store = TelemetryConfigStore(configPath: path)
        var config = TelemetryConfig(level: .community)
        config.consentDate = Date()
        try store.save(config)

        let loaded = try store.load()
        #expect(loaded.level == .community)
        #expect(loaded.installId == config.installId)
        #expect(loaded.isSharingEnabled == true)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @Test("Store returns default when no file exists")
    func storeDefaultWhenMissing() throws {
        let store = TelemetryConfigStore(configPath: "/tmp/nonexistent-\(UUID().uuidString)/config.json")
        let config = try store.load()
        #expect(config.level == .local)
    }

    @Test("setLevel preserves install ID")
    func setLevelPreservesInstallId() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-test-\(UUID().uuidString)")
        let path = tmpDir.appendingPathComponent("telemetry.json").path

        let store = TelemetryConfigStore(configPath: path)

        // Set initial level
        let first = try store.setLevel(.local)
        let installId = first.installId

        // Change level
        let second = try store.setLevel(.community)
        #expect(second.installId == installId)
        #expect(second.level == .community)
        #expect(second.consentDate != nil)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @Test("setLevel to community sets consent date")
    func setLevelCommunityConsent() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-test-\(UUID().uuidString)")
        let path = tmpDir.appendingPathComponent("telemetry.json").path
        let store = TelemetryConfigStore(configPath: path)

        let before = Date()
        let config = try store.setLevel(.community)
        let after = Date()

        #expect(config.consentDate != nil)
        #expect(config.consentDate! >= before)
        #expect(config.consentDate! <= after)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Codable

    @Test("TelemetryLevel round-trips via JSON")
    func levelCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for level in TelemetryLevel.allCases {
            let data = try encoder.encode(level)
            let decoded = try decoder.decode(TelemetryLevel.self, from: data)
            #expect(decoded == level)
        }
    }
}
