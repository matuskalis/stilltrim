import CleanupCore
import Foundation

/// Everything the app keeps lives in one folder in Application Support, excluded from backups.
enum AppStorage {
    static func directory() -> URL {
        var url = URL.applicationSupportDirectory.appending(path: "Stilltrim", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }
}

actor AnalysisCache {
    struct Entry: Codable, Sendable {
        var modificationDate: Date?
        var byteSize: Int64
        var isEdited: Bool
        var metrics: ImageMetrics?
        var fingerprint: Data?
    }

    private struct File: Codable {
        var version: Int
        var fingerprinterID: String
        var entries: [String: Entry]
    }

    private static let version = 1
    private let url = AppStorage.directory().appending(path: "analysis-cache.plist")
    private var fingerprinterID = ""
    private var entries: [String: Entry] = [:]

    /// A different fingerprinter or file version drops everything: old vectors cannot be compared.
    func load(fingerprinterID: String) {
        self.fingerprinterID = fingerprinterID
        entries = [:]
        guard let data = try? Data(contentsOf: url),
              let file = try? PropertyListDecoder().decode(File.self, from: data),
              file.version == Self.version, file.fingerprinterID == fingerprinterID
        else { return }
        entries = file.entries
    }

    /// Entries whose photo has not been modified since they were stored.
    func lookup(_ records: [AssetRecord]) -> [String: Entry] {
        var hits: [String: Entry] = [:]
        for record in records {
            if let entry = entries[record.id], entry.modificationDate == record.modificationDate {
                hits[record.id] = entry
            }
        }
        return hits
    }

    func store(_ entry: Entry, for id: String) {
        entries[id] = entry
    }

    func remove(ids: [String]) {
        for id in ids { entries[id] = nil }
    }

    /// Forgets photos that are gone from the library, so the file cannot grow without bound.
    func retain(ids: Set<String>) {
        entries = entries.filter { ids.contains($0.key) }
    }

    func save() {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let file = File(version: Self.version, fingerprinterID: fingerprinterID, entries: entries)
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func erase() {
        entries = [:]
        try? FileManager.default.removeItem(at: url)
    }
}

actor KeepList {
    private let url = AppStorage.directory().appending(path: "keep-list.json")
    private(set) var ids: Set<String> = []

    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return }
        ids = decoded
    }

    func add(_ newIDs: [String]) {
        ids.formUnion(newIDs)
        guard let data = try? JSONEncoder().encode(ids) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func erase() {
        ids = []
        try? FileManager.default.removeItem(at: url)
    }
}
