import SwiftUI

enum AlbumSortOption: String, Codable {
    case album
    case artist
    case year
    case dateAdded
}

/// What the Home detail overlay is showing: any entity, or a playlist.
enum HomeDetailTarget: Identifiable, Equatable {
    case entity(any Entity)
    case playlist(UUID)

    var id: UUID {
        switch self {
        case .entity(let entity): return entity.id
        case .playlist(let playlistID): return playlistID
        }
    }

    // `any Entity` isn't Equatable; identity is (case, id), which suffices because
    // entity ids are deterministic and namespaced.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.entity(left), .entity(right)): return left.id == right.id
        case let (.playlist(left), .playlist(right)): return left == right
        default: return false
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager
    
    @AppStorage("trackTableRowSize")
    private var trackTableRowSize: TableRowSize = .expanded
    
    @Binding var selectedSidebarItem: HomeSidebarItem?
    @State private var selectedTrackID: UUID?
    @State private var pinnedItemTracks: [Track] = []
    @State private var pinnedEntity: (any Entity)?
    @State private var homeDetail: HomeDetailTarget?
    /// Carries the role behind an album-artist or composer tile into its detail view.
    @State private var detailRoleCarrier: PinnedItem?
    @State private var trackTableSortOrder = [KeyPathComparator(\Track.title)]
    /// True while Home is the selected tab. HomeView is never torn down on tab switches,
    /// so this is the only signal its children have that they became visible again.
    var isActiveTab: Bool = true
    
    var body: some View {
        ZStack {
                // Base content (always rendered)
                VStack(spacing: 0) {
                    if let selectedItem = selectedSidebarItem {
                        switch selectedItem.source {
                        case .fixed(let type):
                            switch type {
                            case .discover:
                                discoverView
                            case .tracks:
                                tracksView
                            case .internetRadio:
                                InternetRadioView()
                            }
                        case .pinned(let pinnedItem):
                            if pinnedItem.itemType == .category, let filterType = pinnedItem.filterType {
                                EntityTypeView(filterType: filterType) { entity, roleCarrier in
                                    detailRoleCarrier = roleCarrier
                                    homeDetail = .entity(entity)
                                }
                                .id(selectedSidebarItem?.id)
                            } else {
                                pinnedItemTracksView
                                    .id(selectedSidebarItem?.id)
                            }
                        }
                    } else {
                        emptySelectionView
                    }
                }
                .navigationTitle(selectedSidebarItem?.title ?? String(localized: "Home"))
                .navigationSubtitle("")

                // Detail overlay: any entity, or a playlist tile from Discover.
                if let detail = homeDetail {
                    detailOverlay(for: detail)
                        // Fresh view per target: EntityDetailView reloads on
                        // `.onChange(of: entity.id)` but never resets its artwork-override,
                        // bio or selection state.
                        .id(detail.id)
                        .zIndex(1)
                }
        }
        .onChange(of: selectedSidebarItem) { _, newItem in
                homeDetail = nil
                detailRoleCarrier = nil
                pinnedEntity = nil

                if case .pinned(let pinnedItem)? = newItem?.source {
                    loadTracksForPinnedItem(pinnedItem)
                }
        }
        .onChange(of: homeDetail) {
                if homeDetail == nil {
                    detailRoleCarrier = nil
                }
        }
    }

    // MARK: - Discover View

    private var discoverView: some View {
        // Only built when Discover is the selected sidebar item, so visibility reduces
        // to whether Home is the active tab.
        DiscoverView(
            libraryManager: libraryManager,
            playlistManager: playlistManager,
            isVisible: isActiveTab
        ) { target in
            detailRoleCarrier = nil
            homeDetail = target
        }
    }

    // MARK: - Detail Overlay

    @ViewBuilder
    private func detailOverlay(for detail: HomeDetailTarget) -> some View {
        switch detail {
        case .entity(let entity):
            EntityDetailView(
                entity: entity,
                onBack: { homeDetail = nil },
                pinnedItem: detailRoleCarrier
            )
        case .playlist(let playlistID):
            PlaylistDetailView(playlistID: playlistID) { homeDetail = nil }
        }
    }
    
    // MARK: - Tracks View
    
    private var tracksView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            TrackListHeader(
                title: String(localized: "All tracks"),
                sortOrder: $trackTableSortOrder,
                tableRowSize: $trackTableRowSize
            )
            
            Divider()
            
            // Show loading or tracks
            if libraryManager.tracks.isEmpty {
                ActivityAnimation(size: .large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        Task {
                            await libraryManager.loadAllTracks()
                        }
                    }
            } else {
                TrackView(
                    tracks: libraryManager.tracks,
                    selectedTrackID: $selectedTrackID,
                    playlistID: nil,
                    entityID: nil,
                    sortOrder: $trackTableSortOrder,
                    onPlayTrack: { track in
                        playlistManager.playTrack(track, fromTracks: libraryManager.tracks)
                        playlistManager.currentQueueSource = .library
                    },
                    contextMenuItems: { track, _ in
                        TrackContextMenu.createMenuItems(
                            for: track,
                            playlistManager: playlistManager,
                            currentContext: .library
                        )
                    }
                )
            }
        }
    }

    // MARK: - Pinned Item Tracks View
    
    private var pinnedItemTracksView: some View {
        VStack(spacing: 0) {
            if let selectedItem = selectedSidebarItem,
               case .pinned(let pinnedItem) = selectedItem.source {
                if pinnedItem.itemType == .playlist,
                   let playlistId = pinnedItem.playlistId,
                   let playlist = playlistManager.playlists.first(where: { $0.id == playlistId }) {
                    PlaylistDetailView(playlist: playlist)
                } else if let entity = pinnedEntity {
                    EntityDetailView(entity: entity, pinnedItem: pinnedItem)
                } else if (pinnedItem.filterType == .artists || pinnedItem.filterType == .albums)
                            && !libraryManager.entitiesLoaded {
                    ActivityAnimation(size: .large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    NoMusicEmptyStateView(context: .localLibrary)
                }
            } else {
                NoMusicEmptyStateView(context: .localLibrary)
            }
        }
    }

    private func buildArtistEntityForPerson(name: String) -> ArtistEntity {
        let data = libraryManager.databaseManager.getArtistArtworkAndBio(for: name)
        let trackCount = pinnedItemTracks.count
        return ArtistEntity(name: name, trackCount: trackCount, artworkData: data.artworkData)
    }
    
    // MARK: - Helpers
    
    private var emptySelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: Icons.musicNoteHouse)
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("Select an item from the sidebar")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    
    private func loadTracksForPinnedItem(_ item: PinnedItem) {
        // Category pins render a grid of entities; `EntityTypeView` owns their loading.
        guard item.itemType != .category else {
            pinnedItemTracks = []
            pinnedEntity = nil
            return
        }

        let tracks = item.itemType == .playlist
            ? playlistManager.getTracksForPinnedPlaylist(item)
            : libraryManager.getTracksForPinnedItem(item)

        pinnedItemTracks = tracks

        // Folders are identified by path (filterType is nil); build a FolderEntity directly.
        if item.itemType == .folder {
            pinnedEntity = FolderEntity(
                path: item.filterValue ?? "",
                name: item.displayName,
                trackCount: tracks.count
            )
            return
        }

        // Build the entity for all library pinned types
        if let filterType = item.filterType, let filterValue = item.filterValue {
            switch filterType {
            case .artists:
                loadPinnedArtistOrAlbumEntity(item, filterType: filterType, filterValue: filterValue)
            case .albums:
                loadPinnedArtistOrAlbumEntity(item, filterType: filterType, filterValue: filterValue)
            case .albumArtists, .composers:
                pinnedEntity = buildArtistEntityForPerson(name: filterValue)
            case .genres, .decades, .years:
                pinnedEntity = CategoryEntity(name: filterValue, trackCount: tracks.count, filterType: filterType)
            }
        } else {
            pinnedEntity = nil
        }
    }

    private func loadPinnedArtistOrAlbumEntity(
        _ item: PinnedItem,
        filterType: LibraryFilterType,
        filterValue: String
    ) {
        pinnedEntity = nil
        let pinnedId = item.id
        Task {
            await libraryManager.loadEntitiesAsync()
            guard case .pinned(let selected)? = selectedSidebarItem?.source,
                  selected.id == pinnedId else { return }

            switch filterType {
            case .artists:
                pinnedEntity = libraryManager.cachedArtistEntities.first { $0.name == filterValue }
            case .albums:
                // Match the exact album by id (titles aren't unique); legacy nil falls back to title.
                if let albumId = item.albumId {
                    pinnedEntity = libraryManager.cachedAlbumEntities.first { $0.albumId == albumId }
                        ?? libraryManager.cachedAlbumEntities.first { $0.name == filterValue }
                } else {
                    pinnedEntity = libraryManager.cachedAlbumEntities.first { $0.name == filterValue }
                }
            default:
                break
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedSidebarItem: HomeSidebarItem?

    HomeView(selectedSidebarItem: $selectedSidebarItem)
        .environmentObject(LibraryManager())
        .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
        .environmentObject(PlaylistManager())
        .frame(width: 800, height: 600)
}
