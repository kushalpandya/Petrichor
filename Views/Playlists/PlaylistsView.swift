import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var libraryManager: LibraryManager
    @Binding var selectedPlaylist: Playlist?

    var body: some View {
        if !libraryManager.shouldShowMainUI {
            NoMusicEmptyStateView(context: .mainWindow)
        } else {
            VStack(spacing: 0) {
                if let playlist = selectedPlaylist {
                    PlaylistDetailView(playlistID: playlist.id)
                } else {
                    emptySelectionView
                }
            }
            .onAppear {
                if selectedPlaylist == nil && !playlistManager.playlists.isEmpty {
                    selectedPlaylist = playlistManager.playlists.first
                }
            }
            .onChange(of: playlistManager.playlists.count) {
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
    @Previewable @State var selectedPlaylist: Playlist?

    PlaylistsView(selectedPlaylist: $selectedPlaylist)
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
