#if os(iOS)
import CoreMotion
import Foundation

/// Production implementation of ``MotionDataCollecting`` backed by CoreMotion.
public final class MotionDataCollector: MotionDataCollecting, @unchecked Sendable {

    // MARK: - Properties

    private let motionManager: CMMotionManager
    private let operationQueue: OperationQueue
    private var continuation: AsyncStream<SensorSample>.Continuation?

    // MARK: - Init

    public init() {
        self.motionManager = CMMotionManager()
        self.operationQueue = OperationQueue()
        self.operationQueue.name = "com.maya.motion-collector"
        self.operationQueue.maxConcurrentOperationCount = 1
    }

    // MARK: - MotionDataCollecting

    public var isAvailable: Bool {
        motionManager.isDeviceMotionAvailable
    }

    public func startCollection(frequency: Double) -> AsyncStream<SensorSample> {
        let interval = 1.0 / max(frequency, 1)
        motionManager.deviceMotionUpdateInterval = interval

        return AsyncStream { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stopCollection()
            }

            self.motionManager.startDeviceMotionUpdates(to: self.operationQueue) { motion, _ in
                guard let motion else { return }

                let sample = SensorSample(
                    accelerationX: motion.userAcceleration.x,
                    accelerationY: motion.userAcceleration.y,
                    accelerationZ: motion.userAcceleration.z,
                    rotationX: motion.rotationRate.x,
                    rotationY: motion.rotationRate.y,
                    rotationZ: motion.rotationRate.z,
                    timestamp: motion.timestamp
                )
                continuation.yield(sample)
            }
        }
    }

    public func stopCollection() {
        motionManager.stopDeviceMotionUpdates()
        continuation?.finish()
        continuation = nil
    }
}
#endif
