import Foundation

public protocol PhotoImportService: Sendable {
    func importPhotos(for config: CorridorConfig, from bucket: MediaBucket) async throws -> [PhotoMetadata]
}
