// MARK: - Usage Example
//
// This file demonstrates how to wire MediaKit into a Maya-style
// ActivityViewModel. It is NOT production code — it illustrates
// the full photo import → validate → compress → upload flow.
//
// In a real Maya app, you would:
// 1. Create a PHPhotoLibraryProvider conforming to PhotoLibraryProvider
// 2. Register it via MediaKitAssembly in your AppDelegate/SceneDelegate
// 3. @Resolve the services in your ViewModel

import Foundation

// MARK: - Example PHPhotoLibrary Provider (app-level)

/*
 import Photos

 final class PHPhotoLibraryProvider: PhotoLibraryProvider {
     func requestAuthorization() async -> Bool {
         let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
         return status == .authorized || status == .limited
     }

     func fetchAssets(from startDate: Date, to endDate: Date) async -> [PhotoAssetData] {
         let options = PHFetchOptions()
         options.predicate = NSPredicate(
             format: "creationDate >= %@ AND creationDate <= %@",
             startDate as NSDate,
             endDate as NSDate
         )
         options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

         let result = PHAsset.fetchAssets(with: .image, options: options)
         var assets: [PhotoAssetData] = []

         let manager = PHImageManager.default()
         let requestOptions = PHImageRequestOptions()
         requestOptions.isSynchronous = true
         requestOptions.deliveryMode = .highQualityFormat

         result.enumerateObjects { asset, _, _ in
             manager.requestImageDataAndOrientation(for: asset, options: requestOptions) {
                 data, _, _, _ in
                 if let data {
                     assets.append(PhotoAssetData(imageData: data, creationDate: asset.creationDate))
                 }
             }
         }

         return assets
     }
 }
 */

// MARK: - Example ActivityViewModel Integration

/*
 @MainActor
 final class ActivityViewModel: ObservableObject {
     @Resolve private var importService: PhotoImportService
     @Resolve private var validator: PhotoValidator
     @Resolve private var compression: CompressionPipeline
     @Resolve private var uploader: MediaUploaderProtocol

     @Published var photos: [PhotoMetadata] = []
     @Published var uploadProgress: UploadProgress?
     @Published var error: Error?

     func importActivityPhotos(config: CorridorConfig) async {
         do {
             // Step 1: Authorize + import (filtered by corridor)
             photos = try await importService.importPhotos(
                 for: config,
                 from: .mayaPhotos
             )

             // Step 2: For each photo, validate → compress → upload
             for metadata in photos {
                 // Validation (size + GPS)
                 let data = Data() // would come from PhotoAssetData
                 try validator.validate(data, metadata: metadata, mimeType: .heic)

                 // Compression
                 let compressed = compression.compress(data, mimeType: .heic)

                 // Upload
                 let uploadable = ActivityUploadable(
                     data: compressed,
                     mimeType: .heic,
                     metadata: metadata,
                     bucket: .mayaPhotos
                 )
                 let result = try await uploader.upload(uploadable) { progress in
                     Task { @MainActor in
                         self.uploadProgress = progress
                     }
                 }
                 print("Uploaded: \(result.s3Key)")
             }
         } catch {
             self.error = error
         }
     }
 }

 struct ActivityUploadable: MediaUploadable {
     let data: Data
     let mimeType: MIMEType
     let metadata: PhotoMetadata
     let bucket: MediaBucket
 }
 */
