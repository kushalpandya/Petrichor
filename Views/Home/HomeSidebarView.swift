import SwiftUI

struct HomeSidebarView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @Binding var selectedItem: HomeSidebarItem?
    
    @State private var allItems: [HomeSidebarItem] = []
    @State private var hasLoadedInitialCounts = false
    @State private var pinnedItemTrackCounts: [Int64: Int] = [:]
    @State private var playlistToDelete: Playlist?
    @State private var showingDeleteConfirmation = false
    @ObservedObject private var radioManager = InternetRadioManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ListHeader(opaque: true) {
                Text("")
                    .headerTitleStyle()
                Spacer()
            }
            
            Divider()
            
            // All items in one list
            // `SidebarView` has several optional closure parameters; explicit labels keep this call readable.
            SidebarView(
                items: allItems,
                selectedItem: $selectedItem,
                onItemTap: { item in
                    selectedItem = item
                },
                contextMenuItems: { item in
                    createContextMenuItems(for: item)
                },
                showIcon: true,
                iconColor: .secondary,
                showCount: false,
                trailingContent: { item in
                    trailingContentView(for: item)
                },
                reorderableFromIndex: libraryManager.hasLocalMusic
                    ? HomeSidebarItem.HomeItemType.allCases.count
                    : 1,
                // swiftlint:disable:next trailing_closure
                onReorder: { reorderedItems in
                    handlePinnedItemsReorder(reorderedItems)
                }
            )
        }
        .alert("Delete Playlist", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                playlistToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let playlist = playlistToDelete {
                    playlistManager.deletePlaylist(playlist)
                    playlistToDelete = nil
                }
            }
        } message: {
            if let playlist = playlistToDelete {
                Text("Are you sure you want to delete \"\(DefaultPlaylists.displayName(for: playlist))\"? This action cannot be undone.")
            }
        }
        .onAppear {
            updateAllItems()

            if !hasLoadedInitialCounts {
                hasLoadedInitialCounts = true
                Task {
                    await updatePinnedItemTrackCounts()
                }
            }
        }
        .onChange(of: libraryManager.tracks.count) {
            updateAllItems()
        }
        .onChange(of: libraryManager.pinnedItems) {
            updateAllItems()
            // Update selection if a pinned item was removed
            if let selected = selectedItem,
               case .pinned(let pinnedItem) = selected.source {
                if !libraryManager.pinnedItems.contains(where: { $0.id == pinnedItem.id }) {
                    selectedItem = allItems.first
                }
            }
        }
        .onChange(of: radioManager.stations.count) {
            updateAllItems()
        }
        .onChange(of: pinnedPlaylistCountSignature) {
            // Only rebuild when a *pinned* playlist's count changes. Count changes on
            // non-pinned playlists don't affect anything shown in the Home sidebar.
            updateAllItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDataDidChange)) { _ in
            updateAllItems()
            Task {
                await updatePinnedItemTrackCounts()
            }
        }
    }

    // MARK: - Update Items Helper

    /// Change signature of just the pinned playlists' counts, so the Home sidebar only
    /// rebuilds when a pinned playlist's count changes (not on any library playlist edit).
    private var pinnedPlaylistCountSignature: String {
        let playlistsById = Dictionary(playlistManager.playlists.map { ($0.id, $0) }) { first, _ in first }
        return libraryManager.pinnedItems
            .compactMap { $0.playlistId }
            .map { id in "\(id)-\(playlistsById[id]?.trackCount ?? 0)" }
            .joined(separator: ",")
    }

    private func updateAllItems() {
        if !libraryManager.hasLocalMusic {
            let playlistsById = Dictionary(playlistManager.playlists.map { ($0.id, $0) }) { first, _ in first }
            let stationPins = libraryManager.pinnedItems.compactMap { pinnedItem -> HomeSidebarItem? in
                guard let playlistId = pinnedItem.playlistId,
                      let playlist = playlistsById[playlistId],
                      playlist.type == .stations else { return nil }
                let cachedCount = pinnedItemTrackCounts[pinnedItem.id ?? 0] ?? playlist.trackCount
                return HomeSidebarItem(pinnedItem: pinnedItem, trackCount: cachedCount, playlist: playlist)
            }
            allItems = [HomeSidebarItem(type: .internetRadio, stationCount: radioManager.stations.count)] + stationPins
            restoreSelection(defaultType: .internetRadio)
            return
        }

        var items: [HomeSidebarItem] = [
            HomeSidebarItem(type: .discover),
            HomeSidebarItem(type: .tracks, trackCount: libraryManager.totalTrackCount),
            HomeSidebarItem(type: .internetRadio, stationCount: radioManager.stations.count)
        ]
        // O(1) playlist lookups instead of a linear scan per pinned item.
        let playlistsById = Dictionary(playlistManager.playlists.map { ($0.id, $0) }) { first, _ in first }
        let pinnedSidebarItems = libraryManager.pinnedItems.map { pinnedItem in
            let cachedCount = pinnedItemTrackCounts[pinnedItem.id ?? 0] ?? fallbackCount(for: pinnedItem)
            let playlist = pinnedItem.playlistId.flatMap { playlistsById[$0] }
            return HomeSidebarItem(pinnedItem: pinnedItem, trackCount: cachedCount, playlist: playlist)
        }
        items.append(contentsOf: pinnedSidebarItems)
        
        allItems = items
        restoreSelection(defaultType: .discover)
        
        // Update track counts asynchronously to avoid blocking UI
        Task {
            await updatePinnedItemTrackCounts()
        }
    }
    
    /// Stand-in until the async count lands, so default pins don't read "0 artists" at first.
    private func fallbackCount(for pinnedItem: PinnedItem) -> Int {
        guard pinnedItem.itemType == .category else { return 0 }

        switch pinnedItem.filterType {
        case .artists: return libraryManager.artistCount
        case .albums: return libraryManager.albumCount
        default: return 0
        }
    }

    private func updatePinnedItemTrackCounts() async {
        // Don't update if we have no pinned items
        guard !libraryManager.pinnedItems.isEmpty else { return }
        
        // Create a single batch query for all library pinned items
        let pinnedItemCounts = await libraryManager.getTrackCountForPinnedItems(libraryManager.pinnedItems)
        
        // Update the UI on main thread
        await MainActor.run {
            for (pinnedId, trackCount) in pinnedItemCounts where pinnedItemTrackCounts[pinnedId] != trackCount {
                pinnedItemTrackCounts[pinnedId] = trackCount
                
                // Update the corresponding item in allItems
                if let index = allItems.firstIndex(where: {
                    if case .pinned(let item) = $0.source {
                        return item.id == pinnedId
                    }
                    return false
                }) {
                    if let pinnedItem = libraryManager.pinnedItems.first(where: { $0.id == pinnedId }) {
                        let playlist = pinnedItem.playlistId.flatMap { id in
                            playlistManager.playlists.first { $0.id == id }
                        }
                        allItems[index] = HomeSidebarItem(pinnedItem: pinnedItem, trackCount: trackCount, playlist: playlist)
                    }
                }
            }
        }
    }

    // MARK: - Context Menu & Trailing Content

    private func createContextMenuItems(for item: HomeSidebarItem) -> [ContextMenuItem] {
        guard case .pinned(let pinnedItem) = item.source else { return [] }

        // Pinned playlist: show the full playlist options menu, identical to the Playlist
        // sidebar's. (The Pin entry reads "Remove from Home" since it's already pinned.)
        if let playlist = playlist(for: item) {
            return PlaylistMenuBuilder.items(for: playlist, playlistManager: playlistManager) {
                playlistToDelete = playlist
                showingDeleteConfirmation = true
            }
        }

        // Pinned library item (artist/album/etc.): just unpin.
        return [
            .button(title: String(localized: "Remove from Home"), role: nil) {
                Task {
                    await libraryManager.removePinnedItem(pinnedItem)
                }
            }
        ]
    }

    /// Resolves the underlying playlist for a pinned playlist item, if any.
    private func playlist(for item: HomeSidebarItem) -> Playlist? {
        guard case .pinned(let pinnedItem) = item.source,
              let playlistId = pinnedItem.playlistId else { return nil }
        return playlistManager.playlists.first { $0.id == playlistId }
    }

    private func trailingContentView(for item: HomeSidebarItem) -> AnyView {
        if case .pinned(let pinnedItem) = item.source {
            return AnyView(
                Button(action: {
                    Task {
                        await libraryManager.removePinnedItem(pinnedItem)
                    }
                }, label: {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundColor(selectedItem?.id == item.id ? .white.opacity(0.8) : .secondary)
                })
                .buttonStyle(.plain)
                .help("Remove from Home")
            )
        }
        return AnyView(EmptyView())
    }

    // MARK: - Reorder Pinned Items

    private func handlePinnedItemsReorder(_ reorderedItems: [HomeSidebarItem]) {
        let fixedItemCount = libraryManager.hasLocalMusic ? HomeSidebarItem.HomeItemType.allCases.count : 1
        let visiblePinned = reorderedItems.dropFirst(fixedItemCount).compactMap { item -> PinnedItem? in
            if case .pinned(let pinnedItem) = item.source {
                return pinnedItem
            }
            return nil
        }
        let visibleIds = Set(visiblePinned.compactMap(\.id))
        var iterator = visiblePinned.makeIterator()
        let reorderedPinned = libraryManager.pinnedItems.map { item in
            guard let id = item.id, visibleIds.contains(id) else { return item }
            return iterator.next() ?? item
        }

        allItems = reorderedItems

        Task {
            await libraryManager.reorderPinnedItems(reorderedPinned)
        }
    }

    private func restoreSelection(defaultType: HomeSidebarItem.HomeItemType) {
        if let currentId = selectedItem?.id,
           let matching = allItems.first(where: { $0.id == currentId }) {
            selectedItem = matching
        } else {
            selectedItem = allItems.first { $0.type == defaultType } ?? allItems.first
        }
    }
}

#Preview {
    @Previewable @State var selectedItem: HomeSidebarItem?

    HomeSidebarView(selectedItem: $selectedItem)
        .environmentObject(LibraryManager())
        .environmentObject(PlaylistManager())
        .frame(width: 250, height: 500)
}
