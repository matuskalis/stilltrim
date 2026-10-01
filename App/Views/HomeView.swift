import CleanupCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [CleanupCategory] = []
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.access.status == .limited {
                    Section {
                        Text("Stilltrim can see only the photos you chose, so results cover those photos only.")
                        Button("Choose more photos") { model.access.presentLimitedPicker() }
                    }
                }
                Section { summary }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                if let result = model.result, model.scanState == .finished {
                    Section {
                        let shares = HomeSummary.barShares(CleanupCategory.allCases.map { result.reclaimableBytes(in: $0) })
                        ForEach(Array(CleanupCategory.allCases.enumerated()), id: \.element) { index, category in
                            NavigationLink(value: category) {
                                CategoryRow(category: category, result: result, share: shares[index])
                            }
                        }
                    } footer: {
                        if result.notOnDevice > 0 {
                            let count = result.notOnDevice
                            Text("\(count.formatted()) \(count == 1 ? "photo is" : "photos are") only in iCloud, so \(count == 1 ? "it was" : "they were") not checked.\nStilltrim never downloads photos.")
                        }
                    }
                } else if case .idle = model.scanState {
                    Section("What Stilltrim looks for") {
                        ForEach(CleanupCategory.allCases) { category in
                            Label(category.explanation, systemImage: category.symbol)
                        }
                    }
                }
            }
            .navigationTitle("Stilltrim")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
            .navigationDestination(for: CleanupCategory.self) { ReviewView(category: $0) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: Binding(get: { model.lastDeletion }, set: { _ in model.dismissDeletionSummary() })) {
                DeletionSummaryView(summary: $0)
            }
            .onChange(of: model.scanState) {
                #if DEBUG
                if model.scanState == .finished, let category = model.debugOpenCategory {
                    path = [category]
                    model.debugOpenCategory = nil
                }
                #endif
            }
        }
    }

    @ViewBuilder private var hero: some View {
        let summary = HomeSummary(
            itemCount: model.result?.totalRemovableCount ?? 0,
            bytes: model.result?.totalReclaimableBytes ?? 0
        )
        switch summary {
        case .nothing:
            Text("Nothing to review")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("Stilltrim found no screenshots, similar shots, blurry photos or big videos.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        case let .bytes(bytes):
            heroNumber(ByteFormat.size(bytes) ?? "", caption: "to review")
        case let .items(count):
            heroNumber(count.formatted(), caption: count == 1 ? "item to review" : "items to review")
        }
        if summary != .nothing {
            Text("Counts screenshots, extra similar shots, blurry photos and big videos. Nothing is deleted until you confirm.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    @ViewBuilder private func heroNumber(_ number: String, caption: LocalizedStringKey) -> some View {
        Text(number)
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        Text(caption)
            .font(.title3)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var summary: some View {
        VStack(spacing: 10) {
            switch model.scanState {
            case .idle:
                Text("Ready to scan")
                    .font(.title2.bold())
                Text("Scanning deletes nothing. Stilltrim sends nothing off this phone.")
                    .foregroundStyle(.secondary)
                Button("Scan photos") { model.startScan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
            case let .scanning(progress):
                ScanStatusView(progress: progress, startedAt: model.scanStartedAt)
                Button("Cancel", role: .cancel) { model.cancelScan() }
                    .padding(.top, 4)
            case .finished:
                hero
                Button("Scan again") { model.startScan() }
                    .padding(.top, 4)
            case let .failed(message):
                Text(message)
                    .multilineTextAlignment(.center)
                Button("Try again") { model.startScan() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Length shows the share of the biggest category. The size and count beside it say the same in text.
private struct ShareBar: View {
    let share: Double

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(.tint).frame(width: proxy.size.width * share)
                }
            }
            .accessibilityHidden(true)
    }
}

private struct CategoryRow: View {
    let category: CleanupCategory
    let result: ScanResult
    let share: Double

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: category.symbol)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if share > 0 {
                    ShareBar(share: share)
                }
            }
            Spacer()
            if let size = ByteFormat.size(bytes) {
                Text(size)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 4)
    }

    private var bytes: Int64 { result.reclaimableBytes(in: category) }

    private var detail: String {
        let count = result.removableCount(in: category)
        if count == 0 { return "Nothing found" }
        let number = count.formatted()
        let isOne = count == 1
        switch category {
        case .similar: return "\(number) extra \(isOne ? "photo" : "photos")"
        case .bigVideos: return "\(number) \(isOne ? "video" : "videos")"
        case .lowQuality: return "\(number) \(isOne ? "photo" : "photos")"
        case .screenshots: return isOne ? "1 screenshot or recording" : "\(number) screenshots and recordings"
        }
    }
}
