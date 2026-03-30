import Foundation
import Testing

@testable import MayaKit

@Suite("SurfaceType")
struct SurfaceTypeTests {

    @Test("All cases have display names")
    func allCasesHaveDisplayNames() {
        for surface in SurfaceType.allCases {
            #expect(!surface.displayName.isEmpty)
        }
    }

    @Test("All cases have valid frequency ranges")
    func allCasesHaveFrequencyRanges() {
        for surface in SurfaceType.allCases {
            #expect(surface.frequencyRange.lowerBound >= 0)
            #expect(surface.frequencyRange.upperBound > surface.frequencyRange.lowerBound)
        }
    }

    @Test("All cases have valid amplitude ranges")
    func allCasesHaveAmplitudeRanges() {
        for surface in SurfaceType.allCases {
            #expect(surface.amplitudeRange.lowerBound >= 0)
            #expect(surface.amplitudeRange.upperBound > surface.amplitudeRange.lowerBound)
        }
    }

    @Test("Display names are capitalized")
    func displayNamesCapitalized() {
        #expect(SurfaceType.smooth.displayName == "Smooth")
        #expect(SurfaceType.gravel.displayName == "Gravel")
        #expect(SurfaceType.rocky.displayName == "Rocky")
        #expect(SurfaceType.roots.displayName == "Roots")
        #expect(SurfaceType.mud.displayName == "Mud")
        #expect(SurfaceType.sand.displayName == "Sand")
    }

    @Test("Codable round-trip preserves value")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for surface in SurfaceType.allCases {
            let data = try encoder.encode(surface)
            let decoded = try decoder.decode(SurfaceType.self, from: data)
            #expect(decoded == surface)
        }
    }

    @Test("Six surface types exist")
    func sixCases() {
        #expect(SurfaceType.allCases.count == 6)
    }
}
