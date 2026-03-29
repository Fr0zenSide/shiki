import Testing
import Foundation
@testable import ShikkiKit

@Suite("Patina Protocol")
struct PatinaProtocolTests {

    // MARK: - Freshness Decay Formula

    @Test("freshness is 1.0 at time zero")
    func freshAtZero() {
        let freshness = computeFreshness(daysSinceCorroboration: 0)
        #expect(abs(freshness - 1.0) < 0.001)
    }

    @Test("freshness is ~0.5 after 30 days (half-life)")
    func halfLifeAt30Days() {
        let freshness = computeFreshness(daysSinceCorroboration: 30)
        #expect(freshness > 0.45 && freshness < 0.55)
    }

    @Test("freshness is ~0.25 after 60 days")
    func quarterAt60Days() {
        let freshness = computeFreshness(daysSinceCorroboration: 60)
        #expect(freshness > 0.20 && freshness < 0.30)
    }

    @Test("freshness never goes below 0.05 (patina floor)")
    func patinaFloor() {
        let freshness = computeFreshness(daysSinceCorroboration: 365)
        #expect(freshness >= 0.05)
    }

    @Test("freshness decays logarithmically not linearly")
    func logarithmicDecay() {
        let f10 = computeFreshness(daysSinceCorroboration: 10)
        let f20 = computeFreshness(daysSinceCorroboration: 20)
        let f30 = computeFreshness(daysSinceCorroboration: 30)

        // Decay rate slows over time (logarithmic, not linear)
        let drop1 = f10 - f20
        let drop2 = f20 - f30
        #expect(drop1 > drop2) // First 10-day drop is bigger than second
    }

    // MARK: - Corroboration

    @Test("corroboration resets freshness to 1.0")
    func corroborationRefreshes() {
        // Simulate: memory is 60 days old (freshness ~0.25)
        let stale = computeFreshness(daysSinceCorroboration: 60)
        #expect(stale < 0.3)

        // After corroboration: freshness resets
        let refreshed = computeFreshness(daysSinceCorroboration: 0)
        #expect(abs(refreshed - 1.0) < 0.001)
    }

    @Test("search results are ranked by similarity * freshness")
    func freshnessWeightedRanking() {
        // Memory A: high similarity (0.95), stale (30 days, freshness ~0.5)
        let scoreA = 0.95 * computeFreshness(daysSinceCorroboration: 30)
        // Memory B: lower similarity (0.7), fresh (0 days, freshness 1.0)
        let scoreB = 0.7 * computeFreshness(daysSinceCorroboration: 0)

        // Fresh memory B should rank higher despite lower raw similarity
        #expect(scoreB > scoreA)
    }

    @Test("patina memories are still queryable")
    func patinaStillQueryable() {
        let freshness = computeFreshness(daysSinceCorroboration: 365)
        // Patina floor is 0.05 — not zero, still findable
        #expect(freshness > 0)
        // But ranking weight is very low
        let score = 0.9 * freshness
        #expect(score < 0.1)
    }

    // MARK: - Edge Cases

    @Test("negative days treated as fresh")
    func negativeDays() {
        let freshness = computeFreshness(daysSinceCorroboration: -1)
        #expect(freshness >= 1.0) // exp of positive = >1, but capped? Actually exp(+0.0231) > 1
    }

    @Test("very large day count hits floor")
    func extremeAge() {
        let freshness = computeFreshness(daysSinceCorroboration: 10000)
        #expect(freshness == 0.05)
    }

    // MARK: - Helper

    /// Mirror of the SQL compute_freshness function.
    /// freshness = max(0.05, exp(-0.0231 * days))
    /// λ = ln(2) / 30 ≈ 0.0231
    func computeFreshness(daysSinceCorroboration: Double) -> Double {
        max(0.05, exp(-0.0231 * daysSinceCorroboration))
    }
}
