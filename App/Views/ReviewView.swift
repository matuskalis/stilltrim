import CleanupCore
import SwiftUI
import UIKit

private struct PreviewTarget: Identifiable {
    let id: String
}

private let scrollSpace = "review-scroll"

private enum CellPosition {
    case above, onScreen, below
}

/// What the list has reported about each photo it drew. A photo counts as scrolled past only when it was
/// crossing the visible area in at least the minimum transit time (`SeenTracker`) and then left through the top, so rows a flick skipped, or
/// only showed for a few frames, are never included. The first reported photo that is not scrolled past, in
/// display order, is where the user is. Only the delete bar reads this, so scrolling never re-evaluates the
/// grid. Scroll position bindings were tried instead and froze the app on a list of a few dozen groups.
@MainActor @Observable
private final class ScrollTracker {
    private(set) var scrolledPast: Set<String> = []
    private(set) var notScrolledPast: Set<String> = []
    /// The part of the list the user can see: below the navigation bar, above the delete bar and receipt strip.
    @ObservationIgnored var visibleTop = CGFloat.zero
    @ObservationIgnored var visibleBottom = CGFloat.infinity
    @ObservationIgnored private var dwell = SeenTracker()

    func update(_ id: String, _ position: CellPosition) {
        let wasSeen = dwell.seen.contains(id)
        switch position {
        case .above:
            notScrolledPast.remove(id)
            dwell.scrolledPast(id, at: .now)
        case .onScreen:
            notScrolledPast.insert(id)
            dwell.appeared(id, at: .now)
        case .below:
            notScrolledPast.insert(id)
            dwell.disappeared(id)
        }
        if dwell.seen.contains(id) != wasSeen { scrolledPast = dwell.seen }
    }

    /// A photo that left the screen without a last report is unknown again, so a hard flick cannot leave
    /// it pinned as "not scrolled past" at the top of the list.
    func forget(_ id: String) {
        if notScrolledPast.contains(id) { notScrolledPast.remove(id) }
        dwell.disappeared(id)
    }
}

/// One heading and its photos. A category without headings is one section with no title.
private struct ReviewSection: Identifiable {
    let id: String
    let title: String?
    /// The keeper rule's reason, shown under the title as secondary text.
    var subtitle: String? = nil
    let items: [CleanupItem]
    /// What the select button ticks. Empty for similar groups, which come with their suggestions already
    /// selected, and when every item is a favourite or an edited photo.
    let bulkSelectableIDs: Set<String>
}

struct ReviewView: View {
    let category: CleanupCategory
    @Environment(AppModel.self) private var model
    @State private var preview: PreviewTarget?
    @State private var explainedBatch: DeletionSummary?
    @State private var tracker = ScrollTracker()
    @State private var selectTicks = 0
    @State private var bulkSelects = 0
    @State private var deletions = 0

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: DesignTokens.Review.gap)]

    var body: some View {
        ScrollViewReader { proxy in
            list
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if let receipt = model.receipt {
                            ReceiptStrip(receipt: receipt, explain: { explainedBatch = receipt.batch })
                        }
                        DeleteBar(category: category, tracker: tracker, deleteAll: { await delete($0) }) { ids, anchor in
                            let target = restoreTarget(for: anchor)
                            await delete(ids)
                            // The photos above are gone, so everything below moves up. Go back to where the
                            // user was, or the next rows would slide past unseen.
                            await Task.yield()
                            if let target { proxy.scrollTo(target, anchor: .top) }
                        }
                    }
                }
        }
        .sensoryFeedback(.selection, trigger: selectTicks)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: bulkSelects)
        .sensoryFeedback(.success, trigger: deletions)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selectionButtonTitle, action: toggleAll)
                    .disabled(bulkAction == .none)
            }
        }
        .sheet(item: $preview) { PreviewView(id: $0.id) }
        .sheet(item: $explainedBatch) { DeletionSummaryView(summary: $0) }
        .onChange(of: model.receipt) { _, receipt in
            if let receipt { UIAccessibility.post(notification: .announcement, argument: receipt.spokenText) }
        }
        .onDisappear { model.dismissReceipt() }
        .alert(
            "Could not delete",
            isPresented: Binding(get: { model.deletionError != nil }, set: { _ in model.dismissDeletionError() })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.deletionError ?? "")
        }
    }

    /// A cancelled or failed delete leaves the ids selected, so only a real delete counts for the haptic.
    private func delete(_ ids: Set<String>) async {
        await model.delete(ids: ids)
        if model.selection.isDisjoint(with: ids) { deletions += 1 }
    }

    private var list: some View {
        ScrollView {
            if let result = model.result {
                if result.items(in: category).isEmpty {
                    ContentUnavailableView("Nothing here", systemImage: category.symbol)
                        .padding(.top, 80)
                } else {
                    leftOutCaption(result.protectedCountLeftOut(in: category))
                    if category == .similar {
                        similarGroups(sections(of: result))
                    } else {
                        LazyVGrid(columns: columns, spacing: DesignTokens.Review.gap, pinnedViews: [.sectionHeaders]) {
                            ForEach(sections(of: result)) { section in
                                Section {
                                    ForEach(section.items) { cell($0) }
                                } header: {
                                    header(section, pinned: true)
                                } footer: {
                                    if section.title != nil { Color.clear.frame(height: DesignTokens.Review.groupGap) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .coordinateSpace(.named(scrollSpace))
        .onGeometryChange(for: ClosedRange<CGFloat>.self) { proxy in
            proxy.safeAreaInsets.top...max(proxy.safeAreaInsets.top, proxy.size.height - proxy.safeAreaInsets.bottom)
        } action: { tracker.visibleTop = $0.lowerBound; tracker.visibleBottom = $0.upperBound }
    }

    /// A strip per group, so a pair or a trio fills its row. One lazy stack of groups keeps the cells lazy;
    /// only groups of four or more nest a small grid. Headers scroll with the list instead of pinning.
    private func similarGroups(_ sections: [ReviewSection]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(sections) { section in
                Section {
                    groupTiles(section.items)
                    Color.clear.frame(height: DesignTokens.Review.groupGap)
                } header: {
                    header(section, pinned: false).id("anchor-\(section.id)")
                }
            }
        }
    }

    /// Where the list goes back to after "Delete above". A photo inside a similar group's row is not a direct
    /// child of the lazy stack, which can only scroll to its direct children, so the list goes back to that
    /// group's header. Every other list is one grid whose cells are direct children.
    private func restoreTarget(for photoID: String?) -> String? {
        guard let photoID else { return nil }
        guard category == .similar else { return photoID }
        return model.result?.similarGroups.first { $0.items.contains { $0.id == photoID } }.map { "anchor-group-\($0.id)" }
    }

    @ViewBuilder private func groupTiles(_ items: [CleanupItem]) -> some View {
        if items.count == 2 || items.count == 3 {
            HStack(spacing: DesignTokens.Review.gap) {
                ForEach(items) { cell($0, side: DesignTokens.Review.largeTileSide) }
            }
        } else {
            LazyVGrid(columns: columns, spacing: DesignTokens.Review.gap) {
                ForEach(items) { cell($0) }
            }
        }
    }

    @ViewBuilder private func leftOutCaption(_ count: Int) -> some View {
        if count > 0 {
            Text(count == 1
                ? "1 favourite or edited photo was left out. Tap it to select it."
                : "\(count.formatted()) favourites or edited photos were left out. Tap one to select it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    /// The same order `ScanResult.items(in:)` uses, which is what "above" is measured against.
    private func sections(of result: ScanResult) -> [ReviewSection] {
        switch category {
        case .similar:
            result.similarGroups.map { group in
                ReviewSection(
                    id: "group-\(group.id)",
                    title: "\(group.items.count) similar · \(group.reclaimableBytes.formatted(.byteCount(style: .file))) to gain",
                    subtitle: group.reasonLine,
                    items: group.items, bulkSelectableIDs: []
                )
            }
        case .screenshots:
            result.screenshotSections.map { section in
                ReviewSection(
                    id: "kind-\(section.id)",
                    title: "\(section.kind.title) · \(section.items.count.formatted()) · \(section.byteSize.formatted(.byteCount(style: .file)))",
                    items: section.items, bulkSelectableIDs: section.bulkSelectableIDs
                )
            }
        default:
            [ReviewSection(id: "category-\(category.id)", title: nil, items: result.items(in: category), bulkSelectableIDs: [])]
        }
    }

    @ViewBuilder private func header(_ section: ReviewSection, pinned: Bool) -> some View {
        if let title = section.title {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DesignTokens.Review.headerLineSpacing) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                    if let subtitle = section.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !section.bulkSelectableIDs.isEmpty {
                    Button(isFullySelected(section) ? "Deselect" : "Select") { toggle(section) }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("select-\(section.id)")
                }
            }
            .padding(.horizontal, DesignTokens.Review.headerInset)
            .padding(.top, DesignTokens.Review.headerTop)
            .padding(.bottom, DesignTokens.Review.headerBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { if pinned { Rectangle().fill(.bar) } }
            .accessibilityAddTraits(.isHeader)
        }
    }

    private func isFullySelected(_ section: ReviewSection) -> Bool {
        section.bulkSelectableIDs.isSubset(of: model.selection)
    }

    /// Deselecting clears the whole section, including favourites and edited photos picked by hand.
    private func toggle(_ section: ReviewSection) {
        bulkSelects += 1
        if isFullySelected(section) {
            model.deselect(ids: Set(section.items.map(\.id)))
        } else {
            model.select(ids: section.bulkSelectableIDs)
        }
    }

    private func cell(_ item: CleanupItem, side: CGFloat = DesignTokens.Review.tileSide) -> some View {
        Button {
            selectTicks += 1
            model.toggle(item.id)
        } label: {
            PhotoCell(item: item, isSelected: model.selection.contains(item.id), side: side)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cell-\(item.id)")
        .onGeometryChange(for: CellPosition.self) { proxy in
            let frame = proxy.frame(in: .named(scrollSpace))
            if frame.maxY <= tracker.visibleTop { return .above }
            return frame.minY >= tracker.visibleBottom ? .below : .onScreen
        } action: { position in
            tracker.update(item.id, position)
        }
        .onDisappear { tracker.forget(item.id) }
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
        model.result?.bulkSelectableIDs(in: category) ?? []
    }

    private var bulkAction: BulkSelectionAction {
        model.result?.bulkSelectionAction(in: category, selection: model.selection) ?? .none
    }

    private var selectionButtonTitle: String {
        if bulkAction == .deselectAll { return "Deselect all" }
        return category == .similar ? "Select suggested" : "Select all"
    }

    /// Deselecting clears everything in this category, including photos picked by hand.
    private func toggleAll() {
        bulkSelects += 1
        switch bulkAction {
        case .deselectAll: model.deselect(ids: Set(model.result?.items(in: category).map(\.id) ?? []))
        case .select: model.select(ids: selectableIDs)
        case .none: break
        }
    }
}

private struct DeleteBar: View {
    let category: CleanupCategory
    let tracker: ScrollTracker
    let deleteAll: (Set<String>) async -> Void
    /// Deletes the photos, then puts the list back at the photo it is given.
    let deleteAbove: (Set<String>, String?) async -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let ids = model.selectedIDs(in: category)
        let bytes = model.result?.byteSize(of: ids) ?? 0
        let top = model.firstShown(in: category, among: tracker.notScrolledPast)
        let above = top.map { model.selectedIDs(in: category, above: $0, scrolledPast: tracker.scrolledPast) } ?? []
        let hasAbove = !above.isEmpty
        let deleteAllButton = Button {
            Task { await deleteAll(ids) }
        } label: {
            Text(ids.isEmpty
                ? "Select items to delete"
                : "\(hasAbove ? "Delete all" : "Delete") \(ids.count.formatted()) · \(bytes.formatted(.byteCount(style: .file)))")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .disabled(ids.isEmpty)
        return HStack(spacing: 10) {
            if hasAbove {
                Button {
                    Task { await deleteAbove(above, top) }
                } label: {
                    Text("Delete \(above.count.formatted()) above")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("delete-above")
            }
            if hasAbove {
                deleteAllButton.buttonStyle(.bordered)
            } else {
                deleteAllButton.buttonStyle(.borderedProminent)
            }
        }
        .tint(.accentColor)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct ReceiptStrip: View {
    let receipt: DeletionReceipt
    let explain: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.deletedText).font(.subheadline.weight(.semibold))
                    Text("They stay in Recently Deleted for 30 days.")
                    Text(receipt.sessionText)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button("Dismiss", systemImage: "xmark") { model.dismissReceipt() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("receipt-dismiss")
            }
            Button("How to empty Recently Deleted", action: explain)
                .font(.footnote)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receipt-strip")
    }
}

extension DeletionReceipt {
    private static func items(_ count: Int) -> String {
        "\(count.formatted()) \(count == 1 ? "item" : "items")"
    }

    private static func amount(count: Int, bytes: Int64) -> String {
        bytes > 0 ? "\(items(count)), \(bytes.formatted(.byteCount(style: .file)))" : items(count)
    }

    var deletedText: String {
        let kept = batch.keptChanged > 0 ? " \(batch.keptChanged.formatted()) changed after the scan and kept." : ""
        return "Deleted \(Self.amount(count: batch.count, bytes: batch.bytes)).\(kept)"
    }

    var sessionText: String {
        "This session: \(Self.amount(count: total.count, bytes: total.bytes))."
    }

    var spokenText: String {
        "\(deletedText) They stay in Recently Deleted for 30 days. \(sessionText)"
    }
}

private struct PhotoCell: View {
    let item: CleanupItem
    let isSelected: Bool
    let side: CGFloat
    @Environment(AppModel.self) private var model
    @State private var image: CGImage?

    var body: some View {
        Color(.systemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Color(.secondarySystemFill)
                    .overlay {
                        if let image {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .clipped()
                    .scaleEffect(isSelected ? DesignTokens.Mark.selectedPhotoScale : 1)
            }
            .overlay(alignment: .topTrailing) { selectionMark }
            .overlay(alignment: .topLeading) { protectedMark }
            .overlay(alignment: .bottomLeading) { badge }
            .overlay(alignment: .bottomTrailing) { videoLabel }
            .task(id: item.id) { image = await model.thumbnails.image(for: item.id, side: side) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    /// A white ring between a dark disc and a dark keyline: 3:1 or better on any photo. Selected adds the
    /// accent fill and a check, so the two states differ in shape and glyph, not colour alone.
    private var selectionMark: some View {
        let mark = DesignTokens.Mark.self
        return Circle()
            .fill(isSelected ? DesignTokens.accent : mark.disc)
            .frame(width: mark.diameter, height: mark.diameter)
            .overlay { Circle().strokeBorder(mark.ring, lineWidth: mark.ringWidth) }
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(DesignTokens.onAccent)
                }
            }
            .padding(mark.keylineWidth)
            .background { Circle().fill(mark.keyline) }
            .padding(6)
    }

    @ViewBuilder private var protectedMark: some View {
        if item.isProtected {
            HStack(spacing: 3) {
                if item.isFavorite { Image(systemName: "heart.fill") }
                if item.isEdited { Image(systemName: "pencil") }
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(DesignTokens.Pill.text)
            .background(DesignTokens.Pill.scrim, in: Capsule())
            .padding(5)
        }
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
        .foregroundStyle(DesignTokens.Pill.text)
        .background(DesignTokens.Pill.scrim, in: Capsule())
        .padding(5)
    }

    private var accessibilityLabel: String {
        var parts = [item.creationDate.formatted(date: .abbreviated, time: .shortened)]
        if item.isKeeper { parts.append("best shot") }
        if item.isFavorite { parts.append("favourite") }
        if item.isEdited { parts.append("edited") }
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
