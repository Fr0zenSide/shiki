import Foundation

/// Protocol for in-app camera capture (WabiSabi use case).
/// The default implementation lives at the app level (UIKit/SwiftUI camera).
public protocol CameraCaptureService: Sendable {
    func capturePhoto() async throws -> CapturedPhoto
}

/// A photo captured via the in-app camera.
public struct CapturedPhoto: Sendable {
    public let imageData: Data
    public let metadata: PhotoMetadata
    public let mimeType: MIMEType

    public init(imageData: Data, metadata: PhotoMetadata, mimeType: MIMEType) {
        self.imageData = imageData
        self.metadata = metadata
        self.mimeType = mimeType
    }
}
