import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var selectedPlaylist: Playlist?

    @AppStorage("sidebarSplitPosition")
    private var splitPosition: Double = 200

    var body: some View {
        if !libraryManager.shouldShowMainUI {
            NoMusicEmptyStateView(context: .mainWindow)
        } else {
            PersistentSplitView(
                left: {
                    PlaylistSidebarView(selectedPlaylist: $selectedPlaylist)
                },
                main: {
                    VStack(spacing: 0) {
                        if let playlist = selectedPlaylist {
                            PlaylistDetailView(playlistID: playlist.id)
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
    }
}

#Preview("Playlist View") {
    PlaylistsView()
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
