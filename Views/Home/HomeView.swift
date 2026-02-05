import SwiftUI

enum AlbumSortOption: String, Codable {
    case album
    case artist
    case year
    case dateAdded
}

struct HomeView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    
    @AppStorage("entitySortAscending")
    private var entitySortAscending: Bool = true

    @AppStorage("albumSortBy")
    private var albumSortBy: AlbumSortOption = .album
    
    @AppStorage("trackTableRowSize")
    private var trackTableRowSize: TableRowSize = .expanded
    
    @State private var selectedSidebarItem: HomeSidebarItem?
    @State private var selectedTrackID: UUID?
    @State private var pinnedItemTracks: [Track] = []
    @State private var sortedArtistEntities: [ArtistEntity] = []
    @State private var sortedAlbumEntities: [AlbumEntity] = []
    @State private var lastArtistCount: Int = 0
    @State private var lastAlbumCount: Int = 0
    @State private var selectedArtistEntity: ArtistEntity?
    @State private var selectedAlbumEntity: AlbumEntity?
    @State private var isShowingEntityDetail = false
    @State private var trackTableSortOrder = [KeyPathComparator(\Track.title)]
    @Binding var isShowingEntities: Bool
    
    var body: some View {
        if libraryManager.folders.isEmpty {
            NoMusicEmptyStateView(context: .mainWindow)
        } else {
            PersistentSplitView(
                left: {
                    HomeSidebarView(selectedItem: $selectedSidebarItem)
                },
                main: {
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
                                    case .artists:
                                        artistsView
                                    case .albums:
                                        albumsView
                                    }
                                case .pinned:
                                    pinnedItemTracksView
                                        .id(selectedSidebarItem?.id)
                                }
                            } else {
                                emptySelectionView
                            }
                        }
                        .navigationTitle(selectedSidebarItem?.title ?? "Home")
                        .navigationSubtitle("")
                        
                        // Entity detail overlay
                        if isShowingEntityDetail {
                            if let artist = selectedArtistEntity {
                                EntityDetailView(
                                    entity: artist,
                                ) {
                                    isShowingEntityDetail = false
                                    selectedArtistEntity = nil
                                }
                                .zIndex(1)
                            } else if let album = selectedAlbumEntity {
                                EntityDetailView(
                                    entity: album,
                                ) {
                                    isShowingEntityDetail = false
                                    selectedAlbumEntity = nil
                                }
                                .zIndex(1)
                            }
                        }
                    }
                }
            )
            .onChange(of: selectedSidebarItem) { _, newItem in
                isShowingEntityDetail = false
                selectedArtistEntity = nil
                selectedAlbumEntity = nil
                
                if let item = newItem {
                    switch item.source {
                    case .fixed(let type):
                        // Handle fixed items
                        isShowingEntities = (type == .artists || type == .albums) && !isShowingEntityDetail
                        
                        // Load appropriate data
                        switch type {
                        case .discover, .tracks:
                            isShowingEntities = false
                        case .artists:
                            sortArtistEntities()
                        case .albums:
                            sortAlbumEntities()
                        }
                        
                    case .pinned(let pinnedItem):
                        // Handle pinned items
                        isShowingEntities = false
                        loadTracksForPinnedItem(pinnedItem)
                    }
                } else {
                    isShowingEntities = false
                }
            }
            .onChange(of: isShowingEntityDetail) {
                // When showing entity detail (tracks), we're not showing entities anymore
                if isShowingEntityDetail {
                    isShowingEntities = false
                } else if let item = selectedSidebarItem {
                    // When going back to entity list, check if we should show entities
                    if case .fixed(let type) = item.source {
                        isShowingEntities = (type == .artists || type == .albums)
                    } else {
                        isShowingEntities = false
                    }
                }
            }
        }
    }
    
    // MARK: - Discover View

    private var discoverView: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrackListHeaderWithOptions(
                title: "Discover",
                sortOrder: $trackTableSortOrder,
                tableRowSize: $trackTableRowSize
            ) {
                Button(action: {
                    libraryManager.refreshDiscoverTracks()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .hoverEffect(scale: 1.1)
                .help("Refresh Discover tracks")
            }
            
            Divider()

            if libraryManager.discoverTracks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: Icons.sparkles)
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("No undiscovered tracks")
                        .font(.headline)
                    
                    Text("You've played all tracks in your library!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                TrackView(
                    tracks: libraryManager.discoverTracks,
                    selectedTrackID: $selectedTrackID,
                    playlistID: nil,
                    entityID: nil,
                    sortOrder: $trackTableSortOrder,
                    onPlayTrack: { track in
                        playlistManager.playTrack(track, fromTracks: libraryManager.discoverTracks)
                        playlistManager.currentQueueSource = .library
                    },
                    contextMenuItems: { track in
                        TrackContextMenu.createMenuItems(
                            for: track,
                            playbackManager: playbackManager,
                            playlistManager: playlistManager,
                            currentContext: .library
                        )
                    }
                )
                .id(libraryManager.discoverLastUpdated)
            }
        }
        .onAppear {
            if libraryManager.discoverTracks.isEmpty {
                libraryManager.loadDiscoverTracks()
            }
        }
    }
    
    // MARK: - Tracks View
    
    private var tracksView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            TrackListHeaderWithOptions(
                title: "All tracks",
                sortOrder: $trackTableSortOrder,
                tableRowSize: $trackTableRowSize
            )
            
            Divider()
            
            // Show loading or tracks
            if libraryManager.tracks.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                    Spacer()
                }
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
                    contextMenuItems: { track in
                        TrackContextMenu.createMenuItems(
                            for: track,
                            playbackManager: playbackManager,
                            playlistManager: playlistManager,
                            currentContext: .library
                        )
                    }
                )
            }
        }
    }
    
    // MARK: - Artists View
    
    private var artistsView: some View {
        VStack(spacing: 0) {
            // Header
            TrackListHeader(
                title: "All Artists",
                trackCount: libraryManager.artistEntities.count
            ) {
                Button(action: {
                    entitySortAscending.toggle()
                    sortEntities()
                }) {
                    Image(Icons.sortIcon(for: entitySortAscending))
                        .renderingMode(.template)
                        .scaleEffect(0.8)
                }
                .buttonStyle(.borderless)
                .hoverEffect(scale: 1.1)
                .help("Sort \(entitySortAscending ? "descending" : "ascending")")
            }
            
            Divider()
            
            // Artists list
            if libraryManager.artistEntities.isEmpty {
                NoMusicEmptyStateView(context: .mainWindow)
            } else {
                EntityView(
                    entities: sortedArtistEntities,
                    onSelectEntity: { artist in
                        selectedArtistEntity = artist
                        selectedAlbumEntity = nil
                        isShowingEntityDetail = true
                    },
                    contextMenuItems: { artist in
                        createArtistContextMenuItems(for: artist)
                    }
                )
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .onAppear {
            if sortedArtistEntities.isEmpty {
                sortArtistEntities()
            }
        }
        .onReceive(libraryManager.$cachedArtistEntities) { _ in
            if libraryManager.artistEntities.count != lastArtistCount {
                sortArtistEntities()
            }
        }
    }
    
    // MARK: - Albums View
    
    private var albumsView: some View {
        VStack(spacing: 0) {
            // Header
            TrackListHeader(
                title: "All Albums",
                trackCount: libraryManager.albumEntities.count
            ) {
                Menu {
                    Section("Sort by") {
                        Toggle("Album", isOn: Binding(
                            get: { albumSortBy == .album },
                            set: { _ in
                                albumSortBy = .album
                                sortAlbumEntities()
                            }
                        ))

                        Toggle("Album artist", isOn: Binding(
                            get: { albumSortBy == .artist },
                            set: { _ in
                                albumSortBy = .artist
                                sortAlbumEntities()
                            }
                        ))
                        
                        Toggle("Year", isOn: Binding(
                            get: { albumSortBy == .year },
                            set: { _ in
                                albumSortBy = .year
                                sortAlbumEntities()
                            }
                        ))
                        
                        Toggle("Date added", isOn: Binding(
                            get: { albumSortBy == .dateAdded },
                            set: { _ in
                                albumSortBy = .dateAdded
                                sortAlbumEntities()
                            }
                        ))
                    }

                    Divider()

                    Section("Sort order") {
                        Toggle("Ascending", isOn: Binding(
                            get: { entitySortAscending },
                            set: { _ in
                                entitySortAscending = true
                                sortAlbumEntities()
                            }
                        ))
                        
                        Toggle("Descending", isOn: Binding(
                            get: { !entitySortAscending },
                            set: { _ in
                                entitySortAscending = false
                                sortAlbumEntities()
                            }
                        ))
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .hoverEffect(activeBackgroundColor: Color(NSColor.controlColor))
                .help("Sort albums")
            }
            
            Divider()
            
            // Albums list
            if libraryManager.albumEntities.isEmpty {
                NoMusicEmptyStateView(context: .mainWindow)
            } else {
                EntityView(
                    entities: sortedAlbumEntities,
                    onSelectEntity: { album in
                        selectedAlbumEntity = album
                        selectedArtistEntity = nil
                        isShowingEntityDetail = true
                    },
                    contextMenuItems: { album in
                        createAlbumContextMenuItems(for: album)
                    }
                )
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .onAppear {
            if sortedAlbumEntities.isEmpty {
                sortAlbumEntities()
            }
        }
        .onReceive(libraryManager.$cachedAlbumEntities) { _ in
            if libraryManager.albumEntities.count != lastAlbumCount {
                sortAlbumEntities()
            }
        }
        .onChange(of: albumSortBy) {
            sortAlbumEntities()
        }
    }
    
    // MARK: - Pinned Item Tracks View
    
    private var pinnedItemTracksView: some View {
        VStack(spacing: 0) {
            if let selectedItem = selectedSidebarItem,
               case .pinned(let pinnedItem) = selectedItem.source {
                // Check if it's a playlist
                if pinnedItem.itemType == .playlist,
                   let playlistId = pinnedItem.playlistId,
                   let playlist = playlistManager.playlists.first(where: { $0.id == playlistId }) {
                    // Use PlaylistDetailView for playlists
                    PlaylistDetailView(playlist: playlist)
                }
                // Check if it's an artist entity
                else if pinnedItem.filterType == .artists,
                         let artistEntity = libraryManager.artistEntities.first(where: { $0.name == pinnedItem.filterValue }) {
                    // Use EntityDetailView for artist entity
                    EntityDetailView(
                        entity: artistEntity,
                        onBack: nil
                    )
                }
                // Check if it's an album entity
                else if pinnedItem.filterType == .albums,
                         let albumEntity = libraryManager.albumEntities.first(where: { $0.name == pinnedItem.filterValue }) {
                    // Use EntityDetailView for album entity
                    EntityDetailView(
                        entity: albumEntity,
                        onBack: nil
                    )
                }
                // For all other pinned items (genres, years, composers, etc.)
                else {
                    // Regular track list header
                    TrackListHeaderWithOptions(
                        title: pinnedItem.displayName,
                        sortOrder: $trackTableSortOrder,
                        tableRowSize: $trackTableRowSize
                    )

                    Divider()

                    // Track list
                    if pinnedItemTracks.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "pin.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            
                            Text("No tracks found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.textBackgroundColor))
                    } else {
                        TrackView(
                            tracks: pinnedItemTracks,
                            selectedTrackID: $selectedTrackID,
                            playlistID: nil,
                            entityID: nil,
                            sortOrder: $trackTableSortOrder,
                            onPlayTrack: { track in
                                playlistManager.playTrack(track, fromTracks: pinnedItemTracks)
                                playlistManager.currentQueueSource = .library
                            },
                            contextMenuItems: { track in
                                TrackContextMenu.createMenuItems(
                                    for: track,
                                    playbackManager: playbackManager,
                                    playlistManager: playlistManager,
                                    currentContext: .library
                                )
                            }
                        )
                        .background(Color(NSColor.textBackgroundColor))
                    }
                }
            } else {
                NoMusicEmptyStateView(context: .mainWindow)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var navigationTitle: String {
        if isShowingEntityDetail {
            if let artist = selectedArtistEntity {
                return artist.name
            } else if let album = selectedAlbumEntity {
                return album.name
            }
        }
        return selectedSidebarItem?.title ?? "Home"
    }
    
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
        .background(Color(NSColor.textBackgroundColor))
    }
    
    private func sortArtistEntities() {
        sortedArtistEntities = entitySortAscending
        ? libraryManager.artistEntities.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        : libraryManager.artistEntities.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        lastArtistCount = sortedArtistEntities.count
    }
    
    private func sortAlbumEntities() {
        let albums = libraryManager.albumEntities

        func tiebreaker(_ a: AlbumEntity, _ b: AlbumEntity) -> Bool {
            let comparison = a.name.localizedCaseInsensitiveCompare(b.name)
            return entitySortAscending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }

        switch albumSortBy {
        case .album:
            sortedAlbumEntities = entitySortAscending
                ? albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                : albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }

        case .artist:
            sortedAlbumEntities = albums.sorted { a, b in
                let comparison = (a.artistName ?? "")
                    .localizedCaseInsensitiveCompare(b.artistName ?? "")
                if comparison == .orderedSame { return tiebreaker(a, b) }
                
                return entitySortAscending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }

        case .year:
            sortedAlbumEntities = albums.sorted { a, b in
                let comparison = (a.year ?? "").compare(b.year ?? "")
                if comparison == .orderedSame { return tiebreaker(a, b) }
                
                return entitySortAscending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }

        case .dateAdded:
            sortedAlbumEntities = albums.sorted { a, b in
                let date1 = a.dateAdded ?? .distantPast
                let date2 = b.dateAdded ?? .distantPast
                if date1 == date2 { return tiebreaker(a, b) }
                
                return entitySortAscending ? date1 < date2 : date1 > date2
            }
        }

        lastAlbumCount = sortedAlbumEntities.count
    }
    
    private func sortEntities() {
        sortArtistEntities()
        sortAlbumEntities()
    }
    
    private func loadTracksForPinnedItem(_ item: PinnedItem) {
        let tracks: [Track]
        
        switch item.itemType {
        case .library:
            tracks = libraryManager.getTracksForPinnedItem(item)
        case .playlist:
            tracks = playlistManager.getTracksForPinnedPlaylist(item)
        }
        
        pinnedItemTracks = tracks
    }
    
    private func createAlbumContextMenuItems(for album: AlbumEntity) -> [ContextMenuItem] {
        [libraryManager.createPinContextMenuItem(for: album)]
    }
    
    private func createArtistContextMenuItems(for artist: ArtistEntity) -> [ContextMenuItem] {
        [libraryManager.createPinContextMenuItem(for: artist)]
    }
}

#Preview {
    @Previewable @State var isShowingEntities = false
    
    HomeView(isShowingEntities: $isShowingEntities)
        .environmentObject(LibraryManager())
        .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
        .environmentObject(PlaylistManager())
        .frame(width: 800, height: 600)
}
