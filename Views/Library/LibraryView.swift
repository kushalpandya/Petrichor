import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager

    @AppStorage("librarySelectedFilterType")
    private var selectedFilterType: LibraryFilterType = .artists
    
    @AppStorage("sidebarSplitPosition")
    private var splitPosition: Double = 200
    
    @AppStorage("trackListSortAscending")
    private var trackListSortAscending: Bool = true
    
    @State private var selectedTrackID: UUID?
    @State private var selectedFilterItem: LibraryFilterItem?
    @State private var cachedFilteredTracks: [Track] = []
    @State private var pendingSearchText: String?
    @State private var isViewReady = false
    @Binding var pendingFilter: LibraryFilterRequest?

    let viewType: LibraryViewType

    var body: some View {
        VStack {
            if libraryManager.folders.isEmpty {
                NoMusicEmptyStateView(context: .mainWindow)
            } else {
                // Main library view with sidebar
                PersistentSplitView(
                    left: {
                        LibrarySidebarView(
                            selectedFilterType: $selectedFilterType,
                            selectedFilterItem: $selectedFilterItem,
                            pendingSearchText: $pendingSearchText
                        )
                    },
                    main: {
                        tracksListView
                    }
                )
                .onChange(of: libraryManager.tracks) { _, newTracks in
                    if let currentItem = selectedFilterItem, currentItem.isAllItem {
                        selectedFilterItem = LibraryFilterItem.allItem(for: selectedFilterType, totalCount: newTracks.count)
                    }
                }
                .onDisappear {
                    isViewReady = false
                }
                .onChange(of: libraryManager.tracks) { _, newTracks in
                    // Update filter item when tracks change
                    if let currentItem = selectedFilterItem, currentItem.isAllItem {
                        selectedFilterItem = LibraryFilterItem.allItem(for: selectedFilterType, totalCount: newTracks.count)
                    }
                }
                .onChange(of: selectedFilterItem) {
                    updateFilteredTracks()
                }
                .onChange(of: selectedFilterType) {
                    updateFilteredTracks()
                }
                .onChange(of: libraryManager.totalTrackCount) {
                    updateFilteredTracks()
                }
                .onChange(of: trackListSortAscending) {
                    updateFilteredTracks()
                }
                .onChange(of: pendingFilter) { _, newValue in
                    if let request = newValue {
                        pendingFilter = nil
                        selectedFilterType = request.filterType
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            pendingSearchText = request.value
                        }
                    }
                }
                .onChange(of: libraryManager.globalSearchText) {
                    updateFilteredTracks()
                }
                .onReceive(NotificationCenter.default.publisher(for: .libraryDataDidChange)) { _ in
                    updateFilteredTracks()
                }
            }
        }
    }

    init(viewType: LibraryViewType, pendingFilter: Binding<LibraryFilterRequest?> = .constant(nil)) {
        self.viewType = viewType
        self._pendingFilter = pendingFilter
    }

    // MARK: - Tracks List View

    private var tracksListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            tracksListHeader

            Divider()

            // Tracks list content
            if cachedFilteredTracks.isEmpty {
                emptyFilterView
            } else {
                TrackView(
                    tracks: cachedFilteredTracks,
                    viewType: viewType,
                    selectedTrackID: $selectedTrackID,
                    playlistID: nil,
                    entityID: nil,
                    onPlayTrack: { track in
                        playlistManager.playTrack(track, fromTracks: cachedFilteredTracks)
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
    }

    // MARK: - Tracks List Header

    private var tracksListHeader: some View {
        Group {
            if viewType == .table {
                TrackListHeader(
                    title: headerTitle,
                    trackCount: cachedFilteredTracks.count
                ) {
                    EmptyView()
                }
            } else {
                TrackListHeader(
                    title: headerTitle,
                    trackCount: cachedFilteredTracks.count
                ) {
                    Button(action: { trackListSortAscending.toggle() }) {
                        Image(Icons.sortIcon(for: trackListSortAscending))
                            .renderingMode(.template)
                            .scaleEffect(0.8)
                    }
                    .buttonStyle(.borderless)
                    .hoverEffect(scale: 1.1)
                    .help("Sort tracks \(trackListSortAscending ? "descending" : "ascending")")
                }
            }
        }
    }

    private var headerTitle: String {
        if !libraryManager.globalSearchText.isEmpty {
            return "Search Results"
        } else if let filterItem = selectedFilterItem {
            if filterItem.isAllItem {
                return "All Tracks"
            } else {
                return filterItem.name
            }
        } else {
            return "All Tracks"
        }
    }

    // MARK: - Empty Filter View

    private var emptyFilterView: some View {
        VStack(spacing: 16) {
            Image(systemName: Icons.musicNoteList)
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text(libraryManager.globalSearchText.isEmpty ? "No Tracks Found" : "No Search Results")
                .font(.headline)

            if !libraryManager.globalSearchText.isEmpty {
                Text("No tracks found matching \"\(libraryManager.globalSearchText)\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else if let filterItem = selectedFilterItem, !filterItem.isAllItem {
                Text("No tracks found for \"\(filterItem.name)\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No tracks match the current filter")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Filtering Tracks Helper

    private func updateFilteredTracks() {
        // If we have a global search, use database FTS search
        if !libraryManager.globalSearchText.isEmpty {
            // searchResults should already be populated by updateSearchResults()
            // which uses database FTS search
            var tracks = libraryManager.searchResults
            
            // Apply sidebar filter if present
            if let filterItem = selectedFilterItem, !filterItem.isAllItem {
                tracks = tracks.filter { track in
                    selectedFilterType.trackMatches(track, filterValue: filterItem.name)
                }
            }
            
            cachedFilteredTracks = sortTracks(tracks)
        } else {
            // No global search - load only what's needed based on selection
            if let filterItem = selectedFilterItem {
                if filterItem.isAllItem {
                    // "All" item selected during search - we shouldn't get here with our new logic
                    cachedFilteredTracks = []
                } else {
                    // Load tracks for specific filter from database
                    var tracks = libraryManager.getTracksBy(filterType: selectedFilterType, value: filterItem.name)
                    // Populate album artwork for the tracks
                    libraryManager.databaseManager.populateAlbumArtworkForTracks(&tracks)
                    cachedFilteredTracks = sortTracks(tracks)
                }
            } else {
                cachedFilteredTracks = []
            }
        }
    }

    private func sortTracks(_ tracks: [Track]) -> [Track] {
        tracks.sorted { track1, track2 in
            let comparison = track1.title.localizedCaseInsensitiveCompare(track2.title)
            return trackListSortAscending ?
                comparison == .orderedAscending :
                comparison == .orderedDescending
        }
    }

    // MARK: - Context Menu Helper

    private func createLibraryContextMenu(for track: Track) -> [ContextMenuItem] {
        TrackContextMenu.createMenuItems(
            for: track,
            playbackManager: playbackManager,
            playlistManager: playlistManager,
            currentContext: .library
        )
    }
}

#Preview {
    LibraryView(viewType: .list)
        .environmentObject({
            let coordinator = AppCoordinator()
            return coordinator.playbackManager
        }())
        .environmentObject({
            let coordinator = AppCoordinator()
            return coordinator.libraryManager
        }())
        .environmentObject({
            let coordinator = AppCoordinator()
            return coordinator.playlistManager
        }())
}
