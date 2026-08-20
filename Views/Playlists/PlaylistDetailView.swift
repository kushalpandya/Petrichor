import SwiftUI

// swiftlint:disable:next type_body_length
struct PlaylistDetailView: View {
    let playlistID: UUID
    /// Set when this is presented as a full-screen overlay (e.g. a Discover
    /// playlist tile); nil when it's the Playlists tab's own content.
    let onBack: (() -> Void)?

    @EnvironmentObject var playlistManager: PlaylistManager
    @ObservedObject private var radioManager = InternetRadioManager.shared
    @State private var selectedTrackID: UUID?
    @State private var gradientColors: [Color] = []
    @State private var gradientTask: Task<Void, Never>?
    @State private var artworkData: Data?
    @State private var collageToken = 0
    @State private var showingArtworkEditor = false
    @State private var isArtworkHovered = false

    @AppStorage("useArtworkColors")
    private var useArtworkColors = true

    @AppStorage("trackTableRowSize")
    private var trackTableRowSize: TableRowSize = .expanded

    @Environment(\.colorScheme)
    var colorScheme
    
    @State private var playlistSortOrder = [TrackSortField.dateAdded.getComparator(ascending: true)]

    @State private var stations: [RadioStation] = []

    private var isStationCollection: Bool { playlist?.type == .stations }

    // Convenience initializer for when you have a Playlist object
    init(playlist: Playlist, onBack: (() -> Void)? = nil) {
        self.playlistID = playlist.id
        self.onBack = onBack
    }

    // Standard initializer with playlist ID
    init(playlistID: UUID, onBack: (() -> Void)? = nil) {
        self.playlistID = playlistID
        self.onBack = onBack
    }

    // Get the current playlist from the manager
    private var playlist: Playlist? {
        playlistManager.playlists.first { $0.id == playlistID }
    }

    var body: some View {
        content
            // Opaque, matching EntityDetailView. Required because Home presents this as a
            // full-screen ZStack overlay; without it, whatever sits behind shows through.
            .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder private var content: some View {
        if let playlist = playlist {
            VStack(spacing: 0) {
                playlistHeader

                Divider()

                playlistContent
            }
            .task(id: playlistArtworkTaskID) {
                // Station collections build their cover from stations, not tracks.
                guard !isStationCollection else { return }
                let fresh = await playlist.warmArtworkCacheIfNeeded()
                // nil with empty tracks means "not loaded yet", not "no artwork"
                if fresh == nil && playlist.tracks.isEmpty { return }
                artworkData = fresh
                updateGradientColors()
            }
            .onChange(of: playlistID) {
                // Fired when this view is reused for a different playlist.
                selectedTrackID = nil
                stations = []
                seedArtworkFromCache()
                loadPlaylistTracksIfNeeded()
                loadSortPreference()
            }
            // An edit rewrites the station but not the collection, so `dateModified` below
            // never moves; without this the open collection keeps a stale stream URL.
            .onChange(of: radioManager.stations) {
                guard isStationCollection else { return }
                loadPlaylistTracksIfNeeded()
            }
            .onChange(of: playlist.dateModified) {
                // Fired after an edit (e.g. smart-playlist rules changed) that cleared tracks.
                loadPlaylistTracksIfNeeded()
            }
            .onAppear {
                if artworkData == nil {
                    seedArtworkFromCache()
                }
                loadPlaylistTracksIfNeeded()
                loadSortPreference()
            }
            .onChange(of: colorScheme) {
                updateGradientColors()
            }
            .onChange(of: useArtworkColors) {
                updateGradientColors()
            }
            .onDisappear { gradientTask?.cancel() }
            .sheet(isPresented: $showingArtworkEditor) {
                PlaylistArtworkSheet(
                    playlist: playlist,
                    defaultArtworkData: playlist.coverArtworkData == nil ? artworkData : nil,
                    stationArtworkSources: stations.compactMap(\.artworkData),
                    isPresented: $showingArtworkEditor
                ) { savedArtwork in
                    collageToken += 1
                    artworkData = savedArtwork
                    updateGradientColors()
                }
                .environmentObject(playlistManager)
            }
        } else {
            playlistNotFoundView
        }
    }

    // MARK: - Playlist Header

    @ViewBuilder private var playlistHeader: some View {
        if playlist != nil {
            PlaylistHeader {
                HStack(alignment: .top, spacing: 20) {
                    if let onBack = onBack {
                        DetailBackButton(action: onBack)
                    }

                    playlistArtwork

                    VStack(alignment: .leading, spacing: 12) {
                        playlistInfo
                        playlistControls
                    }

                    Spacer()
                }
            }
            .background {
                if !gradientColors.isEmpty {
                    GradientBackground(colors: gradientColors)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    if isStationCollection {
                        StationOptionsDropdown()
                    } else {
                        TrackTableOptionsDropdown(
                            sortOrder: $playlistSortOrder,
                            tableRowSize: $trackTableRowSize,
                            playlistID: playlistID,
                            showCustomSort: playlist?.type == .regular
                        )
                        .id(playlistID)
                    }
                }
                .padding([.bottom, .trailing], 12)
            }
        }
    }

    private var playlistArtwork: some View {
        Group {
            if let artworkData,
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
                        SymbolImage(playlistIcon)
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            guard playlist?.isUserEditable == true else { return }
            showingArtworkEditor = true
        }
        .overlay {
            if playlist?.isUserEditable == true {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 120, height: 120)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 20, weight: .medium))
                            Text(String(localized: "Update artwork"))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.white)
                    )
                    .opacity(isArtworkHovered ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isArtworkHovered)
                    .allowsHitTesting(false)
            }
        }
        .onHover { isArtworkHovered = $0 }
    }

    private var playlistInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playlistTypeText)
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)

            Text(playlist.map(DefaultPlaylists.displayName) ?? "")
                .font(.title)
                .fontWeight(.bold)
                .lineLimit(2)

            if let playlist = playlist {
                HStack {
                    Text(isStationCollection
                        ? String(localized: "\(playlist.trackCount) stations")
                        : String(localized: "\(playlist.trackCount) songs"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if playlist.trackCount > 0, !isStationCollection {
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
                    .foregroundStyle(.secondary)
                    .padding(.vertical, verticalPadding)
                    .padding(.horizontal, verticalPadding)
            }
            .adaptiveCircularButtonStyle()
            .help(isPinned ? String(localized: "Remove from Home") : String(localized: "Pin to Home"))

            // Stations have no queue, so there's no collection-level Play/Shuffle.
            if isStationCollection {
                Button(action: editStationCollection) {
                    HStack(spacing: iconTextSpacing) {
                        Image(systemName: Icons.edit)
                            .font(.system(size: iconSize))
                        Text("Edit")
                            .font(.system(size: textSize, weight: .medium))
                    }
                    .frame(width: buttonWidth)
                    .padding(.vertical, verticalPadding)
                }
                .adaptiveButtonStyle()
            } else {
                trackPlaylistControls(
                    buttonWidth: buttonWidth,
                    verticalPadding: verticalPadding,
                    iconSize: iconSize,
                    textSize: textSize,
                    iconTextSpacing: iconTextSpacing
                )
            }
        }
    }

    @ViewBuilder
    private func trackPlaylistControls(
        buttonWidth: CGFloat,
        verticalPadding: CGFloat,
        iconSize: CGFloat,
        textSize: CGFloat,
        iconTextSpacing: CGFloat
    ) -> some View {
        Group {
            Button(action: { playPlaylist() }, label: {
                HStack(spacing: iconTextSpacing) {
                    Image(systemName: Icons.playFill)
                        .font(.system(size: iconSize))
                    Text("Play")
                        .font(.system(size: textSize, weight: .medium))
                }
                .frame(width: buttonWidth)
                .padding(.vertical, verticalPadding)
            })
            .adaptiveButtonStyle(prominent: true)
            .disabled(playlist?.trackCount == 0)

            Button(action: { playPlaylist(shuffle: true) }, label: {
                HStack(spacing: iconTextSpacing) {
                    Image(systemName: Icons.shuffleFill)
                        .font(.system(size: iconSize))
                    Text("Shuffle")
                        .font(.system(size: textSize, weight: .medium))
                }
                .frame(width: buttonWidth)
                .padding(.vertical, verticalPadding)
            })
            .adaptiveButtonStyle()
            .disabled(playlist?.trackCount == 0)

            if playlist?.type == .regular {
                Button(action: editRegularPlaylist) {
                    HStack(spacing: iconTextSpacing) {
                        Image(systemName: Icons.edit)
                            .font(.system(size: iconSize))
                        Text("Edit")
                            .font(.system(size: textSize, weight: .medium))
                    }
                    .frame(width: buttonWidth)
                    .padding(.vertical, verticalPadding)
                }
                .adaptiveButtonStyle()
            } else if playlist?.type == .smart && playlist?.isUserEditable == true {
                Button(action: editSmartPlaylistRules) {
                    HStack(spacing: iconTextSpacing) {
                        Image(systemName: Icons.edit)
                            .font(.system(size: iconSize))
                        Text("Edit")
                            .font(.system(size: textSize, weight: .medium))
                    }
                    .frame(width: buttonWidth)
                    .padding(.vertical, verticalPadding)
                }
                .adaptiveButtonStyle()
            }
        }
    }

    // MARK: - Playlist Content

    private var playlistContent: some View {
        Group {
            if isStationCollection, let playlist {
                StationCollectionContentView(
                    collection: playlist,
                    stations: stations,
                    onEdit: editStationCollection
                )
            } else if let playlist, !playlist.tracks.isEmpty {
                TrackView(
                    tracks: playlist.tracks,
                    selectedTrackID: $selectedTrackID,
                    playlistID: playlistID,
                    entityID: nil,
                    sortOrder: $playlistSortOrder,
                    onPlayTrack: { track in
                        if let index = playlist.tracks.firstIndex(of: track) {
                            playlistManager.playTrackFromPlaylist(playlist, at: index)
                            selectedTrackID = track.id
                        }
                    },
                    contextMenuItems: { track, _ in
                        TrackContextMenu.createMenuItems(
                            for: track,
                            playlistManager: playlistManager,
                            currentContext: .playlist(playlist)
                        )
                    }
                )
                .id(playlistID)
            } else {
                emptyPlaylistView
            }
        }
    }

    // MARK: - Empty Playlist View

    @ViewBuilder private var emptyPlaylistView: some View {
        if let playlist = playlist {
            VStack(spacing: 20) {
                SymbolImage(playlistIcon)
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
                    Button("Edit") {
                        editRegularPlaylist()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
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
            return String(localized: "SMART PLAYLIST")
        case .regular:
            return String(localized: "PLAYLIST")
        case .stations:
            return String(localized: "STATION COLLECTION")
        }
    }

    private var emptyStateTitle: String {
        guard let playlist = playlist else { return String(localized: "Empty Playlist") }

        return DefaultPlaylists.noSongsText(for: playlist)
    }

    private var emptyStateMessage: String {
        guard let playlist = playlist else { return "" }
        
        return DefaultPlaylists.emptyStateText(for: playlist)
    }
    
    private var isPinned: Bool {
        playlistManager.isPlaylistPinned(playlist ?? Playlist(name: "", tracks: []))
    }

    // MARK: - Action Methods

    /// Swaps in the selected playlist's cover/cached collage synchronously, so
    /// the reused view never flashes the previous playlist's artwork.
    private func seedArtworkFromCache() {
        guard !isStationCollection else { return }
        artworkData = playlist?.artworkData
        updateGradientColors()
    }

    private func updateGradientColors() {
        gradientTask?.cancel()

        guard let playlist else {
            gradientColors = []
            return
        }

        gradientTask = ArtworkGradient.resolve(
            id: playlist.id,
            artworkData: artworkData,
            enabled: useArtworkColors,
            isDark: colorScheme == .dark,
            animation: .easeOut(duration: AnimationDuration.mediumDuration)
        ) { gradientColors = $0 }
    }

    private var playlistArtworkTaskID: String {
        // Order-independent signature of the cover-feeding tracks, so the collage + gradient
        // only recompute when the cover content actually changes, not on reorder or other
        // unrelated edits (dateModified/track count).
        playlist?.artworkSignature ?? "nil"
    }

    private func loadSortPreference() {
        let sortManager = PlaylistSortManager.shared

        // If user has explicitly set a sort preference, use it
        if sortManager.hasSortPreference(for: playlistID) {
            let field = sortManager.getSortField(for: playlistID)
            if field == .custom {
                NotificationCenter.default.post(
                    name: .trackTableSortChanged,
                    object: nil,
                    userInfo: ["isCustomSort": true]
                )
            } else {
                let ascending = sortManager.getSortAscending(for: playlistID)
                playlistSortOrder = [field.getComparator(ascending: ascending)]
            }
            return
        }

        // No stored preference: use smart playlist default or dateAdded
        if let criteria = playlist?.smartCriteria,
           let sortBy = criteria.sortBy {
            let fieldMap: [String: TrackSortField] = [
                "dateAdded": .dateAdded,
                "title": .title,
                "artist": .artist,
                "album": .album,
                "genre": .genre,
                "year": .year,
                "duration": .duration,
                "playCount": .playCount,
                "lastPlayedDate": .lastPlayedDate,
                "trackNumber": .trackNumber,
                "discNumber": .discNumber,
                "filename": .filename,
            ]
            if let field = fieldMap[sortBy] {
                playlistSortOrder = [field.getComparator(ascending: criteria.sortAscending)]
            } else {
                // Smart criteria sort (e.g. playCount, lastPlayedDate) has no table column,
                // so tracks arrive pre-sorted from DB and we preserve that order.
                NotificationCenter.default.post(
                    name: .trackTableSortChanged,
                    object: nil,
                    userInfo: ["isCustomSort": true]
                )
            }
        } else {
            playlistSortOrder = [TrackSortField.dateAdded.getComparator(ascending: true)]
        }
    }

    private func loadPlaylistTracksIfNeeded() {
        guard let playlist = playlist else { return }

        if playlist.type == .stations {
            stations = playlistManager.stations(in: playlist)
            refreshStationCollage()
            return
        }

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
        
        NotificationCenter.default.post(
            name: .playPlaylistTracks,
            object: nil,
            userInfo: ["playlistID": playlist.id, "shuffle": shuffle]
        )
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

    private func editSmartPlaylistRules() {
        guard let playlist = playlist else { return }
        playlistManager.showEditSmartPlaylistModal(playlist)
    }

    private func editRegularPlaylist() {
        guard let playlist = playlist else { return }
        playlistManager.showEditRegularPlaylistModal(playlist)
    }

    private func editStationCollection() {
        guard let playlist = playlist else { return }
        playlistManager.showEditStationCollectionModal(playlist)
    }
}

// MARK: - Station Collections

private extension PlaylistDetailView {
    /// The playlist 2x2 collage, over stations: `Playlist.artworkData` collages tracks.
    func refreshStationCollage() {
        // Before the early returns below, not after: selecting a custom cover or clearing
        // artwork must also invalidate a render already in flight.
        collageToken += 1
        let token = collageToken

        guard let playlist, playlist.type == .stations else { return }

        if let customCover = playlist.coverArtworkData {
            artworkData = customCover
            updateGradientColors()
            return
        }

        // Filter before taking four: otherwise four artwork-less stations at the front
        // produce a placeholder while later ones have images.
        let sources: [Data?] = Array(stations.compactMap(\.artworkData).prefix(4))
        guard !sources.isEmpty else {
            artworkData = nil
            updateGradientColors()
            return
        }

        Task.detached(priority: .utility) {
            let collage = Playlist.renderCollageArtwork(fromArtwork: sources)
            await MainActor.run {
                guard collageToken == token else { return }
                artworkData = collage
                updateGradientColors()
            }
        }
    }
}

// MARK: - Preview

#Preview("Regular Playlist") {
    let samplePlaylist = Playlist(name: "My Favorite Songs", tracks: [])

    return PlaylistDetailView(playlist: samplePlaylist)
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
            rules: [
                SmartPlaylistCriteria.Rule(
                    field: "isFavorite",
                    condition: .equals,
                    value: "true"
                )
            ],
            sortBy: "title",
            sortAscending: true
        ),
        isUserEditable: false
    )

    return PlaylistDetailView(playlist: smartPlaylist)
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
