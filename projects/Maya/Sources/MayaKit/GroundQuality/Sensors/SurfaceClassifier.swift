import Foundation

/// Classifies ``VibrationResult`` data into a ``SurfaceType`` with a confidence score.
///
/// Uses a rule-based classifier that maps vibration frequency and amplitude to surface types.
/// Each surface type defines an expected frequency range and amplitude range; the classifier
/// picks the best match using weighted distance.
public struct SurfaceClassifier: Sendable {

    public init() {}

    // MARK: - Classification

    /// Classify vibration data into a surface type.
    /// - Parameter vibration: The vibration analysis result for a sample window.
    /// - Returns: A tuple of (surface type, confidence 0...1).
    public func classify(vibration: VibrationResult) -> (surfaceType: SurfaceType, confidence: Double) {
        var bestMatch: SurfaceType = .smooth
        var bestScore = Double.infinity

        for surface in SurfaceType.allCases {
            let score = matchScore(vibration: vibration, surface: surface)
            if score < bestScore {
                bestScore = score
                bestMatch = surface
            }
        }

        // Convert distance score to confidence (0...1). Lower distance = higher confidence.
        let confidence = max(0, min(1, 1.0 - (bestScore / 2.0)))

        return (bestMatch, confidence)
    }

    // MARK: - Private

    /// Weighted distance between observed vibration and expected surface characteristics.
    private func matchScore(vibration: VibrationResult, surface: SurfaceType) -> Double {
        let freqRange = surface.frequencyRange
        let ampRange = surface.amplitudeRange

        let freqMid = (freqRange.lowerBound + freqRange.upperBound) / 2.0
        let freqSpan = max(freqRange.upperBound - freqRange.lowerBound, 1)
        let freqDistance = abs(vibration.dominantFrequency - freqMid) / freqSpan

        let ampMid = (ampRange.lowerBound + ampRange.upperBound) / 2.0
        let ampSpan = max(ampRange.upperBound - ampRange.lowerBound, 0.01)
        let ampDistance = abs(vibration.rmsAmplitude - ampMid) / ampSpan

        // Frequency carries more weight than amplitude for classification.
        return freqDistance * 0.6 + ampDistance * 0.4
    }
}
