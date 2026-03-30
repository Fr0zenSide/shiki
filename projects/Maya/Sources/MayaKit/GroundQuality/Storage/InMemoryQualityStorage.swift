import Foundation

/// In-memory implementation of ``QualityStorageProtocol`` for testing and previews.
public actor InMemoryQualityStorage: QualityStorageProtocol {

    private var reports: [QualityReport] = []

    public init() {}

    public init(preloaded reports: [QualityReport]) {
        self.reports = reports
    }

    // MARK: - QualityStorageProtocol

    public func save(report: QualityReport) async throws {
        reports.append(report)
    }

    public func fetchAllReports() async throws -> [QualityReport] {
        reports.sorted(by: { $0.rideDate > $1.rideDate })
    }

    public func fetchReports(from start: Date, to end: Date) async throws -> [QualityReport] {
        reports
            .filter { $0.rideDate >= start && $0.rideDate <= end }
            .sorted(by: { $0.rideDate > $1.rideDate })
    }

    public func fetchNearestReport(to coordinate: Coordinate, radiusMeters: Double) async throws -> QualityReport? {
        // Simplified: find any report that has a segment within radius.
        let radiusDegrees = radiusMeters / 111_000 // rough meters-to-degrees

        return reports
            .sorted(by: { $0.rideDate > $1.rideDate })
            .first { report in
                report.segments.contains { segment in
                    let dLat = abs(segment.startCoordinate.latitude - coordinate.latitude)
                    let dLon = abs(segment.startCoordinate.longitude - coordinate.longitude)
                    return dLat <= radiusDegrees && dLon <= radiusDegrees
                }
            }
    }

    public func deleteReport(id: UUID) async throws {
        reports.removeAll(where: { $0.id == id })
    }
}
