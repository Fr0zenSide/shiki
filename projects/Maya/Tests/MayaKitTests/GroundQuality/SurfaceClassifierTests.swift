import Foundation
import Testing

@testable import MayaKit

@Suite("SurfaceClassifier")
struct SurfaceClassifierTests {

    let classifier = SurfaceClassifier()

    @Test("Low frequency low amplitude classifies as smooth or mud")
    func lowFreqLowAmp() {
        let vibration = VibrationResult(dominantFrequency: 2, rmsAmplitude: 0.05, peakAmplitude: 0.1)
        let (surface, confidence) = classifier.classify(vibration: vibration)
        // Should be smooth or mud (both are low-freq, low-amp).
        #expect([SurfaceType.smooth, .mud].contains(surface))
        #expect(confidence > 0)
    }

    @Test("High frequency moderate amplitude classifies as gravel")
    func highFreqModerateAmp() {
        let vibration = VibrationResult(dominantFrequency: 27, rmsAmplitude: 0.55, peakAmplitude: 0.8)
        let (surface, _) = classifier.classify(vibration: vibration)
        #expect(surface == .gravel)
    }

    @Test("Medium frequency high amplitude classifies as rocky")
    func medFreqHighAmp() {
        let vibration = VibrationResult(dominantFrequency: 10, rmsAmplitude: 1.0, peakAmplitude: 1.5)
        let (surface, _) = classifier.classify(vibration: vibration)
        // Rocky has freq 5-15 and amp 0.6-1.5 — this should match.
        #expect(surface == .rocky)
    }

    @Test("Confidence is between 0 and 1")
    func confidenceBounded() {
        let variations: [VibrationResult] = [
            VibrationResult(dominantFrequency: 0, rmsAmplitude: 0, peakAmplitude: 0),
            VibrationResult(dominantFrequency: 50, rmsAmplitude: 3.0, peakAmplitude: 5.0),
            VibrationResult(dominantFrequency: 10, rmsAmplitude: 0.5, peakAmplitude: 0.8),
        ]

        for vibration in variations {
            let (_, confidence) = classifier.classify(vibration: vibration)
            #expect(confidence >= 0)
            #expect(confidence <= 1)
        }
    }

    @Test("Zero vibration classifies as smooth with high confidence")
    func zeroVibration() {
        let vibration = VibrationResult(dominantFrequency: 0, rmsAmplitude: 0, peakAmplitude: 0)
        let (surface, confidence) = classifier.classify(vibration: vibration)
        // Zero vibration is closest to smooth (0-5 Hz, 0-0.15g).
        #expect(surface == .smooth)
        #expect(confidence > 0.5)
    }
}
