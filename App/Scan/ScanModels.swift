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
        case .screenshots: "Screenshots and screen recordings, sorted by kind"
        case .similar: "Photos that look alike and were taken minutes apart. One is marked Best."
        case .lowQuality: "Blurry, dark, blank or too bright photos"
        case .bigVideos: "Videos of 50 MB or more"
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

extension ScreenshotKind {
    var title: String {
        switch self {
        case .chat: "Chats"
        case .receipt: "Receipts and tickets"
        case .code: "Codes and barcodes"
        case .oneTimeCode: "Verification codes"
        case .map: "Maps"
        case .web: "Web pages"
        case .social: "Social posts"
        case .document: "Documents"
        case .photo: "Pictures"
        case .recording: "Screen recordings"
        case .mix: "Mix"
        }
    }
}

extension ScanStage {
    var stepTitle: String {
        switch self {
        case .listing: "Listing photos"
        case .sizing: "Measuring file sizes"
        case .analyzing: "Checking photos"
        case .reading: "Reading screenshots"
        case .grouping: "Grouping similar shots"
        }
    }
}

struct ScanProgress: Sendable, Equatable {
    typealias Stage = ScanStage

    var stage: Stage
    var done: Int
    var total: Int

    var fraction: Double? {
        total > 0 ? Double(done) / Double(total) : nil
    }

    var overall: Double { ScanPlan.overall(stage: stage, done: done, total: total) }

    var label: String {
        switch stage {
        case .listing: "Reading your library"
        case .sizing: "Measuring file sizes"
        case .analyzing: "Checking photo \(done.formatted()) of \(total.formatted())"
        case .reading: "Reading screenshot \(done.formatted()) of \(total.formatted())"
        case .grouping: "Comparing photos"
        }
    }
}
