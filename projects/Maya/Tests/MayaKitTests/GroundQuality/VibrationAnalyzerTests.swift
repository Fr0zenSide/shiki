import Foundation
import Testing

@testable import MayaKit

@Suite("VibrationAnalyzer")
struct VibrationAnalyzerTests {

    @Test("Empty samples produce zero result")
    func emptySamples() {
        let analyzer = VibrationAnalyzer()
        let result = analyzer.analyse(samples: [], sampleRate: 100)
        #expect(result.dominantFrequency == 0)
        #expect(result.rmsAmplitude == 0)
        #expect(result.peakAmplitude == 0)
    }

    @Test("Single sample produces zero result")
    func singleSample() {
        let analyzer = VibrationAnalyzer()
        let sample = makeSample(ax: 1.0)
        let result = analyzer.analyse(samples: [sample], sampleRate: 100)
        #expect(result.dominantFrequency == 0)
        #expect(result.rmsAmplitude == 0)
        #expect(result.peakAmplitude == 0)
    }

    @Test("Constant signal has zero vibration")
    func constantSignal() {
        let analyzer = VibrationAnalyzer(windowSize: 8)
        let samples = (0..<8).map { makeSample(ax: 0, ay: 0, az: 1.0, timestamp: Double($0)) }
        let result = analyzer.analyse(samples: samples, sampleRate: 100)

        // Constant signal => zero vibration after de-meaning.
        #expect(result.rmsAmplitude < 0.001)
    }

    @Test("Alternating signal has non-zero frequency")
    func alternatingSignal() {
        let analyzer = VibrationAnalyzer(windowSize: 16)
        // Alternate between high and low magnitudes (not just sign, which keeps magnitude constant).
        // magnitude = sqrt(x^2 + y^2 + z^2), so we vary x between 0.2 and 1.5 to vary magnitude.
        let samples = (0..<16).map { i in
            let accel = (i % 2 == 0) ? 1.5 : 0.2
            return makeSample(ax: accel, ay: 0, az: 0, timestamp: Double(i) / 100.0)
        }
        let result = analyzer.analyse(samples: samples, sampleRate: 100)

        #expect(result.dominantFrequency > 0)
        #expect(result.rmsAmplitude > 0)
        #expect(result.peakAmplitude > 0)
    }

    @Test("Higher vibration yields higher RMS")
    func higherVibrationHigherRMS() {
        let analyzer = VibrationAnalyzer(windowSize: 8)

        // Low vibration: magnitude alternates between 0.1 and 0.2 (small variance).
        let lowSamples = (0..<8).map { i in
            makeSample(ax: (i % 2 == 0) ? 0.1 : 0.2, timestamp: Double(i))
        }
        // High vibration: magnitude alternates between 0.2 and 2.0 (large variance).
        let highSamples = (0..<8).map { i in
            makeSample(ax: (i % 2 == 0) ? 0.2 : 2.0, timestamp: Double(i))
        }

        let lowResult = analyzer.analyse(samples: lowSamples, sampleRate: 100)
        let highResult = analyzer.analyse(samples: highSamples, sampleRate: 100)

        #expect(highResult.rmsAmplitude > lowResult.rmsAmplitude)
    }

    @Test("Window size clamped to minimum 4")
    func windowSizeClamped() {
        let analyzer = VibrationAnalyzer(windowSize: 1)
        #expect(analyzer.windowSize == 4)
    }

    // MARK: - Helpers

    private func makeSample(
        ax: Double = 0,
        ay: Double = 0,
        az: Double = 0,
        timestamp: Double = 0
    ) -> SensorSample {
        SensorSample(
            accelerationX: ax,
            accelerationY: ay,
            accelerationZ: az,
            rotationX: 0,
            rotationY: 0,
            rotationZ: 0,
            timestamp: timestamp
        )
    }
}
