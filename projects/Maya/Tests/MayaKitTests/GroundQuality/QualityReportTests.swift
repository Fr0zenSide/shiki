import Foundation
import Testing

@testable import MayaKit

@Suite("QualityReport")
struct QualityReportTests {

    @Test("Average score is distance-weighted")
    func averageScoreWeighted() {
        let date = Date.now
        let segments = [
            makeSegment(score: 80, distance: 100, surface: .smooth, date: date),
            makeSegment(score: 40, distance: 100, surface: .rocky, date: date),
        ]

        let report = QualityReport(
            segments: segments,
            rideDate: date,
            totalDistanceMeters: 200,
            durationSeconds: 600
        )

        // (80*100 + 40*100) / 200 = 60
        #expect(report.averageScore == 60)
    }

    @Test("Average score with empty segments is zero")
    func emptySegmentsZero() {
        let report = QualityReport(
            segments: [],
            rideDate: .now,
            totalDistanceMeters: 0,
            durationSeconds: 0
        )
        #expect(report.averageScore == 0)
    }

    @Test("Overall tier matches average score")
    func overallTier() {
        let date = Date.now
        let segments = [makeSegment(score: 85, distance: 100, surface: .smooth, date: date)]
        let report = QualityReport(
            segments: segments,
            rideDate: date,
            totalDistanceMeters: 100,
            durationSeconds: 300
        )
        #expect(report.overallTier == .excellent)
    }

    @Test("Surface distribution sums to 1.0")
    func surfaceDistributionSumsToOne() {
        let date = Date.now
        let segments = [
            makeSegment(score: 80, distance: 60, surface: .smooth, date: date),
            makeSegment(score: 50, distance: 30, surface: .gravel, date: date),
            makeSegment(score: 30, distance: 10, surface: .rocky, date: date),
        ]

        let report = QualityReport(
            segments: segments,
            rideDate: date,
            totalDistanceMeters: 100,
            durationSeconds: 600
        )

        let total = report.surfaceDistribution.values.reduce(0, +)
        #expect(abs(total - 1.0) < 0.001)
    }

    @Test("Best and worst segments identified correctly")
    func bestAndWorstSegments() {
        let date = Date.now
        let bestSeg = makeSegment(score: 95, distance: 50, surface: .smooth, date: date)
        let worstSeg = makeSegment(score: 15, distance: 50, surface: .mud, date: date)

        let report = QualityReport(
            segments: [bestSeg, worstSeg],
            rideDate: date,
            totalDistanceMeters: 100,
            durationSeconds: 300
        )

        #expect(report.bestSegment?.score.value == 95)
        #expect(report.worstSegment?.score.value == 15)
    }

    @Test("Empty distribution for zero distance")
    func emptyDistribution() {
        let report = QualityReport(
            segments: [],
            rideDate: .now,
            totalDistanceMeters: 0,
            durationSeconds: 0
        )
        #expect(report.surfaceDistribution.isEmpty)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let segment = makeSegment(score: 70, distance: 100, surface: .gravel, date: date)
        let report = QualityReport(
            segments: [segment],
            rideDate: date,
            totalDistanceMeters: 100,
            durationSeconds: 600
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(QualityReport.self, from: data)

        #expect(decoded.id == report.id)
        #expect(decoded.segments.count == 1)
        #expect(decoded.averageScore == report.averageScore)
    }

    // MARK: - Helpers

    private func makeSegment(
        score: Int,
        distance: Double,
        surface: SurfaceType,
        date: Date
    ) -> TrailSegment {
        TrailSegment(
            score: GroundQualityScore(value: score, confidence: 0.8, surfaceType: surface, timestamp: date),
            startCoordinate: Coordinate(latitude: 45.0, longitude: 7.0),
            endCoordinate: Coordinate(latitude: 45.001, longitude: 7.001),
            startTimestamp: date,
            endTimestamp: date.addingTimeInterval(60),
            distanceMeters: distance,
            sampleCount: 10
        )
    }
}
