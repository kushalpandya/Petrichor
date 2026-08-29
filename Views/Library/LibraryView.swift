import SwiftUI

private enum LibraryTrackSortContext: Hashable {
    case album(id: Int64?, name: String)
    case person(type: LibraryFilterType, name: String)
    case global
}

struct LibraryView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager

    @Binding var selectedFilterType: LibraryFilterType
    @Binding var selectedFilterItem: LibraryFilterItem?
    @Binding var pendingSearchText: String?
    @Binding var cachedFilteredTracks: [Track]
    @Binding var filteredItems: [LibraryFilterItem]
    @Binding var selectedSidebarItem: LibrarySidebarItem?

    @AppStorage("trackTableRowSize")
    private var trackTableRowSize: TableRowSize = .expanded

    @State private var playbackTargetID = UUID()
    @State private var isLibrarySearchActive = false
    @State private var isFilterLoading = false
    @State private var isViewReady = false
    @State private var trackTableSortOrder = [KeyPathComparator(\Track.title)]
    @State private var globalFallbackSortOrder = [KeyPathComparator(\Track.title, order: .forward)]
    @State private var filterUpdateTask: Task<Void, Never>?
    @State private var searchUpdateTask: Task<Void, Never>?
    @State private var lastFilterUpdateAt: Date = .distantPast
    @State private var sortContext: LibraryTrackSortContext?
    @Binding var pendingFilter: LibraryFilterRequest?

    var body: some View {
        if !libraryManager.hasLocalMusic {
            NoMusicEmptyStateView(context: .localLibrary)
        } else {
            libraryContent
                .onAppear {
                    processPendingFilter()
                    if cachedFilteredTracks.isEmpty, selectedFilterItem != nil {
                        updateFilteredTracks()
                    }
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

    // MARK: - Helper Methods

    private func processPendingFilter() {
        guard let request = pendingFilter else { return }
        
        pendingFilter = nil
        selectedFilterType = request.filterType
        pendingSearchText = request.value
    }

    private func handleGlobalSearch() {
        isLibrarySearchActive = true
        searchUpdateTask?.cancel()
        searchUpdateTask = Task {
            try? await Task.sleep(nanoseconds: TimeConstants.searchDebounceDuration)
            guard !Task.isCancelled else { return }
            updateFilteredTracks()
            isLibrarySearchActive = false
        }
    }

    init(
        selectedFilterType: Binding<LibraryFilterType>,
        selectedFilterItem: Binding<LibraryFilterItem?>,
        pendingSearchText: Binding<String?>,
        cachedFilteredTracks: Binding<[Track]>,
        filteredItems: Binding<[LibraryFilterItem]>,
        selectedSidebarItem: Binding<LibrarySidebarItem?>,
        pendingFilter: Binding<LibraryFilterRequest?> = .constant(nil)
    ) {
        self._selectedFilterType = selectedFilterType
        self._selectedFilterItem = selectedFilterItem
        self._pendingSearchText = pendingSearchText
        self._cachedFilteredTracks = cachedFilteredTracks
        self._filteredItems = filteredItems
        self._selectedSidebarItem = selectedSidebarItem
        self._pendingFilter = pendingFilter
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        PersistentSplitView(
            left: {
                LibrarySidebarView(
                    selectedFilterType: $selectedFilterType,
                    selectedFilterItem: $selectedFilterItem,
                    pendingSearchText: $pendingSearchText,
                    filteredItems: $filteredItems,
                    selectedSidebarItem: $selectedSidebarItem
                )
            },
            main: {
                tracksListView
            },
            leftStorageKey: "libraryItemsSplitPosition"
        )
    }

    // MARK: - Tracks List View

    private var tracksListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            TrackListHeader(
                title: headerTitle,
                sortOrder: $trackTableSortOrder,
                tableRowSize: $trackTableRowSize,
                usesGlobalSortOrder: trackGrouping == .none,
                showsArtistGroupingOptions: trackGrouping == .albumAndDisc,
                playAction: playVisibleTracks,
                isPlayDisabled: cachedFilteredTracks.isEmpty || isFilterLoading
            )

            Divider()

            // Tracks list content
            if isFilterLoading {
                ActivityAnimation(size: .large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cachedFilteredTracks.isEmpty && !isLibrarySearchActive {
                emptyFilterView
            } else {
                TrackView(
                    tracks: cachedFilteredTracks,
                    playlistID: nil,
                    entityID: nil,
                    playbackTargetID: playbackTargetID,
                    grouping: trackGrouping,
                    fallbackSortOrder: globalFallbackSortOrder,
                    usesGlobalSortOrder: trackGrouping == .none,
                    sortOrder: $trackTableSortOrder,
                    onPlayTrack: { track in
                        playlistManager.playTrack(track, fromTracks: cachedFilteredTracks)
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

    // MARK: - Tracks List Header

    private func playVisibleTracks() {
        NotificationCenter.default.post(
            name: .playVisibleTrackTable,
            object: nil,
            userInfo: ["targetID": playbackTargetID]
        )
    }

    private var headerTitle: String {
        if !libraryManager.globalSearchText.isEmpty {
            return String(localized: "Search Results")
        } else if let filterItem = selectedFilterItem {
            if filterItem.isAllItem {
                return String(localized: "All Tracks")
            } else {
                return filterItem.name
            }
        } else {
            return String(localized: "All Tracks")
        }
    }

    private var usesAlbumPresentation: Bool {
        libraryManager.globalSearchText.isEmpty
            && selectedFilterType == .albums
            && selectedFilterItem?.isAllItem == false
    }

    private var usesPersonPresentation: Bool {
        libraryManager.globalSearchText.isEmpty
            && selectedFilterType.usesMultiArtistParsing
            && selectedFilterItem?.isAllItem == false
    }

    private var trackGrouping: TrackGrouping {
        if usesAlbumPresentation { return .disc }
        if usesPersonPresentation { return .albumAndDisc }
        return .none
    }

    // MARK: - Empty Filter View

    private var emptyFilterView: some View {
        VStack(spacing: 16) {
            Image(systemName: Icons.musicNoteList)
                .font(.system(size: 48))
                .foregroundColor(.gray)

            (libraryManager.globalSearchText.isEmpty ? Text("No Tracks Found") : Text("No Search Results"))
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
        updateTrackSortOrder()

        let now = Date()
        // Only debounce when the previous request was very recent (rapid sidebar
        // navigation). A single deliberate selection should load immediately.
        let isRapidChange = now.timeIntervalSince(lastFilterUpdateAt) < 0.1
        lastFilterUpdateAt = now

        filterUpdateTask?.cancel()

        if !libraryManager.globalSearchText.isEmpty {
            isFilterLoading = false
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
                    isFilterLoading = false
                    cachedFilteredTracks = []
                } else {
                    let filterType = selectedFilterType
                    let filterValue = filterItem.name
                    let albumId = filterItem.albumId
                    let libManager = libraryManager
                    cachedFilteredTracks = []
                    isFilterLoading = true

                    filterUpdateTask = Task {
                        if isRapidChange {
                            try? await Task.sleep(nanoseconds: TimeConstants.oneHundredMilliseconds)
                        }

                        guard !Task.isCancelled else { return }

                        let tracks = await Task.detached {
                            var tracks = libManager.getTracksBy(filterType: filterType, value: filterValue, albumId: albumId)
                            libManager.databaseManager.populateAlbumArtworkForTracks(&tracks)
                            return tracks
                        }.value

                        guard !Task.isCancelled else { return }

                        await MainActor.run {
                            self.cachedFilteredTracks = tracks
                            self.isFilterLoading = false
                        }
                    }
                }
            } else {
                isFilterLoading = false
                cachedFilteredTracks = []
            }
        }
    }

    private func updateTrackSortOrder() {
        let newContext: LibraryTrackSortContext
        if usesAlbumPresentation {
            newContext = .album(id: selectedFilterItem?.albumId, name: selectedFilterItem?.name ?? "")
        } else if usesPersonPresentation {
            newContext = .person(type: selectedFilterType, name: selectedFilterItem?.name ?? "")
        } else {
            newContext = .global
        }
        guard newContext != sortContext else { return }
        sortContext = newContext

        globalFallbackSortOrder = TrackSortPreferences.loadGlobal()
        if usesAlbumPresentation {
            trackTableSortOrder = Track.albumSortOrder
        } else if usesPersonPresentation {
            trackTableSortOrder = Track.artistSortOrder
        } else {
            trackTableSortOrder = globalFallbackSortOrder
        }
    }
}

#Preview {
    @Previewable @State var filterType: LibraryFilterType = .artists
    @Previewable @State var filterItem: LibraryFilterItem?
    @Previewable @State var searchText: String?
    @Previewable @State var cachedTracks: [Track] = []
    @Previewable @State var filteredItems: [LibraryFilterItem] = []
    @Previewable @State var selectedSidebarItem: LibrarySidebarItem?

    LibraryView(
        selectedFilterType: $filterType,
        selectedFilterItem: $filterItem,
        pendingSearchText: $searchText,
        cachedFilteredTracks: $cachedTracks,
        filteredItems: $filteredItems,
        selectedSidebarItem: $selectedSidebarItem
    )
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
