import Foundation
import Testing

@testable import MayaKit

@Suite("SensorPipeline")
struct SensorPipelineTests {

    @Test("Pipeline emits scores after window is filled")
    func emitsAfterWindow() async {
        let windowSize = 4
        let samples = generateSmoothSamples(count: windowSize * 2)
        let collector = MockMotionDataCollector(samples: samples)

        let pipeline = SensorPipeline(
            collector: collector,
            windowSize: windowSize,
            sampleRate: 100,
            segmentDistanceMeters: 50
        )

        var scores: [GroundQualityScore] = []
        let stream = await pipeline.start()

        for await score in stream {
            scores.append(score)
        }

        // Should have received at least one score (buffer fills at windowSize).
        #expect(!scores.isEmpty)
    }

    @Test("Pipeline scores are in valid range")
    func scoresInRange() async {
        let samples = generateSmoothSamples(count: 16)
        let collector = MockMotionDataCollector(samples: samples)

        let pipeline = SensorPipeline(
            collector: collector,
            windowSize: 4,
            sampleRate: 100
        )

        let stream = await pipeline.start()

        for await score in stream {
            #expect(score.value >= 0)
            #expect(score.value <= 100)
            #expect(score.confidence >= 0)
            #expect(score.confidence <= 1)
        }
    }

    @Test("Pipeline stop clears state")
    func stopClearsState() async {
        let collector = MockMotionDataCollector(samples: [])
        let pipeline = SensorPipeline(collector: collector, windowSize: 4, sampleRate: 100)
        await pipeline.stop()
        // No crash, stop is idempotent.
        #expect(collector.didStop)
    }

    @Test("Unavailable collector yields empty stream")
    func unavailableCollector() async {
        let collector = MockMotionDataCollector(samples: [], isAvailable: false)
        let pipeline = SensorPipeline(collector: collector, windowSize: 4, sampleRate: 100)
        let stream = await pipeline.start()

        var count = 0
        for await _ in stream {
            count += 1
        }
        #expect(count == 0)
    }

    // MARK: - Helpers

    private func generateSmoothSamples(count: Int) -> [SensorSample] {
        (0..<count).map { i in
            SensorSample(
                accelerationX: 0.01 * Double(i % 3),
                accelerationY: 0.02,
                accelerationZ: 0.98,
                rotationX: 0.001,
                rotationY: 0.001,
                rotationZ: 0.001,
                timestamp: Double(i) / 100.0
            )
        }
    }
}
