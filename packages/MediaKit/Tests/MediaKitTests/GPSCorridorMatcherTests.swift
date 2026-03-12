import XCTest
@testable import MediaKit

final class GPSCorridorMatcherTests: XCTestCase {

    private var sut: DefaultGPSCorridorMatcher!
    private var config: CorridorConfig!

    override func setUp() {
        super.setUp()
        sut = DefaultGPSCorridorMatcher()

        // Route: Paris (48.8566, 2.3522) → Eiffel Tower (48.8584, 2.2945)
        let now = Date()
        config = CorridorConfig(
            routeCoordinates: [
                (latitude: 48.8566, longitude: 2.3522),
                (latitude: 48.8584, longitude: 2.2945),
            ],
            corridorWidthMeters: 100,
            sessionStart: now.addingTimeInterval(-3600),
            sessionEnd: now.addingTimeInterval(3600),
            timeBufferSeconds: 300
        )
    }

    // MARK: - Corridor tests

    func test_isWithinCorridor_pointInside_returnsTrue() {
        // Point very close to Paris center (48.8566, 2.3522)
        let metadata = PhotoMetadata(latitude: 48.8566, longitude: 2.3523)
        XCTAssertTrue(sut.isWithinCorridor(metadata, config: config))
    }

    func test_isWithinCorridor_pointOutside_returnsFalse() {
        // Point far from route — London
        let metadata = PhotoMetadata(latitude: 51.5074, longitude: -0.1278)
        XCTAssertFalse(sut.isWithinCorridor(metadata, config: config))
    }

    func test_isWithinCorridor_onBoundary_returnsTrue() {
        // Point ~90m from route start — just inside the 100m corridor
        let metadata = PhotoMetadata(latitude: 48.8574, longitude: 2.3522)
        XCTAssertTrue(sut.isWithinCorridor(metadata, config: config))
    }

    // MARK: - Time window tests

    func test_isWithinTimeWindow_insideWindow_returnsTrue() {
        let metadata = PhotoMetadata(capturedAt: Date())
        XCTAssertTrue(sut.isWithinTimeWindow(metadata, config: config))
    }

    func test_isWithinTimeWindow_outsideWindow_returnsFalse() {
        // 2 hours in the future (beyond session end + buffer)
        let metadata = PhotoMetadata(capturedAt: Date().addingTimeInterval(7200))
        XCTAssertFalse(sut.isWithinTimeWindow(metadata, config: config))
    }

    // MARK: - Validate tests

    func test_validate_missingGPS_throws() {
        let metadata = PhotoMetadata() // no GPS
        XCTAssertThrowsError(try sut.validate(metadata, config: config)) { error in
            XCTAssertEqual(error as? MediaValidationError, .missingGPSData)
        }
    }

    func test_validate_validPhoto_passes() throws {
        let metadata = PhotoMetadata(
            latitude: 48.8566,
            longitude: 2.3522,
            capturedAt: Date()
        )
        XCTAssertNoThrow(try sut.validate(metadata, config: config))
    }
}

final class HaversineCalculatorTests: XCTestCase {

    func test_distance_parisToLondon() {
        // Paris to London is ~343 km
        let distance = HaversineCalculator.distance(
            lat1: 48.8566, lon1: 2.3522,
            lat2: 51.5074, lon2: -0.1278
        )
        XCTAssertEqual(distance, 343_500, accuracy: 1000)
    }

    func test_distance_samePoint_isZero() {
        let distance = HaversineCalculator.distance(
            lat1: 48.8566, lon1: 2.3522,
            lat2: 48.8566, lon2: 2.3522
        )
        XCTAssertEqual(distance, 0, accuracy: 0.01)
    }
}
