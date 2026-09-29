@preconcurrency import Photos
import os

enum LibraryChange: Sendable {
    /// These assets were removed or changed (favourited, edited, hidden) since the scan.
    case assets(Set<String>)
    /// PhotoKit could not describe the change, so nothing from the scan can be trusted.
    case everything
}

/// Tells the app when the photos it scanned change underneath it, for example a favourite
/// added in the Photos app. Results for those assets are dropped rather than acted on.
final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private struct State {
        var watched: PHFetchResult<PHAsset>?
        var handler: (@Sendable (LibraryChange) -> Void)?
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    func watch(_ result: PHFetchResult<PHAsset>) {
        state.withLock { $0.watched = result }
    }

    func setHandler(_ handler: @escaping @Sendable (LibraryChange) -> Void) {
        state.withLock { $0.handler = handler }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        let (watched, handler) = state.withLock { ($0.watched, $0.handler) }
        guard let watched, let handler, let details = changeInstance.changeDetails(for: watched) else { return }
        state.withLock { $0.watched = details.fetchResultAfterChanges }
        guard details.hasIncrementalChanges else {
            handler(.everything)
            return
        }
        var affected = Set<String>()
        for asset in details.removedObjects + details.changedObjects { affected.insert(asset.localIdentifier) }
        if !affected.isEmpty { handler(.assets(affected)) }
    }
}
