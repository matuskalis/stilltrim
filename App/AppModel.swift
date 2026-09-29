import CleanupCore
import CoreGraphics
import Observation
import Photos
import UIKit

struct DeletionSummary: Identifiable, Equatable {
    let id = UUID()
    let count: Int
    let bytes: Int64
}

@MainActor
final class ThumbnailLoader {
    private let library: PhotoLibraryService
    private let cache = NSCache<NSString, CGImage>()

    init(library: PhotoLibraryService) {
        self.library = library
        cache.countLimit = 600
    }

    func image(for id: String, side: CGFloat) async -> CGImage? {
        let key = "\(id)@\(Int(side))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard case let .image(image) = await library.thumbnail(for: id, side: side, exact: false) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

@MainActor @Observable
final class AppModel {
    enum ScanState: Equatable {
        case idle
        case scanning(ScanProgress)
        case finished
        case failed(String)
    }

    let access = LibraryAccess()
    let library = PhotoLibraryService()
    let thumbnails: ThumbnailLoader
    private(set) var scanState: ScanState = .idle
    private var review = ReviewState()
    private(set) var lastDeletion: DeletionSummary?
    private(set) var deletionError: String?
    var debugOpenCategory: CleanupCategory?

    @ObservationIgnored private let cache = AnalysisCache()
    @ObservationIgnored private let keepList = KeepList()
    @ObservationIgnored private let fingerprinter: any Fingerprinter
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// Bumped whenever a scan is started or discarded, so a finishing scan can tell it is stale.
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var isErasing = false

    init() {
        thumbnails = ThumbnailLoader(library: library)
        #if DEBUG
        let arguments = CommandLine.arguments
        // The Simulator's Vision returns near-identical vectors for every photo.
        fingerprinter = arguments.contains("-tinyFingerprints") ? TinyImageFingerprinter() : VisionFingerprinter()
        if let index = arguments.firstIndex(of: "-openCategory"), index + 1 < arguments.count {
            debugOpenCategory = CleanupCategory(rawValue: arguments[index + 1])
        }
        #else
        fingerprinter = VisionFingerprinter()
        #endif
        Task {
            await library.onLibraryChange { [weak self] change in
                Task { @MainActor in self?.libraryChanged(change) }
            }
        }
    }

    var result: ScanResult? { review.result }
    var selection: Set<String> { review.selection }

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    func startScanIfRequestedByLaunchArguments() {
        #if DEBUG
        if CommandLine.arguments.contains("-autoScan"), access.canRead, scanState == .idle { startScan() }
        #endif
    }

    func startScan() {
        guard access.canRead, !isScanning, !isErasing else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        review.beginScan()
        scanState = .scanning(ScanProgress(stage: .listing, done: 0, total: 0))
        scanGeneration += 1
        let generation = scanGeneration
        scanTask = Task {
            defer {
                if generation == scanGeneration { UIApplication.shared.isIdleTimerDisabled = false }
            }
            await keepList.load()
            let pipeline = ScanPipeline(
                library: library, fingerprinter: fingerprinter, cache: cache, keptIDs: await keepList.ids
            )
            do {
                let scanned = try await pipeline.run { progress in
                    Task { @MainActor in self.apply(progress) }
                }
                guard generation == scanGeneration else { return }
                if review.finishScan(with: scanned) {
                    scanState = .finished
                } else {
                    scanState = .failed("Your photo library changed during the scan. Scan again.")
                }
            } catch is CancellationError {
                if generation == scanGeneration {
                    review.abortScan()
                    scanState = .idle
                }
            } catch ScanError.analysisUnavailable {
                if generation == scanGeneration {
                    review.abortScan()
                    scanState = .failed("This device could not analyse the photos. Nothing was changed.")
                }
            } catch {
                if generation == scanGeneration {
                    review.abortScan()
                    scanState = .failed("The scan stopped: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    private func apply(_ progress: ScanProgress) {
        if isScanning { scanState = .scanning(progress) }
    }

    private func libraryChanged(_ change: LibraryChange) {
        switch change {
        case let .assets(ids):
            review.libraryChanged(ids: ids)
        case .everything:
            review.libraryChangedEverywhere()
            if !isScanning { scanState = .idle }
        }
    }

    func toggle(_ id: String) {
        review.toggle(id)
    }

    func select(ids: Set<String>) {
        review.select(ids)
    }

    func deselect(ids: Set<String>) {
        review.deselect(ids)
    }

    func selectedIDs(in category: CleanupCategory) -> Set<String> {
        review.selectedIDs(in: category)
    }

    func delete(ids requested: Set<String>) async {
        guard !requested.isEmpty, let before = review.result else { return }
        deletionError = nil
        let deleted: Set<String>
        do {
            deleted = try await library.delete(ids: requested)
        } catch {
            if (error as? PHPhotosError)?.code != .userCancelled {
                deletionError = "The photos could not be deleted: \(error.localizedDescription)"
            }
            return
        }
        let bytes = before.byteSize(of: deleted)
        // Ids that were already gone from the library leave the results as well.
        review.remove(ids: requested)
        await cache.remove(ids: Array(requested))
        await cache.save()
        if !deleted.isEmpty { lastDeletion = DeletionSummary(count: deleted.count, bytes: bytes) }
    }

    /// The best photo of a group stays in the library anyway, so it cannot be "kept" away.
    func keep(ids: Set<String>) async {
        guard let current = review.result else { return }
        let keepable = ids.subtracting(current.keeperIDs)
        guard !keepable.isEmpty else { return }
        await keepList.add(Array(keepable))
        review.remove(ids: keepable)
    }

    func dismissDeletionSummary() {
        lastDeletion = nil
    }

    func dismissDeletionError() {
        deletionError = nil
    }

    /// Waits for a running scan to stop first, so it cannot write results back afterwards.
    func eraseAppData() async {
        isErasing = true
        scanGeneration += 1
        scanTask?.cancel()
        await scanTask?.value
        scanTask = nil
        await cache.erase()
        await keepList.erase()
        review.clear()
        scanState = .idle
        UIApplication.shared.isIdleTimerDisabled = false
        isErasing = false
    }
}
