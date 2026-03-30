import Foundation

/// Classifies the trail surface material detected via accelerometer/gyroscope vibration patterns.
public enum SurfaceType: String, Sendable, Codable, CaseIterable {
    case smooth
    case gravel
    case rocky
    case roots
    case mud
    case sand

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .smooth: "Smooth"
        case .gravel: "Gravel"
        case .rocky: "Rocky"
        case .roots: "Roots"
        case .mud: "Mud"
        case .sand: "Sand"
        }
    }

    // MARK: - Classification Thresholds

    /// Dominant vibration frequency band (Hz) that characterises this surface.
    /// Used by ``SurfaceClassifier`` to map FFT peaks to surface types.
    public var frequencyRange: ClosedRange<Double> {
        switch self {
        case .smooth: 0...5
        case .gravel: 15...40
        case .rocky: 5...15
        case .roots: 8...20
        case .mud: 0...3
        case .sand: 3...10
        }
    }

    /// Typical vibration amplitude range (g) for this surface at moderate riding speed.
    public var amplitudeRange: ClosedRange<Double> {
        switch self {
        case .smooth: 0.0...0.15
        case .gravel: 0.3...0.8
        case .rocky: 0.6...1.5
        case .roots: 0.4...1.2
        case .mud: 0.05...0.25
        case .sand: 0.1...0.4
        }
    }
}
