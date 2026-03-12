import Foundation
import CoreKit

/// Registers all MediaKit services into a CoreKit ``Container``.
///
/// Usage:
/// ```swift
/// let container = Container()
/// MediaKitAssembly.register(in: container, provider: myPhotoLibraryProvider)
/// ```
public enum MediaKitAssembly {

    /// Register all MediaKit services in the given container.
    ///
    /// - Parameters:
    ///   - container: The CoreKit DI container to register services in.
    ///   - provider: A ``PhotoLibraryProvider`` implementation (e.g., PHPhotoLibraryProvider in the app).
    ///   - uploader: An optional ``MediaUploaderProtocol`` implementation. Defaults to ``StubMediaUploader``.
    public static func register(
        in container: Container,
        provider: any PhotoLibraryProvider,
        uploader: (any MediaUploaderProtocol)? = nil
    ) {
        container.register(PhotoValidator.self) { _ in
            PhotoValidator()
        }

        container.register(MetadataExtractor.self) { _ in
            MetadataExtractor()
        }

        container.register((any GPSCorridorMatcher).self) { _ in
            DefaultGPSCorridorMatcher()
        }

        container.register(CompressionPipeline.self) { _ in
            CompressionPipeline()
        }

        let resolvedUploader = uploader ?? StubMediaUploader()
        container.register((any MediaUploaderProtocol).self) { _ in
            resolvedUploader
        }

        container.register(BackgroundRetryQueue.self) { resolver in
            let uploaderService = try resolver.resolve((any MediaUploaderProtocol).self)
            return BackgroundRetryQueue(uploader: uploaderService)
        }

        container.register((any PhotoImportService).self) { resolver in
            let matcher = try resolver.resolve((any GPSCorridorMatcher).self)
            let extractor = try resolver.resolve(MetadataExtractor.self)
            return DefaultPhotoImportService(
                provider: provider,
                metadataExtractor: extractor,
                corridorMatcher: matcher
            )
        }
    }
}
