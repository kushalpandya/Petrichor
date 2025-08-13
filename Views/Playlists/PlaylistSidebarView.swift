import SwiftUI

struct PlaylistSidebarView: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    @Binding var selectedPlaylist: Playlist?
    @State private var showingCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var selectedSidebarItem: PlaylistSidebarItem?
    @State private var playlistToDelete: Playlist?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            Divider()

            playlistsList
        }
        .sheet(isPresented: $showingCreatePlaylist) {
            createPlaylistSheet
        }
        .alert("Delete Playlist", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                playlistToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let playlist = playlistToDelete {
                    playlistManager.deletePlaylist(playlist)
                    if selectedPlaylist?.id == playlist.id {
                        selectedPlaylist = nil
                    }
                    playlistToDelete = nil
                }
            }
        } message: {
            if let playlist = playlistToDelete {
                Text("Are you sure you want to delete \"\(playlist.name)\"? This action cannot be undone.")
            }
        }
        .onAppear {
            updateSelectedSidebarItem()
        }
        .onChange(of: selectedPlaylist) {
            updateSelectedSidebarItem()
        }
    }

    // MARK: - Update Selection Helper

    private func updateSelectedSidebarItem() {
        if let playlist = selectedPlaylist {
            selectedSidebarItem = PlaylistSidebarItem(playlist: playlist)
        }
    }

    // MARK: - Sidebar Header

    private var sidebarHeader: some View {
        ListHeader {
            Text("Playlists")
                .headerTitleStyle()

            Spacer()

            Button(action: { showingCreatePlaylist = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .hoverEffect(scale: 1.1)
            .help("Create New Playlist")
        }
    }

    // MARK: - Playlists List

    private var playlistsList: some View {
        SidebarView(
            items: allPlaylistItems,
            selectedItem: $selectedSidebarItem,
            onItemTap: { item in
                selectedPlaylist = item.playlist
            },
            contextMenuItems: { item in
                createContextMenuItems(for: item.playlist)
            },
            onRename: { item, newName in
                playlistManager.renamePlaylist(item.playlist, newName: newName)
            },
            showIcon: true,
            iconColor: .secondary,
            showCount: false
        )
    }

    private var allPlaylistItems: [PlaylistSidebarItem] {
        playlistManager.playlists.map { PlaylistSidebarItem(playlist: $0) }
    }

    // MARK: - Context Menu

    private func createContextMenuItems(for playlist: Playlist) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        
        // Add pin/unpin option
        items.append(playlistManager.createPinContextMenuItem(for: playlist))
        
        if playlist.isUserEditable {
            items.append(.divider)
            items.append(.button(title: "Rename") {})
            items.append(.divider)
            items.append(.button(title: "Delete", role: .destructive) {
                playlistToDelete = playlist
                showingDeleteConfirmation = true
            })
        }
        
        return items
    }

    // MARK: - Create Playlist Sheet

    private var createPlaylistSheet: some View {
        CreatePlaylistSheet(
            isPresented: $showingCreatePlaylist,
            playlistName: $newPlaylistName,
            trackToAdd: nil
        ) {
            createPlaylist()
        }
        .environmentObject(playlistManager)
    }

    private func createPlaylist() {
        if !newPlaylistName.isEmpty {
            let newPlaylist = playlistManager.createPlaylist(name: newPlaylistName)
            selectedPlaylist = newPlaylist
            newPlaylistName = ""
            showingCreatePlaylist = false
        }
    }
}

// MARK: - Preview

#Preview("Playlist Sidebar") {
    @Previewable @State var selectedPlaylist: Playlist?

    let previewManager = {
        let manager = PlaylistManager()

        // Create sample playlists using the new criteria-based approach
        let smartPlaylists = [
            Playlist(
                name: DefaultPlaylists.favorites,
                criteria: SmartPlaylistCriteria(
                    rules: [SmartPlaylistCriteria.Rule(
                        field: "isFavorite",
                        condition: .equals,
                        value: "true"
                    )],
                    sortBy: "title",
                    sortAscending: true
                ),
                isUserEditable: false
            ),
            Playlist(
                name: DefaultPlaylists.mostPlayed,
                criteria: SmartPlaylistCriteria(
                    rules: [SmartPlaylistCriteria.Rule(
                        field: "playCount",
                        condition: .greaterThan,
                        value: "5"
                    )],
                    limit: 25,
                    sortBy: "playCount",
                    sortAscending: false
                ),
                isUserEditable: false
            ),
            Playlist(
                name: DefaultPlaylists.recentlyPlayed,
                criteria: SmartPlaylistCriteria(
                    rules: [SmartPlaylistCriteria.Rule(
                        field: "lastPlayedDate",
                        condition: .greaterThan,
                        value: "7days"
                    )],
                    limit: 25,
                    sortBy: "lastPlayedDate",
                    sortAscending: false
                ),
                isUserEditable: false
            )
        ]

        // Create sample tracks for regular playlists
        var sampleTrack1 = Track(url: URL(fileURLWithPath: "/sample1.mp3"))
        sampleTrack1.title = "Sample Song 1"
        sampleTrack1.artist = "Artist 1"

        var sampleTrack2 = Track(url: URL(fileURLWithPath: "/sample2.mp3"))
        sampleTrack2.title = "Sample Song 2"
        sampleTrack2.artist = "Artist 2"

        let regularPlaylists = [
            Playlist(name: "My Favorites", tracks: [sampleTrack1, sampleTrack2]),
            Playlist(name: "Workout Mix", tracks: [sampleTrack1]),
            Playlist(name: "Relaxing Music", tracks: [])
        ]

        manager.playlists = smartPlaylists + regularPlaylists
        return manager
    }()

    PlaylistSidebarView(selectedPlaylist: $selectedPlaylist)
        .environmentObject(previewManager)
        .frame(width: 250, height: 500)
}

#Preview("Empty Sidebar") {
    @Previewable @State var selectedPlaylist: Playlist?

    let emptyManager = PlaylistManager()

    return PlaylistSidebarView(selectedPlaylist: $selectedPlaylist)
        .environmentObject(emptyManager)
        .frame(width: 250, height: 500)
}
