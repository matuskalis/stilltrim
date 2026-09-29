import CleanupCore
import SwiftUI

private struct PreviewTarget: Identifiable {
    let id: String
}

struct ReviewView: View {
    let category: CleanupCategory
    @Environment(AppModel.self) private var model
    @State private var preview: PreviewTarget?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 2)]

    var body: some View {
        ScrollView {
            if let result = model.result {
                if result.items(in: category).isEmpty {
                    ContentUnavailableView("Nothing here", systemImage: category.symbol)
                        .padding(.top, 80)
                } else if category == .similar {
                    similarContent(result)
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(result.items(in: category)) { cell($0) }
                    }
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selectionButtonTitle, action: toggleAll)
            }
        }
        .safeAreaInset(edge: .bottom) { deleteBar }
        .sheet(item: $preview) { PreviewView(id: $0.id) }
        .alert(
            "Could not delete",
            isPresented: Binding(get: { model.deletionError != nil }, set: { _ in model.dismissDeletionError() })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.deletionError ?? "")
        }
    }

    private func similarContent(_ result: ScanResult) -> some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(result.similarGroups) { group in
                Section {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(group.items) { cell($0) }
                    }
                    .padding(.bottom, 18)
                } header: {
                    Text("\(group.items.count) similar · \(group.reclaimableBytes.formatted(.byteCount(style: .file))) to gain")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
            }
        }
    }

    private func cell(_ item: CleanupItem) -> some View {
        Button { model.toggle(item.id) } label: {
            PhotoCell(item: item, isSelected: model.selection.contains(item.id))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Preview", systemImage: "eye") { preview = PreviewTarget(id: item.id) }
            if !item.isKeeper {
                Button("Keep, do not show again", systemImage: "heart") {
                    Task { await model.keep(ids: [item.id]) }
                }
            }
        }
    }

    private var selectableIDs: Set<String> {
        guard let result = model.result else { return [] }
        return category == .similar ? result.suggestedSelection : Set(result.items(in: category).map(\.id))
    }

    private var allSelectableSelected: Bool {
        !selectableIDs.isEmpty && selectableIDs.isSubset(of: model.selection)
    }

    private var selectionButtonTitle: String {
        if allSelectableSelected { return "Deselect all" }
        return category == .similar ? "Select suggested" : "Select all"
    }

    /// Deselecting clears everything in this category, including photos picked by hand.
    private func toggleAll() {
        if allSelectableSelected {
            model.deselect(ids: Set(model.result?.items(in: category).map(\.id) ?? []))
        } else {
            model.select(ids: selectableIDs)
        }
    }

    private var deleteBar: some View {
        let ids = model.selectedIDs(in: category)
        let bytes = model.result?.byteSize(of: ids) ?? 0
        return Button {
            Task { await model.delete(ids: ids) }
        } label: {
            Text(ids.isEmpty
                ? "Select items to delete"
                : "Delete \(ids.count.formatted()) · \(bytes.formatted(.byteCount(style: .file)))")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .disabled(ids.isEmpty)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct PhotoCell: View {
    let item: CleanupItem
    let isSelected: Bool
    @Environment(AppModel.self) private var model
    @State private var image: CGImage?

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) { selectionMark }
            .overlay(alignment: .bottomLeading) { badge }
            .overlay(alignment: .bottomTrailing) { videoLabel }
            .overlay { if isSelected { Rectangle().strokeBorder(Color.accentColor, lineWidth: 3) } }
            .task(id: item.id) { image = await model.thumbnails.image(for: item.id, side: 400) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var selectionMark: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, isSelected ? Color.accentColor : Color.white.opacity(0.9))
            .font(.title3)
            .shadow(radius: 2)
            .padding(6)
    }

    @ViewBuilder private var badge: some View {
        if item.isKeeper {
            pill("Best", symbol: "star.fill")
        } else if let text = item.badge {
            pill(text)
        }
    }

    @ViewBuilder private var videoLabel: some View {
        if let duration = item.duration {
            pill("\(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))) · \(item.byteSize.formatted(.byteCount(style: .file)))")
        }
    }

    private func pill(_ text: String, symbol: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(5)
    }

    private var accessibilityLabel: String {
        var parts = [item.creationDate.formatted(date: .abbreviated, time: .shortened)]
        if item.isKeeper { parts.append("best shot") }
        if let badge = item.badge { parts.append(badge) }
        parts.append(item.byteSize.formatted(.byteCount(style: .file)))
        return parts.joined(separator: ", ")
    }
}

private struct PreviewView: View {
    let id: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    @State private var finished = false

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else if finished {
                    ContentUnavailableView(
                        "Not on this phone", systemImage: "icloud",
                        description: Text("This photo is only in iCloud. The app never downloads photos.")
                    )
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                image = await model.thumbnails.image(for: id, side: 1600)
                finished = true
            }
        }
    }
}
