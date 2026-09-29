import CleanupCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [CleanupCategory] = []
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
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
                            Text("\(result.notOnDevice.formatted()) photos are only in iCloud and were not checked. This app never downloads them.")
                        }
                    }
                } else if case .idle = model.scanState {
                    Section("What gets checked") {
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
                Text("Your photos stay on this phone.")
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
                Text(total.formatted(.byteCount(style: .file)))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(total == 0 ? "Nothing to clean up" : "can be cleaned")
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
            Text(result.reclaimableBytes(in: category).formatted(.byteCount(style: .file)))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        let count = result.removableCount(in: category)
        switch category {
        case .similar:
            return "\(plural(count, "photo")) in \(plural(result.similarGroups.count, "group"))"
        case .bigVideos:
            return plural(count, "video")
        default:
            return plural(count, "item")
        }
    }

    private func plural(_ count: Int, _ noun: String) -> String {
        "\(count.formatted()) \(noun)\(count == 1 ? "" : "s")"
    }
}
