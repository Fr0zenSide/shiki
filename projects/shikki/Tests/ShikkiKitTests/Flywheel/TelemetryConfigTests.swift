import Foundation
import Testing

@testable import ShikkiKit

@Suite("TelemetryConfig")
struct TelemetryConfigTests {

    @Test("Default config uses local telemetry level")
    func defaultConfig() {
        let config = TelemetryConfig()
        #expect(config.level == .local)
        #expect(config.consentDate == nil)
        #expect(config.lastSyncDate == nil)
        #expect(!config.installId.isEmpty)
    }

    @Test("Default shared categories include risk, watchdog, task outcomes")
    func defaultSharedCategories() {
        let defaults = OutcomeCategory.defaultShared
        #expect(defaults.contains(.riskScores))
        #expect(defaults.contains(.watchdogPatterns))
        #expect(defaults.contains(.taskOutcomes))
        #expect(!defaults.contains(.promptEffectiveness))
        #expect(!defaults.contains(.specPatterns))
    }

    @Test("TelemetryLevel has all expected cases")
    func telemetryLevelCases() {
        let cases = TelemetryLevel.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.community))
        #expect(cases.contains(.local))
        #expect(cases.contains(.off))
    }

    @Test("OutcomeCategory has all expected cases")
    func outcomeCategoryCases() {
        let cases = OutcomeCategory.allCases
        #expect(cases.count == 5)
    }

    @Test("Config roundtrips through JSON")
    func jsonRoundTrip() throws {
        let config = TelemetryConfig(
            level: .community,
            installId: "test-123",
            consentDate: Date(timeIntervalSince1970: 1_700_000_000),
            lastSyncDate: Date(timeIntervalSince1970: 1_700_001_000),
            sharedCategories: [.riskScores, .watchdogPatterns]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TelemetryConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test("TelemetryConfigStore persists and loads config")
    func storePersistence() async throws {
        let tempPath = NSTemporaryDirectory() + "shikki-test-telemetry-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let store = TelemetryConfigStore(filePath: tempPath)
        try await store.setLevel(.community)
        let config = await store.current()
        #expect(config.level == .community)
        #expect(config.consentDate != nil)

        // Reload from disk
        let store2 = TelemetryConfigStore(filePath: tempPath)
        let config2 = await store2.current()
        #expect(config2.level == .community)
        #expect(config2.installId == config.installId)
    }

    @Test("TelemetryConfigStore sharing check")
    func sharingCheck() async throws {
        let tempPath = NSTemporaryDirectory() + "shikki-test-sharing-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let store = TelemetryConfigStore(filePath: tempPath)

        // Default (local) — sharing not allowed
        let allowed = await store.isSharingAllowed(for: .riskScores)
        #expect(!allowed)

        // Set to community
        try await store.setLevel(.community)
        let allowedNow = await store.isSharingAllowed(for: .riskScores)
        #expect(allowedNow)

        // Not in default shared
        let promptAllowed = await store.isSharingAllowed(for: .promptEffectiveness)
        #expect(!promptAllowed)
    }

    @Test("TelemetryConfigStore collection enabled check")
    func collectionEnabled() async throws {
        let tempPath = NSTemporaryDirectory() + "shikki-test-collection-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let store = TelemetryConfigStore(filePath: tempPath)

        // Default (local) — collection enabled
        let enabled = await store.isCollectionEnabled()
        #expect(enabled)

        // Set to off
        try await store.setLevel(.off)
        let disabled = await store.isCollectionEnabled()
        #expect(!disabled)
    }

    @Test("TelemetryConfigStore set shared categories")
    func setSharedCategories() async throws {
        let tempPath = NSTemporaryDirectory() + "shikki-test-categories-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let store = TelemetryConfigStore(filePath: tempPath)
        try await store.setLevel(.community)
        try await store.setSharedCategories([.promptEffectiveness, .specPatterns])

        let config = await store.current()
        #expect(config.sharedCategories.contains(.promptEffectiveness))
        #expect(config.sharedCategories.contains(.specPatterns))
        #expect(!config.sharedCategories.contains(.riskScores))
    }

    @Test("TelemetryConfigStore recordSync updates date")
    func recordSync() async throws {
        let tempPath = NSTemporaryDirectory() + "shikki-test-sync-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let store = TelemetryConfigStore(filePath: tempPath)
        let before = await store.current()
        #expect(before.lastSyncDate == nil)

        try await store.recordSync()
        let after = await store.current()
        #expect(after.lastSyncDate != nil)
    }
}
