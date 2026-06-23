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
                reorderableFromIndex: HomeSidebarItem.HomeItemType.allCases.count,
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
            updateSelectedItem()

            if !hasLoadedInitialCounts {
                hasLoadedInitialCounts = true
                Task {
                    await updatePinnedItemTrackCounts()
                }
            }
        }
        .onChange(of: libraryManager.tracks.count) {
            updateAllItems()
            updateSelectedItem()
        }
        .onChange(of: libraryManager.discoverTracks.count) {
            updateAllItems()
            updateSelectedItem()
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
        .onChange(of: pinnedPlaylistCountSignature) {
            // Only rebuild when a *pinned* playlist's count changes. Count changes on
            // non-pinned playlists don't affect anything shown in the Home sidebar.
            updateAllItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDataDidChange)) { _ in
            updateAllItems()
            updateSelectedItem()
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
        let artistCount = libraryManager.artistCount
        let albumCount = libraryManager.albumCount

        var items: [HomeSidebarItem] = [
            HomeSidebarItem(type: .discover, trackCount: libraryManager.discoverTracks.count),
            HomeSidebarItem(type: .tracks, trackCount: libraryManager.totalTrackCount),
            HomeSidebarItem(type: .artists, artistCount: artistCount),
            HomeSidebarItem(type: .albums, albumCount: albumCount)
        ]

        // O(1) playlist lookups instead of a linear scan per pinned item.
        let playlistsById = Dictionary(playlistManager.playlists.map { ($0.id, $0) }) { first, _ in first }
        let pinnedSidebarItems = libraryManager.pinnedItems.map { pinnedItem in
            let cachedCount = pinnedItemTrackCounts[pinnedItem.id ?? 0] ?? 0
            let playlist = pinnedItem.playlistId.flatMap { playlistsById[$0] }
            return HomeSidebarItem(pinnedItem: pinnedItem, trackCount: cachedCount, playlist: playlist)
        }
        items.append(contentsOf: pinnedSidebarItems)
        
        // Preserve selection when updating items
        let currentSelectionId = selectedItem?.id
        allItems = items
        
        // Restore selection if it still exists
        if let currentId = currentSelectionId,
           let matchingItem = allItems.first(where: { $0.id == currentId }) {
            selectedItem = matchingItem
        }
        
        // Update track counts asynchronously to avoid blocking UI
        Task {
            await updatePinnedItemTrackCounts()
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
        let fixedCount = HomeSidebarItem.HomeItemType.allCases.count
        let reorderedPinned = reorderedItems.dropFirst(fixedCount).compactMap { item -> PinnedItem? in
            if case .pinned(let pinnedItem) = item.source {
                return pinnedItem
            }
            return nil
        }

        allItems = reorderedItems

        Task {
            await libraryManager.reorderPinnedItems(reorderedPinned)
        }
    }

    // MARK: - Update Selection Helper

    private func updateSelectedItem() {
        // Select "Discover" by default if nothing is selected
        if selectedItem == nil {
            selectedItem = allItems.first { item in
                if case .fixed(let type) = item.source, type == .discover {
                    return true
                }
                return false
            } ?? allItems.first
        } else if let current = selectedItem {
            // Update the selected item to get the latest count for fixed items
            switch current.source {
            case .fixed(let type):
                selectedItem = allItems.first { item in
                    if case .fixed(let itemType) = item.source {
                        return itemType == type
                    }
                    return false
                }
            case .pinned:
                // Pinned items don't need updates
                break
            }
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
