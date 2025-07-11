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
    @State private var showingCreatePlaylistWithTrack = false
    @State private var trackToAddToNewPlaylist: Track?
    @State private var newPlaylistName = ""
    @State private var cachedFilteredTracks: [Track] = []
    @State private var pendingSearchText: String?
    @State private var isViewReady = false
    @Binding var pendingFilter: LibraryFilterRequest?

    let viewType: LibraryViewType

    var body: some View {
        VStack {
            if libraryManager.tracks.isEmpty {
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
                .onAppear {
                    // Set initial filter selection
                    if selectedFilterItem == nil {
                        selectedFilterItem = LibraryFilterItem.allItem(for: selectedFilterType, totalCount: libraryManager.tracks.count)
                    }
                    updateFilteredTracks()

                    // Mark view as ready
                    isViewReady = true

                    // Check if there's a pending filter to apply
                    if let request = pendingFilter {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            selectedFilterType = request.filterType
                            pendingSearchText = request.value
                            pendingFilter = nil
                        }
                    }
                }
                .onDisappear {
                    isViewReady = false
                }
                .onChange(of: libraryManager.tracks) { _, newTracks in
                    // Update filter item when tracks change
                    if let currentItem = selectedFilterItem, currentItem.name.hasPrefix("All") {
                        selectedFilterItem = LibraryFilterItem.allItem(for: selectedFilterType, totalCount: newTracks.count)
                    }
                }
                .onChange(of: selectedFilterItem) {
                    updateFilteredTracks()
                }
                .onChange(of: selectedFilterType) {
                    updateFilteredTracks()
                }
                .onChange(of: libraryManager.tracks.count) {
                    // Only update if the number of tracks changed (tracks added/removed)
                    updateFilteredTracks()
                }
                .onChange(of: trackListSortAscending) {
                    updateFilteredTracks()
                }
                .onChange(of: pendingFilter) { _, newValue in
                    if let request = newValue, isViewReady {
                        Logger.info("View is ready, applying filter type: \(request.filterType)")
                        selectedFilterType = request.filterType
                        pendingSearchText = request.value
                        pendingFilter = nil
                    }
                    // If view is not ready, onAppear will handle it
                }
                .onChange(of: libraryManager.globalSearchText) {
                    updateFilteredTracks()
                }
                .sheet(isPresented: $showingCreatePlaylistWithTrack) {
                    createPlaylistSheet
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CreatePlaylistWithTrack"))) { notification in
                    if let track = notification.userInfo?["track"] as? Track {
                        trackToAddToNewPlaylist = track
                        showingCreatePlaylistWithTrack = true
                    }
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
                    .help("Sort tracks \(trackListSortAscending ? "descending" : "ascending")")
                }
            }
        }
    }

    private var headerTitle: String {
        if !libraryManager.globalSearchText.isEmpty {
            return "Search Results"
        } else if let filterItem = selectedFilterItem {
            if filterItem.name.hasPrefix("All") {
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
            } else if let filterItem = selectedFilterItem, !filterItem.name.hasPrefix("All") {
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
        // Start with all tracks
        var tracks = libraryManager.searchResults

        // Then apply sidebar filter if present
        if let filterItem = selectedFilterItem, !filterItem.name.hasPrefix("All") {
            tracks = tracks.filter { track in
                selectedFilterType.trackMatches(track, filterValue: filterItem.name)
            }
        }

        cachedFilteredTracks = sortTracks(tracks)
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

    // MARK: - Create Playlist Sheet

    private var createPlaylistSheet: some View {
        VStack(spacing: 20) {
            Text("New Playlist")
                .font(.headline)

            TextField("Playlist Name", text: $newPlaylistName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            if let track = trackToAddToNewPlaylist {
                Text("Will add: \(track.title)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    newPlaylistName = ""
                    trackToAddToNewPlaylist = nil
                    showingCreatePlaylistWithTrack = false
                }
                .keyboardShortcut(.escape)

                Button("Create") {
                    if !newPlaylistName.isEmpty, let track = trackToAddToNewPlaylist {
                        _ = playlistManager.createPlaylist(
                            name: newPlaylistName,
                            tracks: [track]
                        )
                        newPlaylistName = ""
                        trackToAddToNewPlaylist = nil
                        showingCreatePlaylistWithTrack = false
                    }
                }
                .keyboardShortcut(.return)
                .disabled(newPlaylistName.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 350)
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
