import CleanupCore
import SwiftUI

private struct PreviewTarget: Identifiable {
    let id: String
}

private let scrollSpace = "review-scroll"

/// What the list has reported about each photo it drew: fully above the top edge (scrolled past) or not.
/// The first reported photo that is not scrolled past, in display order, is where the user is. Only photos
/// reported as scrolled past can be deleted above it, so rows a fast flick skipped without ever drawing
/// them are never included. Only the delete bar reads this, so scrolling never re-evaluates the grid.
/// Scroll position bindings were tried instead and froze the app on a list of a few dozen groups.
@MainActor @Observable
private final class ScrollTracker {
    private(set) var scrolledPast: Set<String> = []
    private(set) var notScrolledPast: Set<String> = []

    func update(_ id: String, scrolledPast isPast: Bool) {
        if isPast {
            notScrolledPast.remove(id)
            scrolledPast.insert(id)
        } else {
            scrolledPast.remove(id)
            notScrolledPast.insert(id)
        }
    }
}

/// One heading and its photos. A category without headings is one section with no title.
private struct ReviewSection: Identifiable {
    let id: String
    let title: String?
    let items: [CleanupItem]
    /// Similar groups come with their suggestions already selected, so they get no select button.
    let canSelectAll: Bool
}

struct ReviewView: View {
    let category: CleanupCategory
    @Environment(AppModel.self) private var model
    @State private var preview: PreviewTarget?
    @State private var tracker = ScrollTracker()

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 2)]

    var body: some View {
        ScrollViewReader { proxy in
            list
                .safeAreaInset(edge: .bottom) {
                    DeleteBar(category: category, tracker: tracker) { ids, anchor in
                        await model.delete(ids: ids)
                        // The photos above are gone, so everything below moves up. Go back to where the
                        // user was, or the next rows would slide past unseen.
                        await Task.yield()
                        if let anchor { proxy.scrollTo(anchor, anchor: .top) }
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

    private var list: some View {
        ScrollView {
            if let result = model.result {
                if result.items(in: category).isEmpty {
                    ContentUnavailableView("Nothing here", systemImage: category.symbol)
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 2, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections(of: result)) { section in
                            Section {
                                ForEach(section.items) { cell($0) }
                            } header: {
                                header(section)
                            } footer: {
                                if section.title != nil { Color.clear.frame(height: 16) }
                            }
                        }
                    }
                }
            }
        }
        .coordinateSpace(.named(scrollSpace))
    }

    /// The same order `ScanResult.items(in:)` uses, which is what "above" is measured against.
    private func sections(of result: ScanResult) -> [ReviewSection] {
        switch category {
        case .similar:
            result.similarGroups.map { group in
                ReviewSection(
                    id: "group-\(group.id)",
                    title: "\(group.items.count) similar · \(group.reclaimableBytes.formatted(.byteCount(style: .file))) to gain",
                    items: group.items, canSelectAll: false
                )
            }
        case .screenshots:
            result.screenshotSections.map { section in
                ReviewSection(
                    id: "kind-\(section.id)",
                    title: "\(section.kind.title) · \(section.items.count.formatted()) · \(section.byteSize.formatted(.byteCount(style: .file)))",
                    items: section.items, canSelectAll: true
                )
            }
        default:
            [ReviewSection(id: "category-\(category.id)", title: nil, items: result.items(in: category), canSelectAll: false)]
        }
    }

    @ViewBuilder private func header(_ section: ReviewSection) -> some View {
        if let title = section.title {
            HStack {
                Text(title)
                Spacer()
                if section.canSelectAll {
                    Button(isFullySelected(section) ? "Deselect" : "Select") { toggle(section) }
                        .accessibilityIdentifier("select-\(section.id)")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }

    private func isFullySelected(_ section: ReviewSection) -> Bool {
        Set(section.items.map(\.id)).isSubset(of: model.selection)
    }

    private func toggle(_ section: ReviewSection) {
        let ids = Set(section.items.map(\.id))
        if isFullySelected(section) { model.deselect(ids: ids) } else { model.select(ids: ids) }
    }

    private func cell(_ item: CleanupItem) -> some View {
        Button { model.toggle(item.id) } label: {
            PhotoCell(item: item, isSelected: model.selection.contains(item.id))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cell-\(item.id)")
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.frame(in: .named(scrollSpace)).maxY <= 0
        } action: { scrolledPast in
            tracker.update(item.id, scrolledPast: scrolledPast)
        }
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
}

private struct DeleteBar: View {
    let category: CleanupCategory
    let tracker: ScrollTracker
    /// Deletes the photos, then puts the list back at the photo it is given.
    let deleteAbove: (Set<String>, String?) async -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let ids = model.selectedIDs(in: category)
        let bytes = model.result?.byteSize(of: ids) ?? 0
        let top = model.firstShown(in: category, among: tracker.notScrolledPast)
        let above = top.map { model.selectedIDs(in: category, above: $0, scrolledPast: tracker.scrolledPast) } ?? []
        return HStack(spacing: 10) {
            if !above.isEmpty {
                Button {
                    Task { await deleteAbove(above, top) }
                } label: {
                    Text("Delete \(above.count.formatted()) above")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("delete-above")
            }
            Button {
                Task { await model.delete(ids: ids) }
            } label: {
                Text(ids.isEmpty
                    ? "Select items to delete"
                    : "Delete \(ids.count.formatted()) · \(bytes.formatted(.byteCount(style: .file)))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(ids.isEmpty)
        }
        .tint(.accentColor)
        .controlSize(.large)
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
        if let kind = item.screenshotKind { parts.append(kind.title) }
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
