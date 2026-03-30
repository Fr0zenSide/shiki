import Foundation
import Testing

@testable import MayaKit

@Suite("GroundQualityScore")
struct GroundQualityScoreTests {

    @Test("Score clamped to 0-100 range")
    func scoreClamped() {
        let overMax = GroundQualityScore(value: 150, confidence: 0.9, surfaceType: .smooth)
        #expect(overMax.value == 100)

        let underMin = GroundQualityScore(value: -20, confidence: 0.9, surfaceType: .smooth)
        #expect(underMin.value == 0)

        let normal = GroundQualityScore(value: 75, confidence: 0.9, surfaceType: .smooth)
        #expect(normal.value == 75)
    }

    @Test("Confidence clamped to 0-1 range")
    func confidenceClamped() {
        let overMax = GroundQualityScore(value: 50, confidence: 1.5, surfaceType: .gravel)
        #expect(overMax.confidence == 1.0)

        let underMin = GroundQualityScore(value: 50, confidence: -0.3, surfaceType: .gravel)
        #expect(underMin.confidence == 0.0)
    }

    @Test("Tier mapping is correct", arguments: [
        (90, QualityTier.excellent),
        (80, QualityTier.excellent),
        (70, QualityTier.good),
        (60, QualityTier.good),
        (50, QualityTier.fair),
        (40, QualityTier.fair),
        (30, QualityTier.poor),
        (20, QualityTier.poor),
        (10, QualityTier.terrible),
        (0, QualityTier.terrible),
    ])
    func tierMapping(score: Int, expectedTier: QualityTier) {
        let qualityScore = GroundQualityScore(value: score, confidence: 0.8, surfaceType: .smooth)
        #expect(qualityScore.tier == expectedTier)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let score = GroundQualityScore(
            value: 73,
            confidence: 0.85,
            surfaceType: .rocky,
            timestamp: Date(timeIntervalSince1970: 1_000_000)
        )
        let data = try JSONEncoder().encode(score)
        let decoded = try JSONDecoder().decode(GroundQualityScore.self, from: data)
        #expect(decoded == score)
    }

    @Test("Equatable works")
    func equatable() {
        let date = Date(timeIntervalSince1970: 1_000)
        let a = GroundQualityScore(value: 50, confidence: 0.5, surfaceType: .mud, timestamp: date)
        let b = GroundQualityScore(value: 50, confidence: 0.5, surfaceType: .mud, timestamp: date)
        #expect(a == b)
    }
}

@Suite("QualityTier")
struct QualityTierTests {

    @Test("Display names are capitalized")
    func displayNames() {
        #expect(QualityTier.excellent.displayName == "Excellent")
        #expect(QualityTier.good.displayName == "Good")
        #expect(QualityTier.fair.displayName == "Fair")
        #expect(QualityTier.poor.displayName == "Poor")
        #expect(QualityTier.terrible.displayName == "Terrible")
    }

    @Test("Five tiers exist")
    func fiveTiers() {
        #expect(QualityTier.allCases.count == 5)
    }

    @Test("Boundary scores: 100 is excellent, 0 is terrible")
    func boundaries() {
        #expect(QualityTier(score: 100) == .excellent)
        #expect(QualityTier(score: 0) == .terrible)
        #expect(QualityTier(score: 79) == .good)
        #expect(QualityTier(score: 80) == .excellent)
    }
}
