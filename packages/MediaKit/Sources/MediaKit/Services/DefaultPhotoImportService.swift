import Foundation

/// Default implementation of ``PhotoImportService`` that uses a ``PhotoLibraryProvider``
/// to fetch photos and filters them through GPS corridor matching.
public struct DefaultPhotoImportService: PhotoImportService, Sendable {

    private let provider: any PhotoLibraryProvider
    private let metadataExtractor: MetadataExtractor
    private let corridorMatcher: any GPSCorridorMatcher

    public init(
        provider: any PhotoLibraryProvider,
        metadataExtractor: MetadataExtractor = MetadataExtractor(),
        corridorMatcher: any GPSCorridorMatcher = DefaultGPSCorridorMatcher()
    ) {
        self.provider = provider
        self.metadataExtractor = metadataExtractor
        self.corridorMatcher = corridorMatcher
    }

    public func importPhotos(
        for config: CorridorConfig,
        from bucket: MediaBucket
    ) async throws -> [PhotoMetadata] {
        // 1. Check authorization
        let authorized = await provider.requestAuthorization()
        guard authorized else {
            throw ImportError.unauthorized
        }

        // 2. Fetch assets within time window (with buffer)
        let windowStart = config.sessionStart.addingTimeInterval(-config.timeBufferSeconds)
        let windowEnd = config.sessionEnd.addingTimeInterval(config.timeBufferSeconds)
        let assets = await provider.fetchAssets(from: windowStart, to: windowEnd)

        // 3. Extract metadata and filter
        var results: [PhotoMetadata] = []

        for asset in assets {
            let metadata = metadataExtractor.extract(from: asset.imageData)

            // Use creation date from asset if metadata doesn't have one
            let effectiveMetadata: PhotoMetadata
            if metadata.capturedAt == nil, let creationDate = asset.creationDate {
                effectiveMetadata = PhotoMetadata(
                    latitude: metadata.latitude,
                    longitude: metadata.longitude,
                    altitude: metadata.altitude,
                    capturedAt: creationDate,
                    cameraModel: metadata.cameraModel,
                    originalFilename: metadata.originalFilename
                )
            } else {
                effectiveMetadata = metadata
            }

            // Skip photos without GPS
            guard effectiveMetadata.latitude != nil, effectiveMetadata.longitude != nil else {
                continue
            }

            // Skip photos outside time window
            guard corridorMatcher.isWithinTimeWindow(effectiveMetadata, config: config) else {
                continue
            }

            // Skip photos outside corridor
            guard corridorMatcher.isWithinCorridor(effectiveMetadata, config: config) else {
                continue
            }

            results.append(effectiveMetadata)
        }

        return results
    }

    // MARK: - Errors

    public enum ImportError: Error, Sendable {
        case unauthorized
    }
}
