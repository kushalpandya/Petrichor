import SwiftUI

struct EntityDetailView: View {
    let entity: any Entity
    let onBack: (() -> Void)?
    let pinnedItem: PinnedItem?

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

    init(entity: any Entity, onBack: (() -> Void)? = nil, pinnedItem: PinnedItem? = nil) {
        self.entity = entity
        self.onBack = onBack
        self.pinnedItem = pinnedItem
    }

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
                    entityID: entity.id,
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
                    if #available(macOS 26.0, *) {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.small)
                        .help("Back")
                    } else {
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
                        .help("Back")
                    }
                }

                // Artwork
                entityArtwork

                // Info and controls
                VStack(alignment: .leading, spacing: 12) {
                    if entity is AlbumEntity {
                        albumEntityInfo
                    } else {
                        artistEntityInfo
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
                    .transaction { $0.animation = nil }
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

    private var isPersonEntity: Bool {
        entity is ArtistEntity
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
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Group {
                            if isPersonEntity {
                                Text(entity.name.artistInitials)
                                    .font(.system(size: 36, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            } else if entity is CategoryEntity {
                                Text(entity.name)
                                    .font(.system(size: entity.name.count <= 5 ? 28 : 16, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(8)
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
            if isPersonEntity {
                showingImagePicker = true
            }
        }
        .overlay {
            if isPersonEntity {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 120, height: 120)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 20, weight: .medium))
                            Text("Update image")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.white)
                    )
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
    
    private var entityTypeLabel: String {
        if let category = entity as? CategoryEntity {
            return category.filterType.singularDisplayName
        }
        switch pinnedItem?.filterType {
        case .albumArtists: return "Album Artist"
        case .composers: return "Composer"
        default: return "Artist"
        }
    }

    private var artistEntityInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entityTypeLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)

            Text(entity.name)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(2)

            if let bio = artistBio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .help(bio)
            }

            trackStats()
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

            trackStats {
                if let year = albumEntity?.year {
                    statText(year)
                    statDot
                }
            } trailing: {
                if isAlbumFullyLossless {
                    statDot
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

    // Shared track count + duration stats line
    private func trackStats<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack {
            leading()
            statText("\(tracks.count) \(tracks.count == 1 ? "song" : "songs")")
            if !tracks.isEmpty {
                statDot
                statText(formattedTotalDuration)
                trailing()
            }
        }
    }

    private func statText(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundColor(.secondary)
    }

    private var statDot: some View {
        Text("•").font(.subheadline).foregroundColor(.secondary)
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
                    .foregroundStyle(.secondary)
                    .padding(.vertical, verticalPadding)
                    .padding(.horizontal, verticalPadding)
            }
            .adaptiveCircularButtonStyle()
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
            .adaptiveButtonStyle(prominent: true)
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
            .adaptiveButtonStyle()
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
    
    private var emptyViewIcon: String {
        if entity is ArtistEntity { return "person.slash" }
        if entity is CategoryEntity { return "music.note.slash" }
        return "opticaldisc.slash"
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: emptyViewIcon)
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No tracks found")
                .font(.headline)

            Text("No tracks were found for \(entity.name)")
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
        if let category = entity as? CategoryEntity {
            return libraryManager.isLibraryItemPinned(filterType: category.filterType, filterValue: category.name)
        } else if let artist = entity as? ArtistEntity {
            if let pinnedItem = pinnedItem {
                return libraryManager.isLibraryItemPinned(
                    filterType: pinnedItem.filterType ?? .artists,
                    filterValue: entity.name
                )
            }
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

        if let overrideData = overrideArtworkData {
            let colors = ImageUtils.extractDominantColors(from: overrideData)
            gradientColors = ImageUtils.backgroundGradientColors(from: colors, isDark: colorScheme == .dark)
        } else {
            gradientColors = entity.backgroundGradientColors(isDark: colorScheme == .dark)
        }
    }

    private func loadTracks() {
        isLoading = true

        let fetchedTracks: [Track]

        // When pinnedItem is provided, use the unified pinned item track loader
        if let pinnedItem = pinnedItem {
            fetchedTracks = libraryManager.databaseManager.getTracksForPinnedItem(pinnedItem)
        } else if entity is ArtistEntity {
            fetchedTracks = libraryManager.databaseManager.getTracksForArtistEntity(entity.name)
        } else if let albumEntity = entity as? AlbumEntity {
            fetchedTracks = libraryManager.databaseManager.getTracksForAlbumEntity(albumEntity)
        } else {
            fetchedTracks = []
        }

        // Albums with full track numbering force disc/track ordering; everything
        // else follows the user's saved global sort.
        let hasCompleteAlbumOrdering = entity is AlbumEntity
            && fetchedTracks.allSatisfy { $0.trackNumber != nil && $0.trackNumber! > 0 }

        if hasCompleteAlbumOrdering {
            trackTableSortOrder = [
                KeyPathComparator(\Track.sortableDiscNumber, order: .forward),
                KeyPathComparator(\Track.sortableTrackNumber, order: .forward)
            ]
        } else if let savedSort = UserDefaults.standard.dictionary(forKey: "trackTableSortOrder"),
                  let key = savedSort["key"] as? String,
                  let ascending = savedSort["ascending"] as? Bool,
                  let field = TrackSortField.from(storageKey: key) {
            trackTableSortOrder = [field.getComparator(ascending: ascending)]
        }

        self.tracks = fetchedTracks

        // Load artist bio for person entities (artists, album artists, composers)
        if entity is ArtistEntity {
            artistBio = libraryManager.databaseManager.getArtistBio(for: entity.name)
        } else {
            artistBio = nil
        }

        self.isLoading = false
    }
    
    private func pinEntity() {
        Task {
            if let category = entity as? CategoryEntity {
                if isPinned {
                    await libraryManager.unpinLibraryItem(filterType: category.filterType, filterValue: category.name)
                } else {
                    await libraryManager.pinLibraryItem(filterType: category.filterType, filterValue: category.name)
                }
            } else if entity is ArtistEntity, let pinnedItem = pinnedItem,
                      let filterType = pinnedItem.filterType, filterType != .artists {
                // Album artist or composer pinned as ArtistEntity
                if isPinned {
                    await libraryManager.unpinLibraryItem(filterType: filterType, filterValue: entity.name)
                } else {
                    await libraryManager.pinLibraryItem(filterType: filterType, filterValue: entity.name)
                }
            } else if isPinned {
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
