import Foundation

/// Analyses a rolling window of ``SensorSample`` values to extract vibration characteristics.
///
/// Uses simplified spectral analysis (zero-crossing rate + RMS amplitude) to approximate
/// dominant vibration frequency without a full FFT dependency.
public struct VibrationAnalyzer: Sendable {

    // MARK: - Configuration

    /// Number of samples in the analysis window.
    public let windowSize: Int

    public init(windowSize: Int = 64) {
        self.windowSize = max(windowSize, 4)
    }

    // MARK: - Analysis

    /// Analyse a window of samples and return vibration characteristics.
    /// - Parameters:
    ///   - samples: Ordered array of sensor samples (oldest first).
    ///   - sampleRate: Sampling frequency in Hz.
    /// - Returns: Vibration result with dominant frequency and amplitude.
    public func analyse(samples: [SensorSample], sampleRate: Double) -> VibrationResult {
        guard samples.count >= 2 else {
            return VibrationResult(dominantFrequency: 0, rmsAmplitude: 0, peakAmplitude: 0)
        }

        let magnitudes = samples.map(\.accelerationMagnitude)
        let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)

        // De-mean the signal for vibration analysis.
        let centered = magnitudes.map { $0 - mean }

        // RMS amplitude.
        let sumSquared = centered.reduce(0) { $0 + $1 * $1 }
        let rms = (sumSquared / Double(centered.count)).squareRoot()

        // Peak amplitude.
        let peak = centered.map(abs).max() ?? 0

        // Zero-crossing rate as a proxy for dominant frequency.
        let dominantFrequency = zeroCrossingFrequency(signal: centered, sampleRate: sampleRate)

        return VibrationResult(
            dominantFrequency: dominantFrequency,
            rmsAmplitude: rms,
            peakAmplitude: peak
        )
    }

    // MARK: - Private

    private func zeroCrossingFrequency(signal: [Double], sampleRate: Double) -> Double {
        guard signal.count >= 2 else { return 0 }

        var crossings = 0
        for i in 1..<signal.count {
            if (signal[i - 1] >= 0 && signal[i] < 0) || (signal[i - 1] < 0 && signal[i] >= 0) {
                crossings += 1
            }
        }

        // Each full cycle has 2 zero crossings.
        let frequency = (Double(crossings) / 2.0) * (sampleRate / Double(signal.count))
        return frequency
    }
}

// MARK: - VibrationResult

/// Output of vibration frequency analysis on a sample window.
public struct VibrationResult: Sendable, Equatable {

    /// Estimated dominant vibration frequency in Hz.
    public let dominantFrequency: Double

    /// Root-mean-square amplitude of the de-meaned acceleration signal (g).
    public let rmsAmplitude: Double

    /// Peak amplitude of the de-meaned acceleration signal (g).
    public let peakAmplitude: Double
}
