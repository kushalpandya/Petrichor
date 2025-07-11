import SwiftUI

struct EntityDetailView: View {
    @AppStorage("trackListSortAscending")
    private var trackListSortAscending = true

    let entity: any Entity
    let viewType: LibraryViewType
    let onBack: (() -> Void)?
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var tracks: [Track] = []
    @State private var selectedTrackID: UUID?
    @State private var isLoading = true
    @State private var isBackButtonHovered = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            entityHeader
            
            Divider()
            
            // Track list
            if isLoading {
                loadingView
            } else if tracks.isEmpty {
                emptyView
            } else {
                TrackView(
                    tracks: sortedTracks,
                    viewType: viewType,
                    selectedTrackID: $selectedTrackID,
                    playlistID: nil,
                    onPlayTrack: { track in
                        playTrack(track)
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
        .onAppear {
            loadTracks()
        }
    }
    
    // MARK: - Header
    
    private var entityHeader: some View {
        PlaylistHeader {
            HStack(alignment: .top, spacing: 20) {
                // Back button
                if let onBack = onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isBackButtonHovered ? Color(NSColor.controlAccentColor).opacity(0.15) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        isBackButtonHovered ? Color(NSColor.controlAccentColor).opacity(0.3) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isBackButtonHovered = hovering
                    }
                    .help("Back to all \(entity is ArtistEntity ? "artists" : "albums")")
                }
                
                // Artwork
                entityArtwork
                
                // Info and controls
                VStack(alignment: .leading, spacing: 12) {
                    entityInfo
                    entityControls
                }
                
                Spacer()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 12) {
                // Sort button for list/grid views
                if viewType != .table {
                    Button(action: { trackListSortAscending.toggle() }) {
                        Image(Icons.sortIcon(for: trackListSortAscending))
                            .renderingMode(.template)
                            .scaleEffect(0.8)
                    }
                    .buttonStyle(.borderless)
                    .help("Sort tracks \(trackListSortAscending ? "descending" : "ascending")")
                }
            }
            .padding([.bottom, .trailing], 12)
        }
    }
    
    private var sortedTracks: [Track] {
        trackListSortAscending
            ? tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            : tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
    }
    
    private var entityArtwork: some View {
        Group {
            if let artworkData = entity.artworkData,
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
                        Image(systemName: entity is ArtistEntity ? Icons.personFill : Icons.opticalDiscFill)
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    )
            }
        }
    }
    
    private var entityInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entity is ArtistEntity ? "Artist" : "Album")
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            
            Text(entity.name)
                .font(.title)
                .fontWeight(.bold)
                .lineLimit(2)
            
            HStack {
                if let albumEntity = entity as? AlbumEntity,
                   let year = albumEntity.year {
                    Text(year)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("\(tracks.count) \(tracks.count == 1 ? "song" : "songs")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if !tracks.isEmpty {
                    Text("•")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(formattedTotalDuration)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var entityControls: some View {
        let buttonWidth: CGFloat = 90
        let verticalPadding: CGFloat = 6
        let iconSize: CGFloat = 12
        let textSize: CGFloat = 13
        let buttonSpacing: CGFloat = 10
        let iconTextSpacing: CGFloat = 4
        
        return HStack(spacing: buttonSpacing) {
            Button(action: pinEntity) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: iconSize))
                    .padding(.vertical, verticalPadding)
                    .padding(.horizontal, verticalPadding)
            }
            .buttonStyle(.bordered)
            .help(isPinned ? "Remove from Home" : "Pin to Home")
            
            Button(action: playEntity) {
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
            .disabled(tracks.isEmpty)
            
            Button(action: shuffleEntity) {
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
            .disabled(tracks.isEmpty)
        }
    }
    
    // MARK: - Views
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading tracks...")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: entity is ArtistEntity ? "person.slash" : "opticaldisc.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No tracks found")
                .font(.headline)
            
            Text("No tracks were found for this \(entity is ArtistEntity ? "artist" : "album")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Computed Properties
    
    private var formattedTotalDuration: String {
        let totalSeconds = tracks.reduce(0) { $0 + $1.duration }
        
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }
    
    private var isPinned: Bool {
        if let artist = entity as? ArtistEntity {
            return libraryManager.isEntityPinned(artist)
        } else if let album = entity as? AlbumEntity {
            return libraryManager.isEntityPinned(album)
        }
        return false
    }
    
    // MARK: - Methods
    
    private func loadTracks() {
        Task {
            await MainActor.run {
                isLoading = true
            }
            
            // Fetch tracks based on entity type
            let fetchedTracks: [Track]
            if entity is ArtistEntity {
                fetchedTracks = libraryManager.databaseManager.getTracksForArtistEntity(entity.name)
            } else if let albumEntity = entity as? AlbumEntity {
                // Pass the entire album entity instead of just name and artist
                fetchedTracks = libraryManager.databaseManager.getTracksForAlbumEntity(albumEntity)
            } else {
                fetchedTracks = []
            }
            
            await MainActor.run {
                self.tracks = fetchedTracks
                self.isLoading = false
            }
        }
    }
    
    private func pinEntity() {
        Task {
            if isPinned {
                await libraryManager.unpinEntity(entity)
            } else {
                if let artist = entity as? ArtistEntity {
                    await libraryManager.pinArtistEntity(artist)
                } else if let album = entity as? AlbumEntity {
                    await libraryManager.pinAlbumEntity(album)
                }
            }
        }
    }
    
    private func playTrack(_ track: Track) {
        // Use the playTrack method with context tracks
        playlistManager.playTrack(track, fromTracks: sortedTracks)
        selectedTrackID = track.id
    }

    private func playEntity() {
        guard !sortedTracks.isEmpty else { return }
        // Play the first track with all tracks as context
        playlistManager.playTrack(sortedTracks[0], fromTracks: sortedTracks)
        selectedTrackID = sortedTracks[0].id
    }

    private func shuffleEntity() {
        guard !sortedTracks.isEmpty else { return }
        // Enable shuffle first
        if !playlistManager.isShuffleEnabled {
            playlistManager.toggleShuffle()
        }
        // Play the first track with all tracks as context
        playlistManager.playTrack(sortedTracks[0], fromTracks: sortedTracks)
        // The selected track ID should be the first track in the shuffled queue
        if let firstTrack = playlistManager.currentQueue.first {
            selectedTrackID = firstTrack.id
        }
    }
}

// MARK: - Preview

#Preview("Artist Detail") {
    let artist = ArtistEntity(name: "Test Artist", trackCount: 10)
    
    return EntityDetailView(
        entity: artist,
        viewType: .list
    ) { Logger.debugPrint("Back tapped") }
    .environmentObject(LibraryManager())
    .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
    .environmentObject(PlaylistManager())
    .frame(height: 600)
}

#Preview("Album Detail") {
    let album = AlbumEntity(name: "The Dark Side of the Moon", trackCount: 10, year: "1973", duration: 2580)
    
    return EntityDetailView(
        entity: album,
        viewType: .grid
    ) { Logger.debugPrint("Back tapped") }
    .environmentObject(LibraryManager())
    .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
    .environmentObject(PlaylistManager())
    .frame(height: 600)
}
