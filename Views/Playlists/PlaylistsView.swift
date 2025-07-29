import SwiftUI

struct PlaylistsView: View {
    let viewType: LibraryViewType

    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var selectedPlaylist: Playlist?

    @AppStorage("sidebarSplitPosition")
    private var splitPosition: Double = 200

    var body: some View {
        if libraryManager.folders.isEmpty {
            // Show unified empty state when no music exists
            NoMusicEmptyStateView(context: .mainWindow)
        } else {
            PersistentSplitView(
                left: {
                    PlaylistSidebarView(selectedPlaylist: $selectedPlaylist)
                },
                main: {
                    VStack(spacing: 0) {
                        if let playlist = selectedPlaylist {
                            PlaylistDetailView(playlistID: playlist.id, viewType: viewType)
                        } else {
                            emptySelectionView
                        }
                    }
                }
            )
            .onAppear {
                // Select first playlist by default if none selected
                if selectedPlaylist == nil && !playlistManager.playlists.isEmpty {
                    selectedPlaylist = playlistManager.playlists.first
                }
            }
            .onChange(of: playlistManager.playlists.count) {
                // Update selection if current playlist was removed
                if let selected = selectedPlaylist,
                   !playlistManager.playlists.contains(where: { $0.id == selected.id }) {
                    selectedPlaylist = playlistManager.playlists.first
                }
            }
        }
    }

    // MARK: - Empty Selection View

    private var emptySelectionView: some View {
        VStack(spacing: 20) {
            Image(systemName: Icons.musicNoteList)
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("Select a Playlist")
                .font(.headline)

            Text("Choose a playlist from the sidebar to view its contents")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

#Preview("List View") {
    PlaylistsView(viewType: .list)
        .environmentObject({
            let manager = PlaylistManager()
            return manager
        }())
        .environmentObject({
            let coordinator = AppCoordinator()
            return coordinator.playbackManager
        }())
        .environmentObject(LibraryManager())
        .frame(width: 800, height: 600)
}

#Preview("Grid View") {
    PlaylistsView(viewType: .grid)
        .environmentObject({
            let manager = PlaylistManager()
            return manager
        }())
        .environmentObject({
            let coordinator = AppCoordinator()
            return coordinator.playbackManager
        }())
        .environmentObject(LibraryManager())
        .frame(width: 800, height: 600)
}
