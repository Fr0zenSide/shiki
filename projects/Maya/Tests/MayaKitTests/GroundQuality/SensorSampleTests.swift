import Foundation
import Testing

@testable import MayaKit

@Suite("SensorSample")
struct SensorSampleTests {

    @Test("Acceleration magnitude computed correctly")
    func accelerationMagnitude() {
        let sample = SensorSample(
            accelerationX: 3,
            accelerationY: 4,
            accelerationZ: 0,
            rotationX: 0,
            rotationY: 0,
            rotationZ: 0,
            timestamp: 0
        )
        #expect(abs(sample.accelerationMagnitude - 5.0) < 0.001)
    }

    @Test("Rotation magnitude computed correctly")
    func rotationMagnitude() {
        let sample = SensorSample(
            accelerationX: 0,
            accelerationY: 0,
            accelerationZ: 0,
            rotationX: 1,
            rotationY: 2,
            rotationZ: 2,
            timestamp: 0
        )
        #expect(abs(sample.rotationMagnitude - 3.0) < 0.001)
    }

    @Test("Zero sample has zero magnitudes")
    func zeroMagnitudes() {
        let sample = SensorSample(
            accelerationX: 0,
            accelerationY: 0,
            accelerationZ: 0,
            rotationX: 0,
            rotationY: 0,
            rotationZ: 0,
            timestamp: 0
        )
        #expect(sample.accelerationMagnitude == 0)
        #expect(sample.rotationMagnitude == 0)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let sample = SensorSample(
            accelerationX: 0.1,
            accelerationY: -0.2,
            accelerationZ: 0.98,
            rotationX: 0.5,
            rotationY: -0.3,
            rotationZ: 0.1,
            timestamp: 1234.56,
            coordinate: Coordinate(latitude: 45.0, longitude: 7.0, altitude: 300)
        )
        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(SensorSample.self, from: data)
        #expect(decoded == sample)
    }

    @Test("Coordinate is optional")
    func optionalCoordinate() {
        let sample = SensorSample(
            accelerationX: 0,
            accelerationY: 0,
            accelerationZ: 0,
            rotationX: 0,
            rotationY: 0,
            rotationZ: 0,
            timestamp: 0
        )
        #expect(sample.coordinate == nil)
    }
}

@Suite("Coordinate")
struct CoordinateTests {

    @Test("CLLocationCoordinate2D conversion")
    func clCoordinateConversion() {
        let coord = Coordinate(latitude: 45.123, longitude: 7.456)
        let cl = coord.clLocationCoordinate
        #expect(abs(cl.latitude - 45.123) < 0.0001)
        #expect(abs(cl.longitude - 7.456) < 0.0001)
    }

    @Test("Equatable works with altitude")
    func equatableWithAltitude() {
        let a = Coordinate(latitude: 1, longitude: 2, altitude: 100)
        let b = Coordinate(latitude: 1, longitude: 2, altitude: 100)
        let c = Coordinate(latitude: 1, longitude: 2, altitude: 200)
        #expect(a == b)
        #expect(a != c)
    }
}
