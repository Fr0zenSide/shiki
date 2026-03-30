import Foundation

/// Persistence interface for ground quality data.
///
/// Backed by SwiftData in production; replaced by an in-memory mock in tests.
public protocol QualityStorageProtocol: Sendable {

    /// Save a completed quality report.
    func save(report: QualityReport) async throws

    /// Fetch all reports, newest first.
    func fetchAllReports() async throws -> [QualityReport]

    /// Fetch reports within a date range.
    func fetchReports(from start: Date, to end: Date) async throws -> [QualityReport]

    /// Fetch the most recent report whose segments overlap the given coordinate (within radius).
    func fetchNearestReport(to coordinate: Coordinate, radiusMeters: Double) async throws -> QualityReport?

    /// Delete a report by ID.
    func deleteReport(id: UUID) async throws
}
