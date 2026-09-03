import Combine
import SwiftUI

private struct DiscoverInitialScanBanner: View {
    @ObservedObject var libraryManager: LibraryManager

    var body: some View {
        if libraryManager.isInitialOnboardingScan,
           libraryManager.hasReachedInitialScanThreshold,
           libraryManager.isScanning {
            HStack(spacing: 12) {
                ActivityAnimation(size: .small)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Discover will populate when scanning finishes")
                        .font(.system(size: 13, weight: .semibold))

                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.accentColor.opacity(0.08))
        }
    }

    private var statusText: String {
        libraryManager.scanStatusMessage.isEmpty
            ? String(localized: "Discover will finish loading when the scan completes.")
            : libraryManager.scanStatusMessage
    }
}

private final class DiscoverViewModel: ObservableObject {
    @Published private(set) var featuredSection: DiscoverSection
    @Published private(set) var recentlyPlayedSection: DiscoverSection
    @Published private(set) var mostLovedSection: DiscoverSection
    @Published private(set) var tracks: [Track]
    @Published private(set) var isLoadingTracks: Bool
    @Published private(set) var showsRecentlyPlayed: Bool
    @Published private(set) var showsMostLoved: Bool

    init(libraryManager: LibraryManager) {
        featuredSection = libraryManager.featuredSection
        recentlyPlayedSection = libraryManager.recentlyPlayedSection
        mostLovedSection = libraryManager.mostLovedSection
        tracks = libraryManager.discoverTracks
        isLoadingTracks = libraryManager.isLoadingDiscoverTracks
        showsRecentlyPlayed = libraryManager.isDiscoverRecentlyPlayedUnlocked
        showsMostLoved = libraryManager.isDiscoverMostLovedUnlocked

        libraryManager.$featuredSection.assign(to: &$featuredSection)
        libraryManager.$recentlyPlayedSection.assign(to: &$recentlyPlayedSection)
        libraryManager.$mostLovedSection.assign(to: &$mostLovedSection)
        libraryManager.$discoverTracks.assign(to: &$tracks)
        libraryManager.$isLoadingDiscoverTracks.assign(to: &$isLoadingTracks)
        libraryManager.$isDiscoverRecentlyPlayedUnlocked.assign(to: &$showsRecentlyPlayed)
        libraryManager.$isDiscoverMostLovedUnlocked.assign(to: &$showsMostLoved)
    }
}

/// The Discover screen: three horizontally scrolling entity rows above the Fresh Music
/// track list, composed as one vertically scrolling page with pinned section headers.
///
/// Fresh Music uses `TrackListView` rather than `TrackTableView`; see its doc for why a
/// `Table` can't participate in this layout.
struct DiscoverView: View {
    private let libraryManager: LibraryManager
    private let playlistManager: PlaylistManager

    /// Whether Discover is on screen; `HomeView` is never torn down on tab switches.
    let isVisible: Bool

    /// Raised to `HomeView`, which owns the detail overlay.
    let onSelectDetail: (HomeDetailTarget) -> Void

    @StateObject private var viewModel: DiscoverViewModel

    @AppStorage("trackTableRowSize")
    private var trackTableRowSize: TableRowSize = .expanded

    @State private var selectedTrackID: TrackListIdentity?
    @State private var trackTableSortOrder = [KeyPathComparator(\Track.title)]
    @State private var metrics: EntityListMetrics = .regular
    @State private var recentlyPlayedIsStale = false

    init(
        libraryManager: LibraryManager,
        playlistManager: PlaylistManager,
        isVisible: Bool,
        onSelectDetail: @escaping (HomeDetailTarget) -> Void
    ) {
        self.libraryManager = libraryManager
        self.playlistManager = playlistManager
        self.isVisible = isVisible
        self.onSelectDetail = onSelectDetail
        _viewModel = StateObject(wrappedValue: DiscoverViewModel(libraryManager: libraryManager))
    }

    // MARK: - Layout

    private enum Layout {
        /// Sized against two carousels plus the third's header, not all three and a slice
        /// of Fresh Music: requiring everything visible at rest would force the smallest
        /// tiles at the default window size. The page scrolls and every header pins.
        static func metrics(forAvailableHeight height: CGFloat) -> EntityListMetrics {
            func fits(_ candidate: EntityListMetrics) -> Bool {
                candidate.totalHeight * 2 + candidate.headerHeight <= height
            }

            if fits(.regular) { return .regular }
            if fits(.compact) { return .compact }
            return .mini
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DiscoverInitialScanBanner(libraryManager: libraryManager)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        featuredRow
                    } header: {
                        EntityListHeader(title: String(localized: "Featured"), metrics: metrics) {
                            refreshButton(help: String(localized: "Refresh featured picks")) {
                                Task { await libraryManager.refreshFeatured() }
                            }
                        }
                    }

                    if viewModel.showsRecentlyPlayed {
                        Section {
                            recentlyPlayedRow
                        } header: {
                            EntityListHeader(title: String(localized: "Recently Played"), metrics: metrics)
                        }
                    }

                    if viewModel.showsMostLoved {
                        Section {
                            mostLovedRow
                        } header: {
                            EntityListHeader(title: String(localized: "Most Loved & Played"), metrics: metrics)
                        }
                    }

                    Section {
                        freshMusicContent
                    } header: {
                        freshMusicHeader
                    }
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { updateMetrics(forAvailableHeight: geometry.size.height) }
                        .onChange(of: geometry.size.height) { _, newHeight in
                            updateMetrics(forAvailableHeight: newHeight)
                        }
                }
            }
        }
        .task {
            await libraryManager.loadDiscover()
        }
        // Refreshing on screen would reshuffle tiles under the user, so mark it stale and
        // settle when Discover next becomes visible. Most Loved & Played tracks its own
        // staleness in `LibraryManager`, since plays land whether or not Discover is open.
        .onReceive(NotificationCenter.default.publisher(for: .trackPlayCountUpdated)) { _ in
            if isVisible {
                recentlyPlayedIsStale = false
                Task { await libraryManager.loadDiscover() }
            } else {
                recentlyPlayedIsStale = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackFavoriteStatusChanged)) { _ in
            guard isVisible else { return }
            Task { await libraryManager.loadDiscover() }
        }
        // Generation is skipped while a scan is running, so pick it up once the scan ends.
        .onReceive(libraryManager.$isScanning.removeDuplicates().dropFirst()) { scanning in
            guard !scanning else { return }
            Task { await libraryManager.loadDiscover() }
        }
        .onChange(of: isVisible) { _, nowVisible in
            guard nowVisible else { return }
            // A loved reselection is a full load, which recomputes Recently Played anyway.
            if libraryManager.discoverLovedNeedsRefresh {
                recentlyPlayedIsStale = false
                Task { await libraryManager.loadDiscover() }
            } else if recentlyPlayedIsStale {
                recentlyPlayedIsStale = false
                Task { await libraryManager.reloadDiscoverRecentlyPlayed() }
            }
        }
    }

    // MARK: - Carousels

    private var featuredRow: some View {
        EntityListRow(
            entities: viewModel.featuredSection.entities,
            state: listState(
                for: viewModel.featuredSection,
                emptyMessage: String(localized: "Add more music to see featured picks")
            ),
            metrics: metrics,
            onSelectEntity: select,
            contextMenuItems: contextMenuItems
        )
    }

    private var recentlyPlayedRow: some View {
        EntityListRow(
            entities: viewModel.recentlyPlayedSection.entities,
            state: listState(
                for: viewModel.recentlyPlayedSection,
                emptyMessage: String(localized: "Play something to see it here")
            ),
            metrics: metrics,
            onSelectEntity: select,
            contextMenuItems: contextMenuItems
        )
    }

    private var mostLovedRow: some View {
        EntityListRow(
            entities: viewModel.mostLovedSection.entities,
            state: listState(
                for: viewModel.mostLovedSection,
                emptyMessage: String(localized: "Play or favourite some music to see it here")
            ),
            metrics: metrics,
            onSelectEntity: select,
            contextMenuItems: contextMenuItems
        )
    }

    private func listState(for section: DiscoverSection, emptyMessage: String) -> EntityListState {
        if section.isLoading { return .loading }
        return section.entities.isEmpty ? .empty(message: emptyMessage) : .loaded
    }

    private func updateMetrics(forAvailableHeight height: CGFloat) {
        let newMetrics = Layout.metrics(forAvailableHeight: height)
        guard newMetrics != metrics else { return }
        metrics = newMetrics
    }

    // MARK: - Fresh Music

    /// Pinned by the enclosing `Section`. No divider: `TrackListHeader`'s opaque fill
    /// already covers rows scrolling under it.
    private var freshMusicHeader: some View {
        TrackListHeader(
            title: String(localized: "Fresh Music"),
            sortOrder: $trackTableSortOrder,
            tableRowSize: $trackTableRowSize
        ) {
            refreshButton(help: String(localized: "Refresh fresh music")) {
                Task { await libraryManager.refreshFreshMusic() }
            }
        }
    }

    @ViewBuilder private var freshMusicContent: some View {
        if viewModel.isLoadingTracks {
            TrackListSkeleton()
        } else if viewModel.tracks.isEmpty {
            freshMusicEmptyState
        } else {
            TrackListView(
                tracks: viewModel.tracks,
                selectedTrackID: $selectedTrackID,
                playlistID: nil,
                entityID: nil,
                sortOrder: $trackTableSortOrder,
                onPlayTrack: { track, displayedTracks in
                    playlistManager.playTrack(track, fromTracks: displayedTracks)
                    playlistManager.currentQueueSource = .library
                },
                onToggleFavorite: { track, currentState in
                    playlistManager.toggleFavorite(for: track, currentState: currentState)
                },
                contextMenuItems: { tracks, _ in
                    guard let track = tracks.first else { return [] }
                    return TrackContextMenu.createMenuItems(
                        for: track,
                        playlistManager: playlistManager,
                        currentContext: .library
                    )
                }
            )
        }
    }

    /// Needs an explicit height; nothing stretches it inside a scrolling page.
    private var freshMusicEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: Icons.sparkles)
                .font(.system(size: 32))
                .foregroundColor(.gray)

            Text("No undiscovered tracks")
                .font(.headline)

            Text("You've played all tracks in your library!")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .padding()
    }

    // MARK: - Actions

    private func select(_ entity: any Entity) {
        if let playlistEntity = entity as? PlaylistEntity {
            onSelectDetail(.playlist(playlistEntity.id))
        } else {
            onSelectDetail(.entity(entity))
        }
    }

    private func contextMenuItems(for entity: any Entity) -> [ContextMenuItem] {
        if let playlistEntity = entity as? PlaylistEntity {
            guard let playlist = playlistManager.playlists.first(where: { $0.id == playlistEntity.id }) else {
                return []
            }
            return [playlistManager.createPinContextMenuItem(for: playlist)]
        }
        return libraryManager.contextMenuItems(for: entity)
    }

    private func refreshButton(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .hoverEffect(scale: 1.1)
        .help(help)
    }
}
