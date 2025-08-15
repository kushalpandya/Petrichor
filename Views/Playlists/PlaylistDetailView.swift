import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: UUID
    let viewType: LibraryViewType

    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @StateObject private var playlistSortManager = PlaylistSortManager.shared
    @State private var selectedTrackID: UUID?
    @State private var showingAddSongs = false

    // Convenience initializer for when you have a Playlist object
    init(playlist: Playlist, viewType: LibraryViewType) {
        self.playlistID = playlist.id
        self.viewType = viewType
    }

    // Standard initializer with playlist ID
    init(playlistID: UUID, viewType: LibraryViewType) {
        self.playlistID = playlistID
        self.viewType = viewType
    }

    // Get the current playlist from the manager
    private var playlist: Playlist? {
        playlistManager.playlists.first { $0.id == playlistID }
    }

    var body: some View {
        if let playlist = playlist {
            VStack(spacing: 0) {
                playlistHeader

                Divider()

                playlistContent
            }
            .sheet(isPresented: $showingAddSongs) {
                AddSongsToPlaylistSheet(playlist: playlist)
            }
            .onChange(of: playlistID) {
                selectedTrackID = nil
            }
            .onChange(of: playlist.dateModified) {
                loadPlaylistTracksIfNeeded()
            }
            .onAppear {
                loadPlaylistTracksIfNeeded()
            }
            .onChange(of: playlist.id) {
                loadPlaylistTracksIfNeeded()
            }
        } else {
            playlistNotFoundView
        }
    }

    // MARK: - Playlist Header

    @ViewBuilder
    private var playlistHeader: some View {
        if playlist != nil {
            PlaylistHeader {
                HStack(alignment: .top, spacing: 20) {
                    playlistArtwork

                    VStack(alignment: .leading, spacing: 12) {
                        playlistInfo
                        playlistControls
                    }

                    Spacer()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 12) {
                    PlaylistSortDropdown(
                        playlistID: playlistID,
                        viewType: viewType
                    )
                }
                .padding([.bottom, .trailing], 12)
            }
        }
    }

    private var playlistArtwork: some View {
        Group {
            if let artworkData = playlist?.effectiveCoverArtwork,
               let nsImage = NSImage(data: artworkData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: playlistIcon)
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    )
            }
        }
    }

    private var playlistInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playlistTypeText)
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)

            Text(playlist?.name ?? "")
                .font(.title)
                .fontWeight(.bold)
                .lineLimit(2)

            if let playlist = playlist {
                HStack {
                    Text("\(playlist.trackCount) songs")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if playlist.trackCount > 0 {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(playlist.formattedTotalDuration)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var playlistControls: some View {
        let buttonWidth: CGFloat = 90
        let verticalPadding: CGFloat = 6
        let iconSize: CGFloat = 12
        let textSize: CGFloat = 13
        let buttonSpacing: CGFloat = 10
        let iconTextSpacing: CGFloat = 4

        return HStack(spacing: buttonSpacing) {
            Button(action: pinPlaylist) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: iconSize))
                    .padding(.vertical, verticalPadding)
                    .padding(.horizontal, verticalPadding)
            }
            .buttonStyle(.bordered)
            .help(isPinned ? "Remove from Home" : "Pin to Home")
            
            Button(action: { playPlaylist() }) {
                HStack(spacing: iconTextSpacing) {
                    Image(systemName: Icons.playFill)
                        .font(.system(size: iconSize))
                    Text("Play")
                        .font(.system(size: textSize, weight: .medium))
                }
                .frame(width: buttonWidth)
                .padding(.vertical, verticalPadding)
            }
            .buttonStyle(.borderedProminent)
            .disabled(playlist?.trackCount == 0)

            Button(action: { playPlaylist(shuffle: true) }) {
                HStack(spacing: iconTextSpacing) {
                    Image(systemName: Icons.shuffleFill)
                        .font(.system(size: iconSize))
                    Text("Shuffle")
                        .font(.system(size: textSize, weight: .medium))
                }
                .frame(width: buttonWidth)
                .padding(.vertical, verticalPadding)
            }
            .buttonStyle(.bordered)
            .disabled(playlist?.trackCount == 0)

            if playlist?.type == .regular {
                Button(action: { showingAddSongs = true }) {
                    HStack(spacing: iconTextSpacing) {
                        Image(systemName: Icons.plusCircle)
                            .font(.system(size: iconSize))
                        Text("Add Songs")
                            .font(.system(size: textSize, weight: .medium))
                    }
                    .frame(width: buttonWidth)
                    .padding(.vertical, verticalPadding)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Playlist Content

    private var playlistContent: some View {
        Group {
            if playlist?.tracks.isEmpty ?? true {
                emptyPlaylistView
            } else {
                TrackView(
                    tracks: sortedTracks,
                    viewType: viewType,
                    selectedTrackID: $selectedTrackID,
                    playlistID: playlistID,
                    onPlayTrack: { track in
                        if let playlist = playlist,
                           let index = playlist.tracks.firstIndex(of: track) {
                            playlistManager.playTrackFromPlaylist(playlist, at: index)
                            selectedTrackID = track.id
                        }
                    },
                    contextMenuItems: { track in
                        if let playlist = playlist {
                            return TrackContextMenu.createMenuItems(
                                for: track,
                                playbackManager: playbackManager,
                                playlistManager: playlistManager,
                                currentContext: .playlist(playlist)
                            )
                        } else {
                            return []
                        }
                    }
                )
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }

    // MARK: - Empty Playlist View

    @ViewBuilder
    private var emptyPlaylistView: some View {
        if let playlist = playlist {
            VStack(spacing: 20) {
                Image(systemName: playlistIcon)
                    .font(.system(size: 60))
                    .foregroundColor(.gray)

                Text(emptyStateTitle)
                    .font(.headline)

                Text(emptyStateMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                if playlist.type == .regular {
                    Button("Add Songs") {
                        showingAddSongs = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    // MARK: - Playlist Not Found View

    private var playlistNotFoundView: some View {
        VStack {
            Image(systemName: Icons.musicNoteList)
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("Playlist not found")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Helper Properties

    private var playlistIcon: String {
        guard let playlist = playlist else { return Icons.musicNoteList }

        return Icons.defaultPlaylistIcon(for: playlist)
    }

    private var playlistTypeText: String {
        guard let playlist = playlist else { return "" }

        switch playlist.type {
        case .smart:
            return "SMART PLAYLIST"
        case .regular:
            return "PLAYLIST"
        }
    }

    private var emptyStateTitle: String {
        guard let playlist = playlist else { return "Empty Playlist" }

        return DefaultPlaylists.noSongsText(for: playlist)
    }

    private var emptyStateMessage: String {
        guard let playlist = playlist else { return "" }
        
        return DefaultPlaylists.emptyStateText(for: playlist)
    }
    
    private var isPinned: Bool {
        playlistManager.isPlaylistPinned(playlist ?? Playlist(name: "", tracks: []))
    }
    
    private var sortedTracks: [Track] {
        guard let playlist = playlist else { return [] }
        
        let sortCriteria = playlistSortManager.getSortCriteria(for: playlistID)
        let isAscending = playlistSortManager.getSortAscending(for: playlistID)
        
        switch sortCriteria {
        case .dateAdded:
            // For date added, we need to maintain the playlist order
            // In ascending order, first added (position 0) comes first
            // In descending order, last added comes first
            return isAscending ? playlist.tracks : playlist.tracks.reversed()
            
        case .title:
            return playlist.tracks.sorted { track1, track2 in
                let comparison = track1.title.localizedCaseInsensitiveCompare(track2.title)
                return isAscending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
            
        case .custom:
            // For custom sorting (table view column sorting),
            // we'll handle this in the table view itself
            return playlist.tracks
        }
    }

    // MARK: - Action Methods
    
    private func loadPlaylistTracksIfNeeded() {
        guard let playlist = playlist else { return }
            
        if playlist.type == .smart && playlist.tracks.isEmpty {
            // Load smart playlist tracks using the optimized query
            Task {
                await playlistManager.loadSmartPlaylistTracks(playlist)
            }
        } else if playlist.type == .regular && playlist.tracks.isEmpty {
            // Load regular playlist tracks
            playlistManager.loadPlaylistTracks(for: playlist.id)
        }
    }

    private func playPlaylist(shuffle: Bool = false) {
        guard let playlist = playlist, !playlist.tracks.isEmpty else { return }
        guard !sortedTracks.isEmpty else { return }
        
        if viewType == .table {
            NotificationCenter.default.post(
                name: .playPlaylistTracks,
                object: nil,
                userInfo: ["playlistID": playlist.id, "shuffle": shuffle]
            )
        } else {
            playlistManager.isShuffleEnabled = shuffle
            
            var tracksForPlayback = sortedTracks
            if shuffle {
                tracksForPlayback.shuffle()
            }
            
            if let firstTrack = tracksForPlayback.first {
                playlistManager.playTrack(firstTrack, fromTracks: tracksForPlayback)
                playlistManager.currentPlaylist = playlist
                playlistManager.currentQueueSource = .playlist
            }
        }
    }
    
    private func pinPlaylist() {
        guard let playlist = playlist else { return }
        
        Task {
            if isPinned {
                await playlistManager.unpinPlaylist(playlist)
            } else {
                await playlistManager.pinPlaylist(playlist)
            }
        }
    }
}

// MARK: - Preview

#Preview("Regular Playlist") {
    let samplePlaylist = Playlist(name: "My Favorite Songs", tracks: [])

    return PlaylistDetailView(playlist: samplePlaylist, viewType: .list)
        .environmentObject({
            let manager = PlaylistManager()
            manager.playlists = [samplePlaylist]
            return manager
        }())
        .environmentObject({
            let coordinator = AppCoordinator()
            return coordinator.playbackManager
        }())
        .frame(height: 600)
}

#Preview("Smart Playlist") {
    let smartPlaylist = Playlist(
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
    )

    return PlaylistDetailView(playlist: smartPlaylist, viewType: .grid)
        .environmentObject({
            let manager = PlaylistManager()
            manager.playlists = [smartPlaylist]
            return manager
        }())
        .environmentObject({
            let coordinator = AppCoordinator()
            return coordinator.playbackManager
        }())
        .frame(height: 600)
}
