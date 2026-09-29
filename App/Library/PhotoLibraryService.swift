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
    private static let thumbnailTimeout = Duration.seconds(30)
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

    /// Never downloads from iCloud: `isNetworkAccessAllowed` stays false. The request ends when the
    /// task is cancelled or after `thumbnailTimeout`, so a scan can always be stopped.
    func thumbnail(for id: String, side: CGFloat, exact: Bool) async -> ThumbnailOutcome {
        guard let asset = asset(for: id) else { return .failed }
        let manager = imageManager
        let request = ThumbnailRequest()
        let timeout = Task {
            do { try await Task.sleep(for: Self.thumbnailTimeout) } catch { return }
            if let requestID = request.cancel() { manager.cancelImageRequest(requestID) }
        }
        defer { timeout.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ThumbnailOutcome, Never>) in
                guard request.start(continuation) else { return }
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = exact ? .exact : .fast
                options.isNetworkAccessAllowed = false
                options.isSynchronous = false
                let requestID = manager.requestImage(
                    for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit, options: options
                ) { image, info in
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                    let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                    // A degraded preview of a local photo is followed by the final image. A degraded
                    // preview of an iCloud photo is all there will ever be: not scanned.
                    if degraded && !inCloud { return }
                    if let cgImage = image?.cgImage, !degraded {
                        request.finish(.image(cgImage))
                    } else {
                        request.finish(inCloud ? .notOnDevice : .failed)
                    }
                }
                if request.register(requestID) { manager.cancelImageRequest(requestID) }
            }
        } onCancel: {
            if let requestID = request.cancel() { manager.cancelImageRequest(requestID) }
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

/// Owns one thumbnail request and resumes its continuation exactly once, whichever comes first:
/// the image, a cancellation or the timeout.
private final class ThumbnailRequest: @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<ThumbnailOutcome, Never>?
        var requestID: PHImageRequestID?
        var finished = false
        var cancelled = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// False when the request was already cancelled: the continuation is resumed and nothing starts.
    func start(_ continuation: CheckedContinuation<ThumbnailOutcome, Never>) -> Bool {
        let cancelled = state.withLock { state -> Bool in
            if state.cancelled { state.finished = true; return true }
            state.continuation = continuation
            return false
        }
        if cancelled { continuation.resume(returning: .failed) }
        return !cancelled
    }

    /// True when the request is already over, so PhotoKit should be told to drop it.
    func register(_ requestID: PHImageRequestID) -> Bool {
        state.withLock { state in
            state.requestID = requestID
            return state.cancelled || state.finished
        }
    }

    func finish(_ outcome: ThumbnailOutcome) {
        let continuation = state.withLock { state -> CheckedContinuation<ThumbnailOutcome, Never>? in
            guard !state.finished else { return nil }
            state.finished = true
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(returning: outcome)
    }

    /// Ends the request as failed. Returns the PhotoKit request to cancel, if it has started.
    func cancel() -> PHImageRequestID? {
        let requestID = state.withLock { state -> PHImageRequestID? in
            state.cancelled = true
            return state.requestID
        }
        finish(.failed)
        return requestID
    }
}
