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
                        ForEach(CleanupCategory.allCases) { category in
                            NavigationLink(value: category) {
                                CategoryRow(category: category, result: result)
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
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
                Text(progress.label)
                    .font(.headline)
                Button("Cancel", role: .cancel) { model.cancelScan() }
                    .padding(.top, 4)
            case .finished:
                let total = model.result?.totalReclaimableBytes ?? 0
                Text(total == 0 ? "Nothing to review" : total.formatted(.byteCount(style: .file)))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(total == 0 ? "Stilltrim found no screenshots, similar shots, blurry photos or big videos." : "can be cleaned")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
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

private struct CategoryRow: View {
    let category: CleanupCategory
    let result: ScanResult

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: category.symbol)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if bytes > 0 {
                Text(bytes.formatted(.byteCount(style: .file)))
                    .foregroundStyle(.secondary)
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
