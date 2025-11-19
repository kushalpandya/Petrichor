import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager

    @AppStorage("librarySelectedFilterType")
    private var selectedFilterType: LibraryFilterType = .artists
    
    @AppStorage("sidebarSplitPosition")
    private var splitPosition: Double = 200
    
    @AppStorage("trackTableRowSize")
    private var trackTableRowSize: TableRowSize = .expanded
    
    @State private var selectedTrackID: UUID?
    @State private var selectedFilterItem: LibraryFilterItem?
    @State private var cachedFilteredTracks: [Track] = []
    @State private var pendingSearchText: String?
    @State private var isLibrarySearchActive = false
    @State private var isViewReady = false
    @State private var trackTableSortOrder = [KeyPathComparator(\Track.title)]
    @State private var filterUpdateTask: Task<Void, Never>?
    @Binding var pendingFilter: LibraryFilterRequest?

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
                .onAppear {
                    processPendingFilter()
                }
                .onDisappear {
                    isViewReady = false
                }
                .onChange(of: libraryManager.tracks) { _, newTracks in
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
                .onChange(of: pendingFilter) {
                    processPendingFilter()
                }
                .onChange(of: libraryManager.globalSearchText) {
                    handleGlobalSearch()
                }
                .onReceive(NotificationCenter.default.publisher(for: .libraryDataDidChange)) { _ in
                    updateFilteredTracks()
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func processPendingFilter() {
        guard let request = pendingFilter else { return }
        
        pendingFilter = nil
        selectedFilterType = request.filterType
        pendingSearchText = request.value
    }

    private func handleGlobalSearch() {
        isLibrarySearchActive = true
        Task {
            try? await Task.sleep(nanoseconds: TimeConstants.searchDebounceDuration)
            await MainActor.run {
                updateFilteredTracks()
                isLibrarySearchActive = false
            }
        }
    }

    init(pendingFilter: Binding<LibraryFilterRequest?> = .constant(nil)) {
        self._pendingFilter = pendingFilter
    }

    // MARK: - Tracks List View

    private var tracksListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            TrackListHeaderWithOptions(
                title: headerTitle,
                sortOrder: $trackTableSortOrder,
                tableRowSize: $trackTableRowSize
            )

            Divider()

            // Tracks list content
            if cachedFilteredTracks.isEmpty && !isLibrarySearchActive {
                emptyFilterView
            } else {
                TrackView(
                    tracks: cachedFilteredTracks,
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
        filterUpdateTask?.cancel()
        
        if !libraryManager.globalSearchText.isEmpty {
            var tracks = libraryManager.searchResults
            
            if let filterItem = selectedFilterItem, !filterItem.isAllItem {
                tracks = tracks.filter { track in
                    selectedFilterType.trackMatches(track, filterValue: filterItem.name)
                }
            }
            
            cachedFilteredTracks = tracks
        } else {
            if let filterItem = selectedFilterItem {
                if filterItem.isAllItem {
                    cachedFilteredTracks = []
                } else {
                    let filterType = selectedFilterType
                    let filterValue = filterItem.name
                    let libManager = libraryManager
                    
                    filterUpdateTask = Task {
                        try? await Task.sleep(nanoseconds: TimeConstants.oneHundredMilliseconds)
                        
                        guard !Task.isCancelled else { return }
                        
                        let tracks = await Task.detached {
                            var tracks = libManager.getTracksBy(filterType: filterType, value: filterValue)
                            libManager.databaseManager.populateAlbumArtworkForTracks(&tracks)
                            return tracks
                        }.value
                        
                        guard !Task.isCancelled else { return }
                        
                        await MainActor.run {
                            self.cachedFilteredTracks = tracks
                        }
                    }
                }
            } else {
                cachedFilteredTracks = []
            }
        }
    }

    // MARK: - Context Menu Helper

    private func createLibraryContextMenu(for tracks: [Track]) -> [ContextMenuItem] {
        TrackContextMenu.createMenuItems(
            for: tracks,
            playbackManager: playbackManager,
            playlistManager: playlistManager,
            currentContext: .library
        )
    }
}

#Preview {
    LibraryView()
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
