import Foundation
import Testing

@testable import MayaKit

@Suite("SegmentScorer")
struct SegmentScorerTests {

    @Test("No segment emitted before distance threshold")
    func noSegmentBeforeThreshold() async {
        let scorer = SegmentScorer(segmentDistance: 100)

        // Two points very close together (< 100m).
        let coord1 = Coordinate(latitude: 45.0000, longitude: 7.0000)
        let coord2 = Coordinate(latitude: 45.0001, longitude: 7.0001)
        let score = GroundQualityScore(value: 80, confidence: 0.9, surfaceType: .smooth)

        let result1 = await scorer.addScore(score, coordinate: coord1)
        let result2 = await scorer.addScore(score, coordinate: coord2)

        #expect(result1 == nil)
        #expect(result2 == nil)
    }

    @Test("Segment emitted when distance threshold reached")
    func segmentEmittedAtThreshold() async {
        let scorer = SegmentScorer(segmentDistance: 10) // 10m segments

        let score = GroundQualityScore(value: 70, confidence: 0.8, surfaceType: .gravel)

        // Points ~111m apart (1 degree latitude ~ 111km, so 0.001 ~ 111m).
        let coord1 = Coordinate(latitude: 45.0000, longitude: 7.0000)
        let coord2 = Coordinate(latitude: 45.0010, longitude: 7.0000)

        _ = await scorer.addScore(score, coordinate: coord1)
        let segment = await scorer.addScore(score, coordinate: coord2)

        #expect(segment != nil)
        #expect(segment?.score.value == 70)
        #expect(segment?.sampleCount == 2)
    }

    @Test("Finalise current segment returns partial data")
    func finalisePartialSegment() async {
        let scorer = SegmentScorer(segmentDistance: 1000)

        let coord = Coordinate(latitude: 45.0, longitude: 7.0)
        let score = GroundQualityScore(value: 60, confidence: 0.7, surfaceType: .mud)

        _ = await scorer.addScore(score, coordinate: coord)
        let segment = await scorer.finaliseCurrentSegment()

        #expect(segment != nil)
        #expect(segment?.score.surfaceType == .mud)
    }

    @Test("Finalise with no data returns nil")
    func finaliseEmpty() async {
        let scorer = SegmentScorer(segmentDistance: 50)
        let segment = await scorer.finaliseCurrentSegment()
        #expect(segment == nil)
    }

    @Test("Reset clears state")
    func resetClearsState() async {
        let scorer = SegmentScorer(segmentDistance: 50)
        let coord = Coordinate(latitude: 45.0, longitude: 7.0)
        let score = GroundQualityScore(value: 60, confidence: 0.7, surfaceType: .smooth)

        _ = await scorer.addScore(score, coordinate: coord)
        await scorer.reset()

        let segment = await scorer.finaliseCurrentSegment()
        #expect(segment == nil)
    }

    @Test("Dominant surface type is most frequent")
    func dominantSurfaceType() async {
        let scorer = SegmentScorer(segmentDistance: 10)

        // 3 gravel, 1 smooth.
        let gravel = GroundQualityScore(value: 50, confidence: 0.7, surfaceType: .gravel)
        let smooth = GroundQualityScore(value: 90, confidence: 0.9, surfaceType: .smooth)

        let coord1 = Coordinate(latitude: 45.0000, longitude: 7.0000)
        let coord2 = Coordinate(latitude: 45.0001, longitude: 7.0000)
        let coord3 = Coordinate(latitude: 45.0002, longitude: 7.0000)
        let coord4 = Coordinate(latitude: 45.0010, longitude: 7.0000)

        _ = await scorer.addScore(gravel, coordinate: coord1)
        _ = await scorer.addScore(gravel, coordinate: coord2)
        _ = await scorer.addScore(smooth, coordinate: coord3)
        let segment = await scorer.addScore(gravel, coordinate: coord4)

        #expect(segment != nil)
        #expect(segment?.score.surfaceType == .gravel)
    }

    @Test("Segment distance clamped to minimum 1")
    func segmentDistanceClamped() async {
        let scorer = SegmentScorer(segmentDistance: -5)
        // Should not crash. Internal segmentDistance is clamped to 1.
        let coord = Coordinate(latitude: 45.0, longitude: 7.0)
        let score = GroundQualityScore(value: 50, confidence: 0.5, surfaceType: .sand)
        _ = await scorer.addScore(score, coordinate: coord)
    }
}
