import Foundation

/// Orchestrates the real-time sensor data pipeline: collection -> windowing -> analysis -> classification.
///
/// Consumes an ``AsyncStream`` of raw ``SensorSample`` values, accumulates them into rolling windows,
/// runs vibration analysis and surface classification, then emits ``GroundQualityScore`` results.
public actor SensorPipeline {

    // MARK: - Configuration

    /// Number of samples per analysis window.
    public let windowSize: Int

    /// Sampling frequency in Hz.
    public let sampleRate: Double

    /// Distance in meters between segment boundaries.
    public let segmentDistanceMeters: Double

    // MARK: - Dependencies

    private let collector: any MotionDataCollecting
    private let analyzer: VibrationAnalyzer
    private let classifier: SurfaceClassifier

    // MARK: - State

    private var sampleBuffer: [SensorSample] = []
    private var isRunning = false

    // MARK: - Init

    public init(
        collector: any MotionDataCollecting,
        windowSize: Int = 64,
        sampleRate: Double = 100,
        segmentDistanceMeters: Double = 50
    ) {
        self.collector = collector
        self.windowSize = max(windowSize, 4)
        self.sampleRate = max(sampleRate, 1)
        self.segmentDistanceMeters = max(segmentDistanceMeters, 1)
        self.analyzer = VibrationAnalyzer(windowSize: windowSize)
        self.classifier = SurfaceClassifier()
    }

    // MARK: - Pipeline

    /// Start the sensor pipeline and return a stream of quality scores.
    public func start() -> AsyncStream<GroundQualityScore> {
        isRunning = true
        sampleBuffer.removeAll()

        return AsyncStream { continuation in
            let sampleStream = collector.startCollection(frequency: sampleRate)

            Task { [weak self] in
                for await sample in sampleStream {
                    guard let self, await self.isRunning else {
                        continuation.finish()
                        return
                    }

                    if let score = await self.processSample(sample) {
                        continuation.yield(score)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                Task {
                    await self?.stop()
                }
            }
        }
    }

    /// Stop the sensor pipeline.
    public func stop() {
        isRunning = false
        collector.stopCollection()
        sampleBuffer.removeAll()
    }

    // MARK: - Private

    private func processSample(_ sample: SensorSample) -> GroundQualityScore? {
        sampleBuffer.append(sample)

        // Only analyse when we have a full window.
        guard sampleBuffer.count >= windowSize else { return nil }

        let window = Array(sampleBuffer.suffix(windowSize))

        // Slide the buffer: keep overlap for continuity.
        let slideAmount = windowSize / 2
        if sampleBuffer.count > windowSize + slideAmount {
            sampleBuffer.removeFirst(slideAmount)
        }

        let vibration = analyzer.analyse(samples: window, sampleRate: sampleRate)
        let (surfaceType, confidence) = classifier.classify(vibration: vibration)
        let qualityValue = computeQualityValue(vibration: vibration, surfaceType: surfaceType)

        return GroundQualityScore(
            value: qualityValue,
            confidence: confidence,
            surfaceType: surfaceType
        )
    }

    /// Map vibration characteristics and surface type to a 0-100 quality score.
    /// Lower vibration = higher quality. Surface type applies a bonus/penalty.
    private func computeQualityValue(vibration: VibrationResult, surfaceType: SurfaceType) -> Int {
        // Base score: inverse of RMS amplitude, normalised to 0-100.
        // Clamp RMS to a reasonable max (2.0g for extreme terrain).
        let clampedRMS = min(vibration.rmsAmplitude, 2.0)
        let baseScore = Int((1.0 - clampedRMS / 2.0) * 100)

        // Surface type modifier.
        let modifier: Int = switch surfaceType {
        case .smooth: 10
        case .gravel: -5
        case .rocky: -15
        case .roots: -10
        case .mud: -20
        case .sand: -10
        }

        return min(max(baseScore + modifier, 0), 100)
    }
}
