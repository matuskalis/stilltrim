import CleanupCore
import Foundation

extension CleanupCategory {
    var title: String {
        switch self {
        case .screenshots: "Screenshots"
        case .similar: "Similar shots"
        case .lowQuality: "Blurry and dark"
        case .bigVideos: "Big videos"
        }
    }

    var explanation: String {
        switch self {
        case .screenshots: "Screenshots and screen recordings"
        case .similar: "Duplicates and near-duplicates"
        case .lowQuality: "Blurry, dark, blank and overexposed shots"
        case .bigVideos: "Videos over 50 MB"
        }
    }

    var symbol: String {
        switch self {
        case .screenshots: "camera.viewfinder"
        case .similar: "square.on.square"
        case .lowQuality: "aqi.medium"
        case .bigVideos: "film"
        }
    }
}

struct ScanProgress: Sendable, Equatable {
    enum Stage: Sendable { case listing, sizing, analyzing, grouping }

    var stage: Stage
    var done: Int
    var total: Int

    var fraction: Double? {
        total > 0 ? Double(done) / Double(total) : nil
    }

    var label: String {
        switch stage {
        case .listing: "Reading your library"
        case .sizing: "Measuring file sizes"
        case .analyzing: "Checking photo \(done.formatted()) of \(total.formatted())"
        case .grouping: "Comparing photos"
        }
    }
}
