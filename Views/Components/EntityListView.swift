import SwiftUI

// MARK: - State

enum EntityListState {
    case loading
    case loaded
    case empty(message: String)
}

// MARK: - Metrics

/// Every dimension is a constant so `totalHeight` is exact, which is what lets a parent
/// size a row without a GeometryReader feedback loop.
struct EntityListMetrics {
    let artworkSize: CGFloat
    let tilePadding: CGFloat
    let artworkLabelSpacing: CGFloat
    /// Fixed, so tile height stays deterministic regardless of label content.
    let labelHeight: CGFloat
    let showsSubtitleLine: Bool
    let itemSpacing: CGFloat
    let headerHeight: CGFloat
    let contentVerticalPadding: CGFloat

    var tileWidth: CGFloat { artworkSize + tilePadding * 2 }

    var tileHeight: CGFloat {
        tilePadding * 2 + artworkSize + artworkLabelSpacing + labelHeight
    }

    /// Exact height of the scrolling row on its own.
    var contentHeight: CGFloat {
        contentVerticalPadding * 2 + tileHeight
    }

    /// Exact height a section occupies, header included.
    var totalHeight: CGFloat {
        headerHeight + contentHeight
    }

    // Artwork sizes must stay <= ViewDefaults.gridArtworkSize; see carouselArtworkSize.

    static let regular = EntityListMetrics(
        artworkSize: ViewDefaults.carouselArtworkSize,
        tilePadding: 8,
        artworkLabelSpacing: 6,
        labelHeight: 32,
        showsSubtitleLine: true,
        itemSpacing: 12,
        headerHeight: 32,
        contentVerticalPadding: 8
    )

    static let compact = EntityListMetrics(
        artworkSize: 120,
        tilePadding: 6,
        artworkLabelSpacing: 5,
        labelHeight: 32,
        showsSubtitleLine: true,
        itemSpacing: 10,
        headerHeight: 28,
        contentVerticalPadding: 6
    )

    /// Drops the subtitle to a single line; the kind label survives in the tooltip
    /// and the accessibility label.
    static let mini = EntityListMetrics(
        artworkSize: 90,
        tilePadding: 6,
        artworkLabelSpacing: 4,
        labelHeight: 18,
        showsSubtitleLine: false,
        itemSpacing: 8,
        headerHeight: 26,
        contentVerticalPadding: 4
    )
}

// MARK: - Section Header

/// Separate from `EntityListRow` so callers can hand it to a `Section`'s header slot and
/// have `LazyVStack(pinnedViews:)` pin it. The fill has to be opaque, since tiles scroll
/// under it once pinned, but matching the page background keeps it invisible at rest.
struct EntityListHeader<Accessory: View>: View {
    let title: String
    let metrics: EntityListMetrics
    @ViewBuilder let accessory: () -> Accessory

    init(
        title: String,
        metrics: EntityListMetrics = .regular,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.metrics = metrics
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            accessory()
        }
        .padding(.horizontal, 14)
        .frame(height: metrics.headerHeight)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Entity List Row

/// A horizontally scrolling row of heterogeneous entities. Separate from `EntityGridView`
/// rather than a mode on it: the grid is generic over one concrete `Entity` type, and
/// folding them would push existentials onto the Artists/Albums screens.
struct EntityListRow: View {
    /// Callers cap this; the view does not truncate.
    let entities: [any Entity]
    let state: EntityListState
    let metrics: EntityListMetrics
    let onSelectEntity: (any Entity) -> Void
    let contextMenuItems: (any Entity) -> [ContextMenuItem]

    init(
        entities: [any Entity],
        state: EntityListState = .loaded,
        metrics: EntityListMetrics = .regular,
        onSelectEntity: @escaping (any Entity) -> Void,
        contextMenuItems: @escaping (any Entity) -> [ContextMenuItem] = { _ in [] }
    ) {
        self.entities = entities
        self.state = state
        self.metrics = metrics
        self.onSelectEntity = onSelectEntity
        self.contextMenuItems = contextMenuItems
        // Built once: as a computed property this reallocated on each of the five accesses
        // per body pass.
        self.items = entities.map { Item(id: $0.id, entity: $0) }
    }

    @State private var isHoveringRow = false
    @State private var rowWidth: CGFloat = 0
    @State private var scrollAnchorID: UUID?

    /// `ForEach` over `[any Entity]` with `id: \.id` needs a key path rooted in an
    /// existential. Wrapping sidesteps that and gives stable identity across refreshes.
    private struct Item: Identifiable {
        let id: UUID
        let entity: any Entity
    }

    private let items: [Item]

    var body: some View {
        content
            .frame(height: metrics.contentHeight)
            .onHover { isHoveringRow = $0 }
            .accessibilityElement(children: .contain)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            skeletonRow
        case .empty(let message):
            emptyRow(message)
        case .loaded where entities.isEmpty:
            emptyRow(String(localized: "Nothing here yet"))
        case .loaded:
            carousel
        }
    }

    private var carousel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: metrics.itemSpacing) {
                    ForEach(items) { item in
                        EntityListItem(entity: item.entity, metrics: metrics) {
                            onSelectEntity(item.entity)
                        }
                        .id(item.id)
                        .contextMenu {
                            ForEach(contextMenuItems(item.entity), id: \.id) { menuItem in
                                ContextMenuItemView(item: menuItem)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)  // matches EntityGridView's gutter
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrollAnchorID, anchor: .leading)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { rowWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, newWidth in rowWidth = newWidth }
                }
            }
            .focusable()
            // Keyboard paging still works; the ring reads as a stuck selection.
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .left: page(by: -1, using: proxy)
                case .right: page(by: 1, using: proxy)
                default: break
                }
            }
            .padding(.vertical, metrics.contentVerticalPadding)
            .overlay(alignment: .leading) { edgeButton(isLeading: true, proxy: proxy) }
            .overlay(alignment: .trailing) { edgeButton(isLeading: false, proxy: proxy) }
        }
    }

    // No `.scrollTargetBehavior(.viewAligned)`: on AppKit it rubber-bands trackpad flicks
    // and jumps a whole tile per wheel detent. `.scrollTargetLayout()` is still required,
    // since `.scrollPosition(id:)` reads it. No `.scrollClipDisabled()` either, or tile
    // shadows bleed over the header.

    private func edgeButton(isLeading: Bool, proxy: ScrollViewProxy) -> some View {
        let enabled = isLeading ? !isAtStart : !isAtEnd

        return Button {
            page(by: isLeading ? -1 : 1, using: proxy)
        } label: {
            Image(systemName: isLeading ? Icons.chevronLeft : Icons.chevronRight)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .opacity(isHoveringRow && enabled ? 1 : 0)
        .allowsHitTesting(isHoveringRow && enabled)
        .animation(.easeInOut(duration: AnimationDuration.standardDuration), value: isHoveringRow)
        .accessibilityLabel(isLeading ? String(localized: "Scroll left") : String(localized: "Scroll right"))
        .accessibilityHidden(!enabled)
    }

    private var tileStride: CGFloat { metrics.tileWidth + metrics.itemSpacing }

    private var currentIndex: Int {
        guard let scrollAnchorID,
              let index = items.firstIndex(where: { $0.id == scrollAnchorID }) else { return 0 }
        return index
    }

    /// Arithmetic rather than measured: a preference key reads 0 until the first layout
    /// pass, and a zero content width makes both edges test true, hiding both chevrons.
    private var contentWidth: CGFloat {
        guard !items.isEmpty else { return 0 }
        return CGFloat(items.count) * metrics.tileWidth
            + CGFloat(items.count - 1) * metrics.itemSpacing
            + 28  // horizontal gutter
    }

    private var maxOffset: CGFloat { max(0, contentWidth - rowWidth) }

    private var isAtStart: Bool { currentIndex <= 0 }

    /// The index the anchor reports once the row is scrolled as far as it goes. NOT
    /// `count - visibleTileCount`: at maximum scroll the leading edge lands partway through
    /// a tile and `.scrollPosition(id:)` reports the tile containing it, one index lower.
    private var lastLeadingIndex: Int {
        guard tileStride > 0 else { return 0 }
        return max(0, Int(maxOffset / tileStride))
    }

    private var isAtEnd: Bool { currentIndex >= lastLeadingIndex }

    private var visibleTileCount: Int {
        guard rowWidth > 0 else { return 1 }
        let usable = rowWidth - 28  // horizontal gutter
        return max(1, Int(usable / tileStride))
    }

    private func page(by direction: Int, using proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }
        let step = max(1, visibleTileCount)
        let target = min(max(0, currentIndex + direction * step), items.count - 1)
        withAnimation(.easeInOut(duration: AnimationDuration.standardDuration)) {
            proxy.scrollTo(items[target].id, anchor: .leading)
        }
    }

    // MARK: - Placeholder States

    /// Mirrors the real tile's metrics so nothing shifts when content lands, in the same
    /// disabled `ScrollView` rather than a bare `HStack`: the row is wider than the
    /// viewport, and an oversized child of a plain `.frame(height:)` gets centred.
    private var skeletonRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: metrics.itemSpacing) {
                ForEach(0..<8, id: \.self) { _ in
                    VStack(spacing: metrics.artworkLabelSpacing) {
                        SkeletonBlock(cornerRadius: 8)
                            .frame(width: metrics.artworkSize, height: metrics.artworkSize)

                        VStack(alignment: .leading, spacing: 5) {
                            SkeletonBlock(cornerRadius: 3)
                                .frame(width: metrics.artworkSize * 0.75, height: 9)

                            if metrics.showsSubtitleLine {
                                SkeletonBlock(cornerRadius: 3)
                                    .frame(width: metrics.artworkSize * 0.45, height: 8)
                            }
                        }
                        .frame(width: metrics.artworkSize, height: metrics.labelHeight, alignment: .topLeading)
                    }
                    .padding(metrics.tilePadding)
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
        .padding(.vertical, metrics.contentVerticalPadding)
        .accessibilityLabel(String(localized: "Loading"))
    }

    private func emptyRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: Icons.sparkles)
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: metrics.tileHeight)
        .padding(.vertical, metrics.contentVerticalPadding)
    }
}

// MARK: - Tile

/// Carousel-specific rather than a promoted `EntityGridItem`: that tile's label block is a
/// variable-height 1-3 line stack, fatal for a fixed-height row.
private struct EntityListItem: View {
    let entity: any Entity
    let metrics: EntityListMetrics
    let onSelect: () -> Void

    /// Row-local: hover held by the parent re-renders every visible tile on each crossing.
    @State private var isHovered = false

    @State private var renderedImage: NSImage?

    var body: some View {
        // Button, not onTapGesture: VoiceOver traits, keyboard activation, and
        // scroll-to-focused-child under Full Keyboard Access.
        Button(action: onSelect) {
            VStack(spacing: metrics.artworkLabelSpacing) {
                artwork
                labels
            }
            .padding(metrics.tilePadding)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
                    .animation(.easeInOut(duration: 0.08), value: isHovered)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Without this the tile stays ringed behind the detail view its own tap opened.
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(String(localized: "Opens details"))
    }

    private var artwork: some View {
        Group {
            if let renderedImage {
                Image(nsImage: renderedImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(placeholderGlyph)
            }
        }
        .frame(width: metrics.artworkSize, height: metrics.artworkSize)
        // Softer than the grid's radius-10/y-5: the row clips at its vertical bounds.
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        .task(id: entity.artworkIdentity) {
            await loadArtwork()
        }
    }

    @ViewBuilder private var placeholderGlyph: some View {
        if entity is ArtistEntity {
            Text(entity.name.artistInitials)
                .font(.system(size: metrics.artworkSize * 0.25, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: Icons.entityIcon(for: entity))
                .font(.system(size: metrics.artworkSize * 0.3))
                .foregroundStyle(.secondary)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entity.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if metrics.showsSubtitleLine {
                Text(secondaryLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: metrics.artworkSize, height: metrics.labelHeight, alignment: .topLeading)
        .help(accessibilityLabel)
    }

    /// A mixed row needs the kind visible, not just a track count. Albums show their
    /// artist instead, since square art already says "album".
    private var secondaryLine: String {
        if let album = entity as? AlbumEntity, let artistName = album.artistName, !artistName.isEmpty {
            return artistName
        }
        return entity.kindLabel
    }

    private var accessibilityLabel: String {
        let kind = entity.kindLabel
        return kind.isEmpty ? entity.displayName : "\(entity.displayName), \(kind)"
    }

    private func loadArtwork() async {
        // Synchronous cache hit first, so recycled tiles don't flash a placeholder.
        if let cached = EntityArtworkCache.shared.getCachedImage(for: entity) {
            renderedImage = cached
            return
        }

        let image = await EntityArtworkCache.shared.loadImage(for: entity)

        guard !Task.isCancelled else { return }
        renderedImage = image
    }
}
