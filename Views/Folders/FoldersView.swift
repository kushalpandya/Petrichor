import SwiftUI
import Foundation

struct FoldersView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @State private var selectedFolderNode: FolderNode?
    @State private var selectedTrackID: UUID?
    @State private var showingRemoveFolderAlert = false
    @State private var folderTracks: [Track] = []
    @State private var isLoadingTracks = false
    @State private var showingCreatePlaylistWithTrack = false
    @State private var trackToAddToNewPlaylist: Track?
    @State private var newPlaylistName = ""

    @AppStorage("trackListSortAscending")
    private var trackListSortAscending: Bool = true

    let viewType: LibraryViewType

    var body: some View {
        if libraryManager.folders.isEmpty {
            // Show unified empty state when no folders exist
            NoMusicEmptyStateView(context: .mainWindow)
        } else {
            PersistentSplitView(
                left: {
                    foldersSidebar
                },
                main: {
                    folderTracksView
                }
            )
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

    // MARK: - Folders Sidebar

    private var foldersSidebar: some View {
        FoldersSidebarView(selectedNode: $selectedFolderNode)
            .onAppear {
                handleHierarchicalSidebarAppear()
            }
            .onChange(of: selectedFolderNode) { _, newNode in
                handleFolderNodeSelection(newNode)
            }
            .onChange(of: trackListSortAscending) {
                // Re-sort the current folder tracks when sort direction changes
                if let node = selectedFolderNode {
                    loadTracksForFolderNode(node)
                }
            }
    }

    // MARK: - Folder Tracks View

    private var folderTracksView: some View {
        VStack(alignment: .leading, spacing: 0) {
            folderTracksHeader

            Divider()

            folderTracksContent
        }
    }

    @ViewBuilder
    private var folderTracksHeader: some View {
        if let node = selectedFolderNode {
            if viewType == .table {
                TrackListHeader(
                    title: node.name,
                    trackCount: folderTracks.count
                ) {
                    EmptyView()
                }
            } else {
                TrackListHeader(
                    title: node.name,
                    trackCount: folderTracks.count
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
        } else {
            TrackListHeader(title: "Select a Folder", trackCount: 0)
        }
    }

    private var folderTracksContent: some View {
        Group {
            if selectedFolderNode == nil {
                noFolderSelectedView
            } else if isLoadingTracks {
                ProgressView("Loading tracks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if folderTracks.isEmpty {
                emptyFolderView
            } else {
                trackListView
            }
        }
    }

    // MARK: - Content Views

    private var loadingTracksView: some View {
        ProgressView("Loading tracks...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFolderView: some View {
        VStack(spacing: 16) {
            Image(systemName: Icons.musicNoteList)
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("No Music Files")
                .font(.headline)

            Text("No playable music files found in this folder")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var trackListView: some View {
        TrackView(
            tracks: folderTracks,
            viewType: viewType,
            selectedTrackID: $selectedTrackID,
            playlistID: nil,
            onPlayTrack: { track in
                if selectedFolderNode != nil {
                    // For hierarchical view, we need to play from the track list
                    playlistManager.playTrack(track, fromTracks: folderTracks)
                    selectedTrackID = track.id
                }
            },
            contextMenuItems: { track in
                if let node = selectedFolderNode {
                    // Create context menu items for folder node
                    if let dbFolder = node.databaseFolder {
                        return TrackContextMenu.createMenuItems(
                            for: track,
                            playbackManager: playbackManager,
                            playlistManager: playlistManager,
                            currentContext: .folder(dbFolder)
                        )
                    } else {
                        // For sub-folders, use library context
                        return TrackContextMenu.createMenuItems(
                            for: track,
                            playbackManager: playbackManager,
                            playlistManager: playlistManager,
                            currentContext: .library
                        )
                    }
                } else {
                    return []
                }
            }
        )
    }

    private var noFolderSelectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: Icons.folder)
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("Select a Folder")
                .font(.headline)

            Text("Choose a folder from the list to view its music files")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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

    // MARK: - Helper Methods

    private func refreshFolder(_ folder: Folder) {
        libraryManager.refreshFolder(folder)
    }

    // MARK: - Hierarchical Sidebar Helper Methods

    private func handleHierarchicalSidebarAppear() {
        // Select first folder node if none selected
        // This will be handled by HierarchicalFolderSidebarView itself
    }

    private func handleFolderNodeSelection(_ node: FolderNode?) {
        guard let node = node else {
            folderTracks = []
            return
        }

        loadTracksForFolderNode(node)
    }

    private func loadTracksForFolderNode(_ node: FolderNode) {
        isLoadingTracks = true

        // Get immediate tracks for this folder node
        let tracks = node.getImmediateTracks(using: libraryManager)

        // Sort tracks based on current sort direction
        let sortedTracks = tracks.sorted { track1, track2 in
            let comparison = track1.title.localizedCaseInsensitiveCompare(track2.title)
            return trackListSortAscending ?
                comparison == .orderedAscending :
                comparison == .orderedDescending
        }

        DispatchQueue.main.async {
            self.folderTracks = sortedTracks
            self.isLoadingTracks = false
        }
    }
}

#Preview {
    FoldersView(viewType: .list)
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
        .frame(width: 800, height: 600)
}
