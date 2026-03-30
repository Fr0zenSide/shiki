import Foundation
import Testing

@testable import MayaKit

@Suite("InMemoryQualityStorage")
struct InMemoryQualityStorageTests {

    @Test("Save and fetch report")
    func saveAndFetch() async throws {
        let storage = InMemoryQualityStorage()
        let report = makeReport(date: .now)

        try await storage.save(report: report)
        let fetched = try await storage.fetchAllReports()

        #expect(fetched.count == 1)
        #expect(fetched.first?.id == report.id)
    }

    @Test("Fetch returns newest first")
    func newestFirst() async throws {
        let storage = InMemoryQualityStorage()
        let old = makeReport(date: Date(timeIntervalSince1970: 1000))
        let recent = makeReport(date: Date(timeIntervalSince1970: 2000))

        try await storage.save(report: old)
        try await storage.save(report: recent)

        let fetched = try await storage.fetchAllReports()
        #expect(fetched.count == 2)
        #expect(fetched.first?.rideDate == recent.rideDate)
    }

    @Test("Fetch by date range")
    func fetchByDateRange() async throws {
        let storage = InMemoryQualityStorage()
        let early = makeReport(date: Date(timeIntervalSince1970: 1000))
        let middle = makeReport(date: Date(timeIntervalSince1970: 2000))
        let late = makeReport(date: Date(timeIntervalSince1970: 3000))

        try await storage.save(report: early)
        try await storage.save(report: middle)
        try await storage.save(report: late)

        let fetched = try await storage.fetchReports(
            from: Date(timeIntervalSince1970: 1500),
            to: Date(timeIntervalSince1970: 2500)
        )
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == middle.id)
    }

    @Test("Delete report by ID")
    func deleteReport() async throws {
        let storage = InMemoryQualityStorage()
        let report = makeReport(date: .now)

        try await storage.save(report: report)
        try await storage.deleteReport(id: report.id)

        let fetched = try await storage.fetchAllReports()
        #expect(fetched.isEmpty)
    }

    @Test("Fetch nearest report by coordinate")
    func fetchNearestByCoordinate() async throws {
        let storage = InMemoryQualityStorage()

        let nearReport = makeReport(
            date: .now,
            coordinate: Coordinate(latitude: 45.0, longitude: 7.0)
        )
        let farReport = makeReport(
            date: .now,
            coordinate: Coordinate(latitude: 48.0, longitude: 10.0)
        )

        try await storage.save(report: nearReport)
        try await storage.save(report: farReport)

        let found = try await storage.fetchNearestReport(
            to: Coordinate(latitude: 45.001, longitude: 7.001),
            radiusMeters: 500
        )
        #expect(found?.id == nearReport.id)
    }

    @Test("Fetch nearest returns nil when nothing in radius")
    func fetchNearestReturnsNil() async throws {
        let storage = InMemoryQualityStorage()
        let found = try await storage.fetchNearestReport(
            to: Coordinate(latitude: 45.0, longitude: 7.0),
            radiusMeters: 100
        )
        #expect(found == nil)
    }

    @Test("Preloaded init works")
    func preloadedInit() async throws {
        let report = makeReport(date: .now)
        let storage = InMemoryQualityStorage(preloaded: [report])
        let fetched = try await storage.fetchAllReports()
        #expect(fetched.count == 1)
    }

    // MARK: - Helpers

    private func makeReport(
        date: Date,
        coordinate: Coordinate = Coordinate(latitude: 45.0, longitude: 7.0)
    ) -> QualityReport {
        let segment = TrailSegment(
            score: GroundQualityScore(value: 70, confidence: 0.8, surfaceType: .smooth, timestamp: date),
            startCoordinate: coordinate,
            endCoordinate: Coordinate(
                latitude: coordinate.latitude + 0.001,
                longitude: coordinate.longitude + 0.001
            ),
            startTimestamp: date,
            endTimestamp: date.addingTimeInterval(60),
            distanceMeters: 50,
            sampleCount: 5
        )
        return QualityReport(
            segments: [segment],
            rideDate: date,
            totalDistanceMeters: 50,
            durationSeconds: 60
        )
    }
}
