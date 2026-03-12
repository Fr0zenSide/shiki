import XCTest
import CoreKit
@testable import MediaKit

final class MediaKitAssemblyTests: XCTestCase {

    private final class StubProvider: PhotoLibraryProvider, @unchecked Sendable {
        func requestAuthorization() async -> Bool { true }
        func fetchAssets(from: Date, to: Date) async -> [PhotoAssetData] { [] }
    }

    func test_allServicesResolve() throws {
        let container = Container(name: "MediaKitTest")
        MediaKitAssembly.register(in: container, provider: StubProvider())

        XCTAssertNoThrow(try container.resolve(PhotoValidator.self))
        XCTAssertNoThrow(try container.resolve(MetadataExtractor.self))
        XCTAssertNoThrow(try container.resolve((any GPSCorridorMatcher).self))
        XCTAssertNoThrow(try container.resolve(CompressionPipeline.self))
        XCTAssertNoThrow(try container.resolve((any MediaUploaderProtocol).self))
        XCTAssertNoThrow(try container.resolve(BackgroundRetryQueue.self))
        XCTAssertNoThrow(try container.resolve((any PhotoImportService).self))
    }
}
