import SwiftUI

struct EntityDetailView: View {
    let entity: any Entity
    let onBack: (() -> Void)?
    
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var tracks: [Track] = []
    @State private var selectedTrackID: UUID?
    @State private var isLoading = true
    @State private var isBackButtonHovered = false
    @State private var isArtworkHovered = false
    @State private var showingImagePicker = false
    @State private var overrideArtworkData: Data?
    @State private var artworkDeleted = false
    @State private var artistBio: String?
    @State private var gradientColors: [Color] = []

    @AppStorage("useArtworkColors")
    private var useArtworkColors = true

    @AppStorage("trackTableRowSize")
    private var trackTableRowSize: TableRowSize = .expanded

    @Environment(\.colorScheme) var colorScheme

    @State private var trackTableSortOrder = [KeyPathComparator(\Track.title)]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            entityHeader
            
            // Track list
            if isLoading {
                loadingView
            } else if tracks.isEmpty {
                emptyView
            } else {
                TrackView(
                    tracks: tracks,
                    selectedTrackID: $selectedTrackID,
                    playlistID: nil,
                    entityID: entity is ArtistEntity ? nil : entity.id,
                    sortOrder: $trackTableSortOrder,
                    onPlayTrack: { track in
                        playTrack(track)
                    },
                    contextMenuItems: { track, playbackManager in
                        TrackContextMenu.createMenuItems(
                            for: track,
                            playbackManager: playbackManager,
                            playlistManager: playlistManager,
                            currentContext: .library
                        )
                    }
                )
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadTracks()
            updateGradientColors()
        }
        .onChange(of: entity.id) { oldValue, newValue in
            if oldValue != newValue {
                loadTracks()
                updateGradientColors()
            }
        }
        .onChange(of: colorScheme) {
            updateGradientColors()
        }
        .onChange(of: useArtworkColors) {
            updateGradientColors()
        }
    }

    // MARK: - Header
    
    private var entityHeader: some View {
        EntityHeader {
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
                    if entity is ArtistEntity {
                        artistEntityInfo
                    } else {
                        albumEntityInfo
                    }

                    entityControls
                }
                .frame(maxHeight: 120)

                Spacer()
            }
        }
        .background {
            if !gradientColors.isEmpty {
                GradientBackground(colors: gradientColors)
                    .animation(
                        .easeInOut(duration: AnimationDuration.standardDuration),
                        value: gradientColors
                    )
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 12) {
                TrackTableOptionsDropdown(
                    sortOrder: $trackTableSortOrder,
                    tableRowSize: $trackTableRowSize
                )
            }
            .padding([.bottom, .trailing], 12)
        }
    }
    
    private var displayedArtworkData: Data? {
        if artworkDeleted { return nil }
        return overrideArtworkData ?? entity.artworkData
    }

    private var entityArtwork: some View {
        Group {
            if let artworkData = displayedArtworkData,
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
                        Group {
                            if entity is ArtistEntity {
                                Text(entity.name.artistInitials)
                                    .font(.system(size: 36, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: Icons.opticalDiscFill)
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if entity is ArtistEntity {
                showingImagePicker = true
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if entity is ArtistEntity {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .opacity(isArtworkHovered ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isArtworkHovered)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            isArtworkHovered = hovering
        }
        .sheet(isPresented: $showingImagePicker) {
            ArtistImageSheet(
                artistName: entity.name,
                artistId: libraryManager.databaseManager.getArtistId(for: entity.name),
                isPresented: $showingImagePicker
            ) { newImageData in
                if let newImageData {
                    overrideArtworkData = newImageData
                    artworkDeleted = false
                } else {
                    overrideArtworkData = nil
                    artworkDeleted = true
                }
                updateGradientColors()
            }
        }
    }
    
    private var artistEntityInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Artist")
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)

            Text(entity.name)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(1)

            if let bio = artistBio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .help(bio)
            }

            HStack {
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

    private var albumEntityInfo: some View {
        let albumEntity = entity as? AlbumEntity
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(entity.name)
                .font(.title)
                .fontWeight(.bold)
                .lineLimit(2)
            
            if let artistName = albumEntity?.artistName, !artistName.isEmpty {
                Text(artistName)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            HStack {
                if let year = albumEntity?.year {
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
                    
                    if isAlbumFullyLossless {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            Image(Icons.customLossless)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 15, height: 15)
                            
                            Text("Lossless")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
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
            
            Button(action: { playEntity() }) {
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
            
            Button(action: { playEntity(shuffle: true) }) {
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
    
    private var isAlbumFullyLossless: Bool {
        guard entity is AlbumEntity, !tracks.isEmpty else { return false }
        return tracks.allSatisfy { $0.lossless == true }
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

    private func updateGradientColors() {
        guard useArtworkColors else {
            gradientColors = []
            return
        }

        // Use override artwork for gradient if available (e.g., after image picker save)
        if let overrideData = overrideArtworkData {
            let colors = ImageUtils.extractDominantColors(from: overrideData)
            gradientColors = ImageUtils.backgroundGradientColors(from: colors, isDark: colorScheme == .dark)
        } else if let album = entity as? AlbumEntity {
            gradientColors = album.backgroundGradientColors(isDark: colorScheme == .dark)
        } else if let artist = entity as? ArtistEntity {
            gradientColors = artist.backgroundGradientColors(isDark: colorScheme == .dark)
        } else {
            gradientColors = []
        }
    }

    private func loadTracks() {
        isLoading = true
        
        let fetchedTracks: [Track]
        if entity is ArtistEntity {
            fetchedTracks = libraryManager.databaseManager.getTracksForArtistEntity(entity.name)
        } else if let albumEntity = entity as? AlbumEntity {
            fetchedTracks = libraryManager.databaseManager.getTracksForAlbumEntity(albumEntity)
        } else {
            fetchedTracks = []
        }
        
        self.tracks = fetchedTracks
        
        // Sort album tracks by disc/track number by default if those values exist
        if entity is AlbumEntity {
            let hasCompleteOrdering = fetchedTracks.allSatisfy { $0.trackNumber != nil && $0.trackNumber! > 0 }
            
            if hasCompleteOrdering {
                trackTableSortOrder = [
                    KeyPathComparator(\Track.sortableDiscNumber, order: .forward),
                    KeyPathComparator(\Track.sortableTrackNumber, order: .forward)
                ]
            }
        }
        
        // Load artist bio
        if entity is ArtistEntity {
            artistBio = libraryManager.databaseManager.getArtistBio(for: entity.name)
        }

        self.isLoading = false
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
        playlistManager.playTrack(track, fromTracks: tracks)
        selectedTrackID = track.id
    }

    private func playEntity(shuffle: Bool = false) {
        guard !tracks.isEmpty else { return }
        
        NotificationCenter.default.post(
            name: .playEntityTracks,
            object: entity,
            userInfo: [
                "shuffle": shuffle,
                "entityId": entity.id.uuidString
            ]
        )
    }
}

// MARK: - Preview

#Preview("Artist Detail") {
    let artist = ArtistEntity(name: "Test Artist", trackCount: 10)
    
    return EntityDetailView(
        entity: artist,
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
    ) { Logger.debugPrint("Back tapped") }
    .environmentObject(LibraryManager())
    .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
    .environmentObject(PlaylistManager())
    .frame(height: 600)
}
