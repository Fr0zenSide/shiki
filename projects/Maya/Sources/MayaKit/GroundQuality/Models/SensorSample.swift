import CoreLocation
import Foundation

/// A single motion sensor reading from accelerometer + gyroscope.
public struct SensorSample: Sendable, Codable, Equatable {

    /// Accelerometer axes (in g).
    public let accelerationX: Double
    public let accelerationY: Double
    public let accelerationZ: Double

    /// Gyroscope axes (rad/s).
    public let rotationX: Double
    public let rotationY: Double
    public let rotationZ: Double

    /// Capture timestamp (seconds since reference date).
    public let timestamp: TimeInterval

    /// GPS coordinate at capture time, if available.
    public let coordinate: Coordinate?

    public init(
        accelerationX: Double,
        accelerationY: Double,
        accelerationZ: Double,
        rotationX: Double,
        rotationY: Double,
        rotationZ: Double,
        timestamp: TimeInterval,
        coordinate: Coordinate? = nil
    ) {
        self.accelerationX = accelerationX
        self.accelerationY = accelerationY
        self.accelerationZ = accelerationZ
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.rotationZ = rotationZ
        self.timestamp = timestamp
        self.coordinate = coordinate
    }

    // MARK: - Derived

    /// Combined acceleration magnitude (g).
    public var accelerationMagnitude: Double {
        (accelerationX * accelerationX + accelerationY * accelerationY + accelerationZ * accelerationZ).squareRoot()
    }

    /// Combined rotation magnitude (rad/s).
    public var rotationMagnitude: Double {
        (rotationX * rotationX + rotationY * rotationY + rotationZ * rotationZ).squareRoot()
    }
}

// MARK: - Coordinate

/// Lightweight, Codable GPS coordinate (avoids CLLocationCoordinate2D Codable issues).
public struct Coordinate: Sendable, Codable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?

    public init(latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    public var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
