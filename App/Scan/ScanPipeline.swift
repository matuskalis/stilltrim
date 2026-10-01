import CleanupCore
import CoreGraphics
import Foundation

enum ScanError: Error {
    case analysisUnavailable
}

struct ScanPipeline: Sendable {
    static let bigVideoBytes: Int64 = 50_000_000
    static let thumbnailSide: CGFloat = 512
    /// Small print on a phone screenshot needs more pixels than a similarity check does. At 1,024 px the fast
    /// reader lost the colon in clock times and the short lines of dark chats. At 1,536 px it read them, for
    /// about the same time (measured on a Mac, not yet on a phone).
    static let screenshotSide: CGFloat = 1_536
    static let maxConcurrentAnalyses = 4
    private static let sizingBatch = 500
    private static let saveEvery = 1_500
    private static let failuresBeforeGivingUp = 20

    let library: PhotoLibraryService
    let fingerprinter: any Fingerprinter
    let cache: AnalysisCache
    let keptIDs: Set<String>

    private enum AnalysisOutcome: Sendable {
        case analyzed(id: String, metrics: ImageMetrics?, fingerprint: Fingerprint)
        case notOnDevice
        case failed
    }

    func run(progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResult {
        progress(ScanProgress(stage: .listing, done: 0, total: 0))
        let records = await library.loadAssets().filter { !keptIDs.contains($0.id) }
        await cache.load(fingerprinterID: fingerprinter.identifier)
        await cache.retain(ids: Set(records.map(\.id)))
        do {
            return try await scan(records, progress: progress)
        } catch {
            await cache.save()
            throw error
        }
    }

    private func scan(_ records: [AssetRecord], progress: @Sendable (ScanProgress) -> Void) async throws -> ScanResult {
        var entries = await cache.lookup(records)
        try Task.checkCancellation()
        try await addSizes(for: records, entries: &entries, progress: progress)

        var result = ScanResult()
        var photos: [AssetRecord] = []
        var screenshots: [AssetRecord] = []
        for record in records {
            let bytes = entries[record.id]?.byteSize ?? 0
            switch record.kind {
            case .video where record.isScreenRecording:
                result.screenshots.append(item(record, bytes: bytes, screenshotKind: .recording, isEdited: entries[record.id]?.isEdited ?? false))
            case .video where bytes >= Self.bigVideoBytes:
                result.bigVideos.append(item(record, bytes: bytes, isEdited: entries[record.id]?.isEdited ?? false))
            case .photo where record.isScreenshot:
                screenshots.append(record)
            case .photo:
                photos.append(record)
            default:
                break
            }
        }
        result.scannedPhotos = photos.count

        result.notOnDevice = try await analyze(photos, entries: &entries, progress: progress)
        try await readScreenshots(screenshots, entries: &entries, progress: progress)
        await cache.save()
        try Task.checkCancellation()

        for record in screenshots {
            let entry = entries[record.id]
            result.screenshots.append(item(
                record, bytes: entry?.byteSize ?? 0, screenshotKind: entry?.currentScreenshotKind ?? .mix,
                isEdited: entry?.isEdited ?? false
            ))
        }

        progress(ScanProgress(stage: .grouping, done: 0, total: 0))
        let groups = makeGroups(photos: photos, entries: entries)
        var grouped = Set<String>()
        for group in groups {
            grouped.formUnion(group.items.map(\.id))
            result.similarGroups.append(group)
        }
        let thresholds = QualityThresholds.standard
        for record in photos where !grouped.contains(record.id) {
            guard let metrics = entries[record.id]?.metrics, let issue = thresholds.issue(for: metrics) else { continue }
            result.lowQuality.append(item(record, bytes: entries[record.id]?.byteSize ?? 0, badge: Self.badge(for: issue), isEdited: entries[record.id]?.isEdited ?? false))
        }

        result.arrangeScreenshots()
        result.lowQuality.sort { $0.byteSize > $1.byteSize }
        result.bigVideos.sort { $0.byteSize > $1.byteSize }
        result.similarGroups.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        try Task.checkCancellation()
        return result
    }

    private func addSizes(
        for records: [AssetRecord], entries: inout [String: AnalysisCache.Entry],
        progress: @Sendable (ScanProgress) -> Void
    ) async throws {
        let missing = records.filter { entries[$0.id] == nil || (entries[$0.id]?.stillBytes == nil && $0.kind == .photo) }
        var done = 0
        for start in stride(from: 0, to: missing.count, by: Self.sizingBatch) {
            try Task.checkCancellation()
            let batch = Array(missing[start..<min(start + Self.sizingBatch, missing.count)])
            let details = await library.details(for: batch.map(\.id))
            for record in batch {
                let detail = details[record.id]
                var entry = entries[record.id] ?? AnalysisCache.Entry(
                    modificationDate: record.modificationDate, byteSize: detail?.byteSize ?? 0,
                    isEdited: detail?.isEdited ?? false, metrics: nil, fingerprint: nil
                )
                entry.stillBytes = detail?.stillBytes ?? 0
                entries[record.id] = entry
                await cache.store(entry, for: record.id)
            }
            done += batch.count
            progress(ScanProgress(stage: .sizing, done: done, total: missing.count))
        }
    }

    /// Returns how many photos were skipped because their pixels are only in iCloud.
    /// Throws only when nothing has ever been analysed, so one broken photo cannot fail every rescan.
    private func analyze(
        _ photos: [AssetRecord], entries: inout [String: AnalysisCache.Entry],
        progress: @Sendable (ScanProgress) -> Void
    ) async throws -> Int {
        let pending = photos.filter { entries[$0.id]?.fingerprint == nil }
        let alreadyDone = photos.count - pending.count
        var notOnDevice = 0, failed = 0, analyzed = 0, sinceSave = 0
        progress(ScanProgress(stage: .analyzing, done: alreadyDone, total: photos.count))

        try await withThrowingTaskGroup(of: AnalysisOutcome.self) { group in
            var next = pending.makeIterator()
            func addNext() {
                guard let record = next.next() else { return }
                group.addTask { await analyzeOne(record) }
            }
            for _ in 0..<Self.maxConcurrentAnalyses { addNext() }

            while let outcome = try await group.next() {
                try Task.checkCancellation()
                switch outcome {
                case let .analyzed(id, metrics, fingerprint):
                    analyzed += 1
                    sinceSave += 1
                    if var entry = entries[id] {
                        entry.metrics = metrics
                        entry.fingerprint = fingerprint.data
                        entries[id] = entry
                        await cache.store(entry, for: id)
                    }
                    if sinceSave >= Self.saveEvery {
                        sinceSave = 0
                        await cache.save()
                    }
                case .notOnDevice:
                    notOnDevice += 1
                case .failed:
                    failed += 1
                }
                let finished = analyzed + notOnDevice + failed
                if finished % 8 == 0 || finished == pending.count {
                    progress(ScanProgress(stage: .analyzing, done: alreadyDone + finished, total: photos.count))
                }
                if alreadyDone == 0, analyzed == 0, failed >= Self.failuresBeforeGivingUp {
                    group.cancelAll()
                    throw ScanError.analysisUnavailable
                }
                addNext()
            }
        }
        if alreadyDone == 0, analyzed == 0, failed > 0 { throw ScanError.analysisUnavailable }
        return notOnDevice
    }

    /// Reads each screenshot once and remembers its kind. One Vision cannot read this time is shown
    /// under "Mix" and tried again on the next scan.
    private func readScreenshots(
        _ screenshots: [AssetRecord], entries: inout [String: AnalysisCache.Entry],
        progress: @Sendable (ScanProgress) -> Void
    ) async throws {
        let pending = screenshots.filter { entries[$0.id]?.currentScreenshotKind == nil }
        guard !pending.isEmpty else { return }
        var done = 0
        progress(ScanProgress(stage: .reading, done: 0, total: pending.count))

        try await withThrowingTaskGroup(of: (id: String, kind: ScreenshotKind?).self) { group in
            var next = pending.makeIterator()
            func addNext() {
                guard let record = next.next() else { return }
                group.addTask { (record.id, await readKind(of: record)) }
            }
            for _ in 0..<Self.maxConcurrentAnalyses { addNext() }

            while let outcome = try await group.next() {
                try Task.checkCancellation()
                if let kind = outcome.kind, var entry = entries[outcome.id] {
                    entry.screenshotKind = kind
                    entry.classifierVersion = ScreenshotClassifier.version
                    entries[outcome.id] = entry
                    await cache.store(entry, for: outcome.id)
                }
                done += 1
                if done % 8 == 0 || done == pending.count {
                    progress(ScanProgress(stage: .reading, done: done, total: pending.count))
                }
                addNext()
            }
        }
    }

    private func readKind(of record: AssetRecord) async -> ScreenshotKind? {
        guard case let .image(image) = await library.thumbnail(for: record.id, side: Self.screenshotSide, exact: true)
        else { return nil }
        return try? ScreenshotAnalyzer.kind(of: image)
    }

    private func analyzeOne(_ record: AssetRecord) async -> AnalysisOutcome {
        switch await library.thumbnail(for: record.id, side: Self.thumbnailSide, exact: true) {
        case let .image(image):
            guard let fingerprint = try? fingerprinter.fingerprint(of: image) else { return .failed }
            return .analyzed(id: record.id, metrics: ImageAnalyzer.measure(image), fingerprint: fingerprint)
        case .notOnDevice:
            return .notOnDevice
        case .failed:
            return .failed
        }
    }

    private func makeGroups(photos: [AssetRecord], entries: [String: AnalysisCache.Entry]) -> [SimilarGroup] {
        var records: [String: AssetRecord] = [:]
        var groupingItems: [GroupingItem] = []
        for record in photos {
            guard let entry = entries[record.id], let data = entry.fingerprint, let fingerprint = Fingerprint(data: data)
            else { continue }
            records[record.id] = record
            groupingItems.append(GroupingItem(
                id: record.id, creationDate: record.creationDate, fingerprint: fingerprint,
                isFavorite: record.isFavorite, isEdited: entry.isEdited,
                pixelCount: record.pixelCount, byteSize: entry.byteSize,
                stillBytes: entry.stillBytes, sharpness: entry.metrics?.fineToCoarse
            ))
        }
        return SimilarityGrouper.groups(from: groupingItems).map { group in
            let items = group.memberIDs.compactMap { id -> CleanupItem? in
                guard let record = records[id] else { return nil }
                return item(record, bytes: entries[id]?.byteSize ?? 0, isKeeper: id == group.keeperID, isEdited: entries[id]?.isEdited ?? false)
            }
            return SimilarGroup(
                id: group.keeperID, items: items, suggestedRemovalIDs: Set(group.suggestedRemovalIDs),
                rankedIDs: group.rankedMemberIDs, confidence: group.confidence, reasonLine: group.reasonLine
            )
        }
    }

    private func item(
        _ record: AssetRecord, bytes: Int64, badge: String? = nil, screenshotKind: ScreenshotKind? = nil,
        isKeeper: Bool = false, isEdited: Bool
    ) -> CleanupItem {
        CleanupItem(
            id: record.id, byteSize: bytes, creationDate: record.creationDate,
            duration: record.kind == .video ? record.duration : nil, badge: badge,
            screenshotKind: screenshotKind, isKeeper: isKeeper,
            modificationDate: record.modificationDate, isFavorite: record.isFavorite, isEdited: isEdited
        )
    }

    private static func badge(for issue: QualityIssue) -> String {
        switch issue {
        case .tooDark: "Very dark"
        case .blownOut: "Overexposed"
        case .flat: "Blank"
        case .blurry: "Blurry"
        }
    }
}
