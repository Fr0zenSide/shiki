import Foundation

/// Abstraction over PHPhotoLibrary for testability.
/// Production apps provide a real implementation using Photos framework.
public protocol PhotoLibraryProvider: Sendable {
    func requestAuthorization() async -> Bool
    func fetchAssets(from startDate: Date, to endDate: Date) async -> [PhotoAssetData]
}

/// Raw photo asset data returned by a `PhotoLibraryProvider`.
public struct PhotoAssetData: Sendable {
    public let imageData: Data
    public let creationDate: Date?

    public init(imageData: Data, creationDate: Date?) {
        self.imageData = imageData
        self.creationDate = creationDate
    }
}
