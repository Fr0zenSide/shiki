import Foundation

/// Protocol for motion sensor data collection.
///
/// Abstracts CoreMotion behind a testable interface. Production implementation wraps
/// ``CMMotionManager``; tests inject a mock stream.
public protocol MotionDataCollecting: Sendable {

    /// Start collecting sensor data at the given frequency.
    /// - Parameter frequency: Sampling rate in Hz (e.g. 100 for 100 samples/second).
    /// - Returns: An `AsyncStream` of sensor samples.
    func startCollection(frequency: Double) -> AsyncStream<SensorSample>

    /// Stop collecting sensor data.
    func stopCollection()

    /// Whether the device supports required motion sensors.
    var isAvailable: Bool { get }
}
