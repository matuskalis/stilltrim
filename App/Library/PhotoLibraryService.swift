@preconcurrency import Photos
import UIKit
import os

struct AssetRecord: Sendable, Identifiable, Hashable {
    enum Kind: Sendable { case photo, video }

    let id: String
    let kind: Kind
    let creationDate: Date
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let isScreenshot: Bool
    let isScreenRecording: Bool
    let isFavorite: Bool

    var pixelCount: Int { pixelWidth * pixelHeight }
}

struct AssetDetails: Sendable {
    let byteSize: Int64
    let isEdited: Bool
}

enum ThumbnailOutcome: Sendable {
    case image(CGImage)
    case notOnDevice
    case failed
}

/// The only owner of PhotoKit objects. Everything that leaves is a plain value.
actor PhotoLibraryService {
    private var fetchResult: PHFetchResult<PHAsset>?
    private var indexByID: [String: Int] = [:]
    private let imageManager = PHImageManager.default()
    private let changeObserver = LibraryChangeObserver()
    private var isObserving = false

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(changeObserver)
    }

    func onLibraryChange(_ handler: @escaping @Sendable (LibraryChange) -> Void) {
        changeObserver.setHandler(handler)
    }

    func loadAssets() -> [AssetRecord] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        fetchResult = result

        var indexes: [String: Int] = [:]
        indexes.reserveCapacity(result.count)
        var records: [AssetRecord] = []
        records.reserveCapacity(result.count)
        result.enumerateObjects { asset, index, _ in
            guard asset.mediaType == .image || asset.mediaType == .video else { return }
            indexes[asset.localIdentifier] = index
            records.append(AssetRecord(
                id: asset.localIdentifier,
                kind: asset.mediaType == .video ? .video : .photo,
                creationDate: asset.creationDate ?? .distantPast,
                modificationDate: asset.modificationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                duration: asset.duration,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                isScreenRecording: asset.mediaSubtypes.contains(.videoScreenRecording),
                isFavorite: asset.isFavorite
            ))
        }
        indexByID = indexes
        changeObserver.watch(result)
        if !isObserving {
            PHPhotoLibrary.shared().register(changeObserver)
            isObserving = true
        }
        return records
    }

    /// Byte size sums every resource of the asset (original, edited render, paired video),
    /// counting only what is on this phone. `fileSize` and `locallyAvailable` are not public API,
    /// so each key is checked before use.
    func details(for ids: [String]) -> [String: AssetDetails] {
        let sizeKey = "fileSize", localKey = "locallyAvailable"
        var details: [String: AssetDetails] = [:]
        details.reserveCapacity(ids.count)
        for id in ids {
            guard let asset = asset(for: id) else { continue }
            var bytes: Int64 = 0
            var edited = false
            for resource in PHAssetResource.assetResources(for: asset) {
                if resource.type == .adjustmentData || resource.type == .fullSizePhoto { edited = true }
                if resource.responds(to: Selector((localKey))),
                   (resource.value(forKey: localKey) as? NSNumber)?.boolValue == false { continue }
                if resource.responds(to: Selector((sizeKey))) {
                    bytes += (resource.value(forKey: sizeKey) as? NSNumber)?.int64Value ?? 0
                }
            }
            details[id] = AssetDetails(byteSize: bytes, isEdited: edited)
        }
        return details
    }

    /// Never downloads from iCloud: `isNetworkAccessAllowed` stays false.
    func thumbnail(for id: String, side: CGFloat, exact: Bool) async -> ThumbnailOutcome {
        guard let asset = asset(for: id) else { return .failed }
        let manager = imageManager
        return await withCheckedContinuation { (continuation: CheckedContinuation<ThumbnailOutcome, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = exact ? .exact : .fast
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            let resumed = OSAllocatedUnfairLock(initialState: false)
            manager.requestImage(
                for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit, options: options
            ) { image, info in
                // A degraded preview is never final, and a continuation must resume exactly once.
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                if resumed.withLock({ let already = $0; $0 = true; return already }) { return }
                if let cgImage = image?.cgImage {
                    continuation.resume(returning: .image(cgImage))
                } else if (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                    continuation.resume(returning: .notOnDevice)
                } else {
                    continuation.resume(returning: .failed)
                }
            }
        }
    }

    /// Deletes what still exists and returns those ids, so the caller reports what really happened.
    /// iOS shows its own confirmation; declining throws `PHPhotosError.userCancelled`.
    func delete(ids: Set<String>) async throws -> Set<String> {
        var existing: [String] = []
        PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil).enumerateObjects { asset, _, _ in
            existing.append(asset.localIdentifier)
        }
        guard !existing.isEmpty else { return [] }
        let toDelete = existing
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: toDelete, options: nil))
        }
        return Set(toDelete)
    }

    private func asset(for id: String) -> PHAsset? {
        guard let index = indexByID[id], let fetchResult, index < fetchResult.count else { return nil }
        return fetchResult.object(at: index)
    }
}
