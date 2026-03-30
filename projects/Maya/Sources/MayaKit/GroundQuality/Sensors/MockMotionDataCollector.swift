import Foundation

/// Mock implementation of ``MotionDataCollecting`` for testing.
///
/// Yields a pre-configured array of samples, then finishes.
public final class MockMotionDataCollector: MotionDataCollecting, @unchecked Sendable {

    private var samples: [SensorSample]
    private var continuation: AsyncStream<SensorSample>.Continuation?
    public private(set) var didStop = false

    public let isAvailable: Bool

    public init(samples: [SensorSample] = [], isAvailable: Bool = true) {
        self.samples = samples
        self.isAvailable = isAvailable
    }

    // MARK: - MotionDataCollecting

    public func startCollection(frequency: Double) -> AsyncStream<SensorSample> {
        let captured = samples
        return AsyncStream { continuation in
            self.continuation = continuation
            Task {
                for sample in captured {
                    continuation.yield(sample)
                }
                continuation.finish()
            }
        }
    }

    public func stopCollection() {
        didStop = true
        continuation?.finish()
        continuation = nil
    }
}
