import SwiftUI

enum AlbumSortOption: String, Codable {
    case album
    case artist
    case year
    case dateAdded
}

struct HomeView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager
    
    @AppStorage("entitySortAscending")
    private var entitySortAscending: Bool = true

    @AppStorage("albumSortBy")
    private var albumSortBy: AlbumSortOption = .album
    
    @AppStorage("trackTableRowSize")
    private var trackTableRowSize: TableRowSize = .expanded
    
    @Binding var selectedSidebarItem: HomeSidebarItem?
    @State private var selectedTrackID: UUID?
    @State private var pinnedItemTracks: [Track] = []
    @State private var pinnedEntity: (any Entity)?
    @State private var sortedArtistEntities: [ArtistEntity] = []
    @State private var sortedAlbumEntities: [AlbumEntity] = []
    @State private var selectedArtistEntity: ArtistEntity?
    @State private var selectedAlbumEntity: AlbumEntity?
    @State private var isShowingEntityDetail = false
    @State private var trackTableSortOrder = [KeyPathComparator(\Track.title)]
    @Binding var isShowingEntities: Bool
    
    var body: some View {
        if !libraryManager.shouldShowMainUI {
            NoMusicEmptyStateView(context: .mainWindow)
        } else {
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
                .navigationTitle(selectedSidebarItem?.title ?? String(localized: "Home"))
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
            .onChange(of: selectedSidebarItem) { _, newItem in
                isShowingEntityDetail = false
                selectedArtistEntity = nil
                selectedAlbumEntity = nil
                pinnedEntity = nil

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
            TrackListHeader(
                title: String(localized: "Discover"),
                sortOrder: $trackTableSortOrder,
                tableRowSize: $trackTableRowSize
            ) {
                Button(action: {
                    libraryManager.refreshDiscoverTracks()
                }, label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                })
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
                    contextMenuItems: { track, _ in
                        TrackContextMenu.createMenuItems(
                            for: track,
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
            TrackListHeader(
                title: String(localized: "All tracks"),
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
    
    // MARK: - Artists View
    
    private var artistsView: some View {
        VStack(spacing: 0) {
            // Header
            TrackListHeader(
                title: String(localized: "All Artists"),
                trackCount: libraryManager.artistEntities.count
            ) {
                Button(action: {
                    entitySortAscending.toggle()
                    sortEntities()
                }, label: {
                    Image(Icons.sortIcon(for: entitySortAscending))
                        .renderingMode(.template)
                        .scaleEffect(0.8)
                })
                .buttonStyle(.borderless)
                .hoverEffect(scale: 1.1)
                .help(entitySortAscending ? String(localized: "Sort descending") : String(localized: "Sort ascending"))
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
                        libraryManager.contextMenuItems(for: artist)
                    }
                )
            }
        }
        .onAppear {
            if sortedArtistEntities.isEmpty {
                sortArtistEntities()
            }
        }
        .onReceive(libraryManager.$cachedArtistEntities) { artists in
            // Sort the received value; @Published fires on willSet, so the manager still holds the old array
            sortArtistEntities(artists)
        }
    }
    
    // MARK: - Albums View
    
    private var albumsView: some View {
        VStack(spacing: 0) {
            // Header
            TrackListHeader(
                title: String(localized: "All Albums"),
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
                        libraryManager.contextMenuItems(for: album)
                    }
                )
            }
        }
        .onAppear {
            if sortedAlbumEntities.isEmpty {
                sortAlbumEntities()
            }
        }
        .onReceive(libraryManager.$cachedAlbumEntities) { albums in
            // Sort the received value (see artists onReceive); no count guard, artwork updates keep the count
            sortAlbumEntities(albums)
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
                if pinnedItem.itemType == .playlist,
                   let playlistId = pinnedItem.playlistId,
                   let playlist = playlistManager.playlists.first(where: { $0.id == playlistId }) {
                    PlaylistDetailView(playlist: playlist)
                } else if let entity = pinnedEntity {
                    EntityDetailView(entity: entity, pinnedItem: pinnedItem)
                } else {
                    NoMusicEmptyStateView(context: .mainWindow)
                }
            } else {
                NoMusicEmptyStateView(context: .mainWindow)
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

    private func sortArtistEntities(_ artists: [ArtistEntity]? = nil) {
        let artists = artists ?? libraryManager.artistEntities
        sortedArtistEntities = entitySortAscending
        ? artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        : artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
    }

    private func sortAlbumEntities(_ albums: [AlbumEntity]? = nil) {
        let albums = albums ?? libraryManager.albumEntities

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
    }
    
    private func sortEntities() {
        sortArtistEntities()
        sortAlbumEntities()
    }
    
    private func loadTracksForPinnedItem(_ item: PinnedItem) {
        let tracks: [Track]

        switch item.itemType {
        case .library, .folder:
            tracks = libraryManager.getTracksForPinnedItem(item)
        case .playlist:
            tracks = playlistManager.getTracksForPinnedPlaylist(item)
        }

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
                pinnedEntity = libraryManager.artistEntities.first { $0.name == filterValue }
            case .albums:
                // Match the exact album by id (titles aren't unique); legacy nil falls back to title.
                if let albumId = item.albumId {
                    pinnedEntity = libraryManager.albumEntities.first { $0.albumId == albumId }
                        ?? libraryManager.albumEntities.first { $0.name == filterValue }
                } else {
                    pinnedEntity = libraryManager.albumEntities.first { $0.name == filterValue }
                }
            case .albumArtists, .composers:
                pinnedEntity = buildArtistEntityForPerson(name: filterValue)
            case .genres, .decades, .years:
                pinnedEntity = CategoryEntity(name: filterValue, trackCount: tracks.count, filterType: filterType)
            }
        } else {
            pinnedEntity = nil
        }
    }
}

#Preview {
    @Previewable @State var isShowingEntities = false
    @Previewable @State var selectedSidebarItem: HomeSidebarItem?

    HomeView(selectedSidebarItem: $selectedSidebarItem, isShowingEntities: $isShowingEntities)
        .environmentObject(LibraryManager())
        .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
        .environmentObject(PlaylistManager())
        .frame(width: 800, height: 600)
}
