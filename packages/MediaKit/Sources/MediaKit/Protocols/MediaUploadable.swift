import Foundation

public protocol MediaUploadable: Sendable {
    var data: Data { get }
    var mimeType: MIMEType { get }
    var metadata: PhotoMetadata { get }
    var bucket: MediaBucket { get }
}
