import SwiftUI

enum TrackListIdentity: Hashable {
    case database(Int64)
    case path(String)
}

private extension Track {
    var listIdentity: TrackListIdentity {
        trackId.map(TrackListIdentity.database) ?? .path(url.path)
    }
}

/// A headerless, row-based track list: a favorite toggle, artwork, title over a
/// middot-joined artist/album/year line, and duration on the trailing edge.
///
/// The counterpart to `TrackTableView`, for whenever the list sits inside a larger
/// scrolling page: a SwiftUI `Table` is `NSTableView`-backed, so it has no intrinsic height
/// and brings an `NSScrollView` that swallows wheel events.
///
/// **It provides no `ScrollView` of its own.** The caller supplies one. Sorting follows the
/// same `trackTableSortOrder` the table uses, synced through `.trackTableSortChanged`.
struct TrackListView: View {
    let tracks: [Track]
    @Binding var selectedTrackID: TrackListIdentity?
    let playlistID: UUID?
    let entityID: UUID?
    @Binding var sortOrder: [KeyPathComparator<Track>]
    let onPlayTrack: (Track) -> Void
    let onToggleFavorite: (Track, Bool) -> Void
    let contextMenuItems: ([Track], PlaybackManager) -> [ContextMenuItem]

    @EnvironmentObject var playbackManager: PlaybackManager

    @AppStorage("trackTableRowSize")
    private var rowSize: TableRowSize = .expanded

    @State private var sortedTracks: [Track] = []
    @State private var trackFavorites: [Int64: Bool] = [:]
    @State private var isCustomSort = false
    @State private var sortGeneration = 0

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(sortedTracks, id: \.listIdentity) { track in
                let identity = track.listIdentity
                TrackListRow(
                    track: track,
                    rowSize: rowSize,
                    isCurrentTrack: isCurrentTrack(track),
                    isPlaying: isPlaying(track),
                    isSelected: selectedTrackID == identity,
                    isFavorite: isFavorite(track),
                    onSelect: { selectedTrackID = identity },
                    onPlay: { handleDoubleTap(on: track) },
                    onToggleFavorite: { onToggleFavorite(track, isFavorite(track)) }
                )
                .contextMenu {
                    TrackRowContextMenu(track: track, itemsProvider: contextMenuItems)
                }
            }
        }
        .onAppear(perform: initializeSortedTracks)
        .onChange(of: tracks) { _, newTracks in
            guard !newTracks.isEmpty else {
                sortGeneration += 1
                sortedTracks = []
                return
            }
            if isCustomSort {
                sortedTracks = newTracks
            } else {
                performBackgroundSort(with: sortOrder)
            }
            refreshFavorites(from: newTracks)
        }
        .onChange(of: sortOrder) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if isCustomSort { isCustomSort = false }
            performBackgroundSort(with: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackTableSortChanged)) { notification in
            handleSortChangedNotification(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackTableRowSizeChanged)) { notification in
            if let newRowSize = notification.userInfo?["rowSize"] as? TableRowSize {
                rowSize = newRowSize
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackFavoriteStatusChanged)) { notification in
            handleTrackFavoriteStatusChanged(notification)
        }
    }

    // MARK: - State Helpers

    private func isCurrentTrack(_ track: Track) -> Bool {
        guard let currentTrack = playbackManager.currentTrack else { return false }
        if let currentId = currentTrack.trackId, let trackId = track.trackId {
            return currentId == trackId
        }
        return currentTrack.url.path == track.url.path
    }

    private func isPlaying(_ track: Track) -> Bool {
        isCurrentTrack(track) && playbackManager.isPlaying
    }

    private func isFavorite(_ track: Track) -> Bool {
        guard let trackId = track.trackId else { return track.isFavorite }
        return trackFavorites[trackId] ?? track.isFavorite
    }

    // MARK: - Actions

    private func handleDoubleTap(on track: Track) {
        if isCurrentTrack(track) {
            playbackManager.togglePlayPause()
        } else {
            onPlayTrack(track)
        }
    }

    // MARK: - Sorting

    /// Mirrors `TrackTableView.initializeSortedTracks()` so both agree on the saved order.
    private func initializeSortedTracks() {
        refreshFavorites(from: tracks)

        if let playlistID = playlistID,
           PlaylistSortManager.shared.getSortField(for: playlistID) == .custom {
            isCustomSort = true
            sortedTracks = tracks
            return
        }

        // Entities and playlists follow the sort order handed down by their container.
        if entityID != nil || playlistID != nil {
            sortedTracks = tracks.sorted(using: sortOrder)
            return
        }

        if let savedSort = UserDefaults.standard.dictionary(forKey: "trackTableSortOrder"),
           let key = savedSort["key"] as? String,
           let ascending = savedSort["ascending"] as? Bool,
           let field = TrackSortField.from(storageKey: key) {
            let comparator = field.getComparator(ascending: ascending)
            sortOrder = [comparator]
            sortedTracks = tracks.sorted(using: [comparator])
            return
        }

        let defaultComparator = KeyPathComparator(\Track.title, order: .forward)
        sortOrder = [defaultComparator]
        sortedTracks = tracks.sorted(using: [defaultComparator])
    }

    private func performBackgroundSort(with newSortOrder: [KeyPathComparator<Track>]) {
        if isCustomSort {
            sortGeneration += 1
            sortedTracks = tracks
            return
        }

        sortGeneration += 1
        let generation = sortGeneration
        let initialTracks = tracks
        Task.detached(priority: .userInitiated) {
            let sorted = initialTracks.sorted(using: newSortOrder)
            await MainActor.run {
                guard generation == self.sortGeneration else { return }
                self.sortedTracks = sorted
            }
        }
    }

    private func handleSortChangedNotification(_ notification: Notification) {
        if let customSort = notification.userInfo?["isCustomSort"] as? Bool {
            isCustomSort = customSort
            if customSort {
                sortGeneration += 1
                sortedTracks = tracks
                return
            }
        }

        if let newSortOrder = notification.userInfo?["sortOrder"] as? [KeyPathComparator<Track>] {
            sortOrder = newSortOrder
        }
    }

    // MARK: - Favorites

    private func refreshFavorites(from tracks: [Track]) {
        // Uniquing rather than `uniqueKeysWithValues:`, which traps: a playlist can hold
        // the same database track twice.
        let pairs = tracks.compactMap { track -> (Int64, Bool)? in
            guard let trackId = track.trackId else { return nil }
            return (trackId, track.isFavorite)
        }
        trackFavorites = Dictionary(pairs) { first, _ in first }
    }

    private func handleTrackFavoriteStatusChanged(_ notification: Notification) {
        guard let updatedTrack = notification.userInfo?["track"] as? Track,
              let trackId = updatedTrack.trackId else { return }

        trackFavorites[trackId] = updatedTrack.isFavorite

        guard let index = sortedTracks.firstIndex(where: { $0.trackId == trackId }) else { return }

        if TrackSortField.detect(from: sortOrder) == .favorite {
            var updated = sortedTracks
            updated[index].isFavorite = updatedTrack.isFavorite
            sortedTracks = updated.sorted(using: sortOrder)
        } else {
            sortedTracks[index].isFavorite = updatedTrack.isFavorite
        }
    }
}

// MARK: - Skeleton

/// Placeholder rows laid out to `TrackListRow`'s metrics, so real rows land without shift.
struct TrackListSkeleton: View {
    var rowCount: Int = 8

    @AppStorage("trackTableRowSize")
    private var rowSize: TableRowSize = .expanded

    private var isExpanded: Bool { rowSize == .expanded }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                HStack(spacing: 10) {
                    Color.clear.frame(width: 14, height: 14)

                    if isExpanded {
                        SkeletonBlock()
                            .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
                    } else {
                        Color.clear.frame(width: 20, height: 20)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Varied widths so the block doesn't read as a rigid grid.
                        SkeletonBlock(cornerRadius: 3)
                            .frame(width: titleWidth(for: index), height: 10)

                        if isExpanded {
                            SkeletonBlock(cornerRadius: 3)
                                .frame(width: subtitleWidth(for: index), height: 9)
                        }
                    }

                    Spacer(minLength: 12)

                    SkeletonBlock(cornerRadius: 3)
                        .frame(width: 32, height: 9)
                }
                .padding(.horizontal, 14)
                .frame(height: rowSize.rowHeight)
            }
        }
        .accessibilityLabel(String(localized: "Loading"))
    }

    private func titleWidth(for index: Int) -> CGFloat {
        [180, 140, 220, 160, 200].map(CGFloat.init)[index % 5]
    }

    private func subtitleWidth(for index: Int) -> CGFloat {
        [260, 210, 300, 240, 280].map(CGFloat.init)[index % 5]
    }
}

// MARK: - Context Menu

/// Defers `itemsProvider` until the menu is presented: a `View`'s initializer runs
/// eagerly, its `body` does not.
private struct TrackRowContextMenu: View {
    let track: Track
    let itemsProvider: ([Track], PlaybackManager) -> [ContextMenuItem]

    @EnvironmentObject var playbackManager: PlaybackManager

    var body: some View {
        ForEach(itemsProvider([track], playbackManager), id: \.id) { item in
            ContextMenuItemView(item: item)
        }
    }
}

// MARK: - Row

private struct TrackListRow: View {
    let track: Track
    let rowSize: TableRowSize
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void

    /// `Table` selection is emphasized only while the window is key; matching it means
    /// tracking the same signal.
    @Environment(\.controlActiveState)
    private var controlActiveState

    @State private var artworkImage: NSImage?
    @State private var isHovering = false

    private var isExpanded: Bool { rowSize == .expanded }

    private var isEmphasized: Bool { isSelected && controlActiveState == .key }

    var body: some View {
        HStack(spacing: 10) {
            favoriteButton

            if isExpanded {
                artwork
            } else {
                compactPlayControl
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    subtitleText
                }
            } else {
                HStack(spacing: 6) {
                    titleText
                    subtitleText
                }
            }

            Spacer(minLength: 12)

            Text(HelperUtils.formattedDuration(track.duration))
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(height: rowSize.rowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // Simultaneous rather than stacked count:2 / count:1 gestures: those make SwiftUI
        // withhold the single tap for the double-click interval, landing selection late.
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(TapGesture(count: 2).onEnded(onPlay))
    }

    // MARK: - Pieces

    /// Always holds its slot so titles stay aligned. A favorited track shows its star
    /// permanently, an unfavorited one only on hover, which keeps a mostly unfavorited list
    /// quiet while leaving the toggle one click away.
    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? Icons.starFill : Icons.star)
                .font(.system(size: 11))
                .foregroundStyle(isFavorite ? Color.yellow : secondaryTextColor)
                .opacity(isFavorite || isHovering ? 1 : 0)
        }
        .buttonStyle(.plain)
        .frame(width: 14)
        .help(isFavorite
            ? String(localized: "Remove from Favorites")
            : String(localized: "Add to Favorites"))
    }

    private var titleText: some View {
        Text(track.title)
            .font(.system(size: 13, weight: isCurrentTrack ? .bold : .regular))
            .foregroundStyle(primaryTextColor)
            .lineLimit(1)
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.system(size: 11))
            .foregroundStyle(secondaryTextColor)
            .lineLimit(1)
    }

    // Text has to invert on an emphasized row, the way NSTableView does; the accent fill
    // is too dark for the default label colors.
    private var primaryTextColor: Color {
        isEmphasized ? Color(NSColor.alternateSelectedControlTextColor) : .primary
    }

    private var secondaryTextColor: Color {
        isEmphasized ? Color(NSColor.alternateSelectedControlTextColor).opacity(0.75) : .secondary
    }

    /// Artist · Album · Year, dropping missing parts so there's no dangling separator.
    private var subtitle: String {
        [track.artist, track.album, track.year]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var artwork: some View {
        ZStack {
            if let artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
                    .overlay(
                        Image(systemName: Icons.musicNote)
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    )
            }

            // Same trigger as TrackTableView; hover only tints the row background.
            if isCurrentTrack || isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.5))
                    .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)

                Button(action: onPlay) {
                    Image(systemName: playButtonIcon)
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
        .animation(.none, value: isSelected)
        // Attached here rather than to the row: this view only exists while expanded, so
        // switching back to expanded starts the load rather than reusing a stale task.
        .task(id: track.trackId) {
            await loadArtwork()
        }
    }

    private var compactPlayControl: some View {
        ZStack {
            // Reserves the glyph's width so titles stay aligned when no control shows.
            Image(systemName: Icons.playFill)
                .font(.system(size: 14))
                .foregroundColor(.clear)
                .frame(width: 20, height: 20)

            if isSelected || isCurrentTrack {
                Button(action: onPlay) {
                    Image(systemName: playButtonIcon)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.none, value: isSelected)
    }

    private var playButtonIcon: String {
        isCurrentTrack && isPlaying ? Icons.pauseFill : Icons.playFill
    }

    /// Matches the native `Table` selection: the emphasized accent fill while the window
    /// is key, the grey unemphasized fill otherwise. No hover state, also matching.
    @ViewBuilder private var rowBackground: some View {
        if isSelected {
            Color(nsColor: isEmphasized ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor)
        } else {
            Color.clear
        }
    }

    private func loadArtwork() async {
        // Synchronous cache hit first, so recycled rows don't flash a placeholder.
        if let cached = TrackArtworkCache.shared.getCachedImage(for: track) {
            artworkImage = cached
            return
        }

        let image = await TrackArtworkCache.shared.loadImage(for: track)

        guard !Task.isCancelled else { return }
        artworkImage = image
    }
}
