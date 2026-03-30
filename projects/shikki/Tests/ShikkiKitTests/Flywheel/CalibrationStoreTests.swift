import Foundation
import Testing
@testable import ShikkiKit

@Suite("CalibrationStore")
struct CalibrationStoreTests {

    private func makeTempStore() -> (CalibrationStore, URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-calibration-test-\(UUID().uuidString)")
        let path = tmpDir.appendingPathComponent("calibration.jsonl").path
        return (CalibrationStore(filePath: path), tmpDir)
    }

    // MARK: - Write & Read

    @Test("Append and load a single record")
    func appendAndLoad() async throws {
        let (store, tmpDir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let record = CalibrationRecord(
            predictedScore: 0.45,
            predictedTier: .medium,
            actualOutcome: .clean,
            fileExtension: ".swift",
            linesChanged: 100
        )

        try await store.append(record)
        let loaded = try await store.loadAll()

        #expect(loaded.count == 1)
        #expect(loaded[0].predictedScore == 0.45)
        #expect(loaded[0].predictedTier == .medium)
        #expect(loaded[0].actualOutcome == .clean)
    }

    @Test("Append multiple records")
    func appendMultiple() async throws {
        let (store, tmpDir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let records = (0..<5).map { i in
            CalibrationRecord(
                predictedScore: Double(i) * 0.2,
                predictedTier: RiskTier.from(score: Double(i) * 0.2),
                actualOutcome: .clean,
                fileExtension: ".swift",
                linesChanged: i * 10
            )
        }

        try await store.appendBatch(records)
        let loaded = try await store.loadAll()
        #expect(loaded.count == 5)
    }

    @Test("Count records without loading all")
    func countRecords() async throws {
        let (store, tmpDir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        for i in 0..<3 {
            try await store.append(CalibrationRecord(
                predictedScore: 0.5,
                predictedTier: .medium,
                actualOutcome: .clean,
                fileExtension: ".swift",
                linesChanged: i
            ))
        }

        let count = try await store.count()
        #expect(count == 3)
    }

    @Test("Empty store returns empty array")
    func emptyStore() async throws {
        let (store, tmpDir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let loaded = try await store.loadAll()
        #expect(loaded.isEmpty)

        let count = try await store.count()
        #expect(count == 0)
    }

    // MARK: - Date Range Queries

    @Test("Load records within date range")
    func dateRangeLoad() async throws {
        let (store, tmpDir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!

        // Record from 2 days ago
        try await store.append(CalibrationRecord(
            id: UUID(),
            timestamp: twoDaysAgo,
            predictedScore: 0.2,
            predictedTier: .low,
            actualOutcome: .clean,
            fileExtension: ".swift",
            linesChanged: 10
        ))

        // Record from now
        try await store.append(CalibrationRecord(
            id: UUID(),
            timestamp: now,
            predictedScore: 0.8,
            predictedTier: .critical,
            actualOutcome: .majorBug,
            fileExtension: ".js",
            linesChanged: 500
        ))

        let recent = try await store.load(from: yesterday, to: now)
        #expect(recent.count == 1)
        #expect(recent[0].predictedTier == .critical)
    }

    // MARK: - Statistics

    @Test("Compute stats from records")
    func computeStats() async throws {
        let (store, tmpDir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Perfect prediction: low tier, clean outcome
        try await store.append(CalibrationRecord(
            predictedScore: 0.1,
            predictedTier: .low,
            actualOutcome: .clean,
            fileExtension: ".swift",
            linesChanged: 10
        ))

        // Wrong prediction: low tier, major bug outcome
        try await store.append(CalibrationRecord(
            predictedScore: 0.1,
            predictedTier: .low,
            actualOutcome: .majorBug,
            fileExtension: ".swift",
            linesChanged: 200
        ))

        let stats = try await store.computeStats()
        #expect(stats.totalRecords == 2)
        #expect(stats.accuracy == 0.5) // 1/2 correct
        #expect(stats.tierDistribution["low"] == 2)
        #expect(stats.outcomeDistribution["clean"] == 1)
        #expect(stats.outcomeDistribution["majorBug"] == 1)
    }

    @Test("Empty stats")
    func emptyStats() async throws {
        let (store, tmpDir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let stats = try await store.computeStats()
        #expect(stats.totalRecords == 0)
        #expect(stats.accuracy == 0)
    }

    // MARK: - Rotation

    @Test("Rotation removes old records")
    func rotation() async throws {
        let (store, tmpDir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let old = Calendar.current.date(byAdding: .day, value: -100, to: Date())!
        let recent = Date()

        try await store.append(CalibrationRecord(
            id: UUID(), timestamp: old,
            predictedScore: 0.5, predictedTier: .medium,
            actualOutcome: .clean, fileExtension: ".swift", linesChanged: 10
        ))
        try await store.append(CalibrationRecord(
            id: UUID(), timestamp: recent,
            predictedScore: 0.3, predictedTier: .medium,
            actualOutcome: .clean, fileExtension: ".swift", linesChanged: 20
        ))

        let removed = try await store.rotate(keepDays: 90)
        #expect(removed == 1)

        let remaining = try await store.loadAll()
        #expect(remaining.count == 1)
    }

    // MARK: - Outcome Mapping

    @Test("Expected tier mapping")
    func expectedTierMapping() {
        #expect(CalibrationStore.expectedTier(for: .clean) == .low)
        #expect(CalibrationStore.expectedTier(for: .minorBug) == .medium)
        #expect(CalibrationStore.expectedTier(for: .majorBug) == .high)
        #expect(CalibrationStore.expectedTier(for: .reverted) == .critical)
        #expect(CalibrationStore.expectedTier(for: .testFailure) == .high)
    }

    @Test("Outcome score mapping")
    func outcomeScoreMapping() {
        #expect(CalibrationStore.outcomeScore(.clean) < CalibrationStore.outcomeScore(.minorBug))
        #expect(CalibrationStore.outcomeScore(.minorBug) < CalibrationStore.outcomeScore(.majorBug))
        #expect(CalibrationStore.outcomeScore(.majorBug) < CalibrationStore.outcomeScore(.reverted))
    }

    // MARK: - Record Properties

    @Test("CalibrationRecord has unique ID")
    func recordUniqueId() {
        let a = CalibrationRecord(predictedScore: 0.5, predictedTier: .medium, actualOutcome: .clean, fileExtension: ".swift", linesChanged: 10)
        let b = CalibrationRecord(predictedScore: 0.5, predictedTier: .medium, actualOutcome: .clean, fileExtension: ".swift", linesChanged: 10)
        #expect(a.id != b.id)
    }

    @Test("OutcomeType all cases")
    func outcomeTypes() {
        let types: [OutcomeType] = [.clean, .minorBug, .majorBug, .reverted, .testFailure]
        #expect(types.count == 5)
    }
}
