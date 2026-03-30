import Foundation
import Testing

@testable import MayaKit

@Suite("HistoricalComparator")
struct HistoricalComparatorTests {

    let comparator = HistoricalComparator()

    @Test("Improving trend when score increases by more than 5")
    func improvingTrend() {
        let previous = makeReport(averageScore: 50, date: Date(timeIntervalSince1970: 1000))
        let current = makeReport(averageScore: 70, date: Date(timeIntervalSince1970: 2000))

        let result = comparator.compare(current: current, previous: previous)

        #expect(result.trend == .improving)
        #expect(result.overallScoreDelta == 20)
    }

    @Test("Degrading trend when score decreases by more than 5")
    func degradingTrend() {
        let previous = makeReport(averageScore: 70, date: Date(timeIntervalSince1970: 1000))
        let current = makeReport(averageScore: 50, date: Date(timeIntervalSince1970: 2000))

        let result = comparator.compare(current: current, previous: previous)

        #expect(result.trend == .degrading)
        #expect(result.overallScoreDelta == -20)
    }

    @Test("Stable trend when score changes by 5 or less")
    func stableTrend() {
        let previous = makeReport(averageScore: 50, date: Date(timeIntervalSince1970: 1000))
        let current = makeReport(averageScore: 53, date: Date(timeIntervalSince1970: 2000))

        let result = comparator.compare(current: current, previous: previous)

        #expect(result.trend == .stable)
    }

    @Test("Segment deltas computed for matching segments")
    func segmentDeltas() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)

        // Both reports have a segment at roughly the same location.
        let coord = Coordinate(latitude: 45.0, longitude: 7.0)
        let prevSegment = TrailSegment(
            score: GroundQualityScore(value: 60, confidence: 0.8, surfaceType: .gravel, timestamp: date1),
            startCoordinate: coord,
            endCoordinate: Coordinate(latitude: 45.001, longitude: 7.001),
            startTimestamp: date1,
            endTimestamp: date1.addingTimeInterval(60),
            distanceMeters: 50,
            sampleCount: 5
        )
        let curSegment = TrailSegment(
            score: GroundQualityScore(value: 80, confidence: 0.9, surfaceType: .smooth, timestamp: date2),
            startCoordinate: coord,
            endCoordinate: Coordinate(latitude: 45.001, longitude: 7.001),
            startTimestamp: date2,
            endTimestamp: date2.addingTimeInterval(60),
            distanceMeters: 50,
            sampleCount: 5
        )

        let previous = QualityReport(
            segments: [prevSegment],
            rideDate: date1,
            totalDistanceMeters: 50,
            durationSeconds: 60
        )
        let current = QualityReport(
            segments: [curSegment],
            rideDate: date2,
            totalDistanceMeters: 50,
            durationSeconds: 60
        )

        let result = comparator.compare(current: current, previous: previous)

        #expect(result.segmentDeltas.count == 1)
        #expect(result.segmentDeltas.first?.scoreDelta == 20)
        #expect(result.segmentDeltas.first?.surfaceChanged == true)
        #expect(result.segmentDeltas.first?.previousSurface == .gravel)
        #expect(result.segmentDeltas.first?.currentSurface == .smooth)
    }

    @Test("Comparison dates preserved")
    func datesPreserved() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)

        let previous = makeReport(averageScore: 50, date: date1)
        let current = makeReport(averageScore: 60, date: date2)

        let result = comparator.compare(current: current, previous: previous)

        #expect(result.previousDate == date1)
        #expect(result.currentDate == date2)
    }

    // MARK: - Helpers

    private func makeReport(averageScore: Int, date: Date) -> QualityReport {
        let segment = TrailSegment(
            score: GroundQualityScore(value: averageScore, confidence: 0.8, surfaceType: .smooth, timestamp: date),
            startCoordinate: Coordinate(latitude: 45.0, longitude: 7.0),
            endCoordinate: Coordinate(latitude: 45.001, longitude: 7.001),
            startTimestamp: date,
            endTimestamp: date.addingTimeInterval(60),
            distanceMeters: 100,
            sampleCount: 10
        )
        return QualityReport(
            segments: [segment],
            rideDate: date,
            totalDistanceMeters: 100,
            durationSeconds: 300
        )
    }
}
