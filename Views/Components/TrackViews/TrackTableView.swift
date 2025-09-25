import SwiftUI

struct TrackTableView: View {
    let tracks: [Track]
    let playlistID: UUID?
    let entityID: UUID?
    let onPlayTrack: (Track) -> Void
    let contextMenuItems: (Track) -> [ContextMenuItem]
    @Binding var sortOrder: [KeyPathComparator<Track>]
    @Binding var tableRowSize: TableRowSize
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    
    @State private var selection: Track.ID?
    @State private var sortedTracks: [Track] = []
    @State private var lastSelectionTime: Date = Date()
    @State private var lastSelectedTrackID: Track.ID?
    
    @State private var columnCustomization = TableColumnCustomization<Track>()
    
    @AppStorage("trackTableColumnCustomizationData")
    private var columnCustomizationData = Data()
    
    private func isCurrentTrack(_ track: Track) -> Bool {
        guard let currentTrack = playbackManager.currentTrack else { return false }
        return currentTrack.url.path == track.url.path
    }
    
    private func isPlaying(_ track: Track) -> Bool {
        isCurrentTrack(track) && playbackManager.isPlaying
    }
    
    var body: some View {
        tableView
            .contextMenu(forSelectionType: Track.ID.self) { selectedIDs in
                if let trackID = selectedIDs.first,
                   let track = tracks.first(where: { $0.id == trackID }) {
                    ForEach(contextMenuItems(track), id: \.id) { item in
                        contextMenuItem(item)
                    }
                }
            } primaryAction: { selectedIDs in
                if let trackID = selectedIDs.first,
                   let track = tracks.first(where: { $0.id == trackID }) {
                    handleDoubleTap(on: track)
                }
            }
            .onChange(of: columnCustomization) { _, newValue in
                saveColumnCustomization(newValue)
            }
            .onChange(of: sortOrder) { oldValue, newValue in
                if oldValue != newValue {
                    performBackgroundSort(with: newValue)
                    
                    saveSortOrderToUserDefaults(newValue, key: "trackTableSortOrder")
                    
                    NotificationCenter.default.post(
                        name: .trackTableSortChanged,
                        object: nil,
                        userInfo: ["sortOrder": newValue, "fromTable": true]
                    )
                }
            }
            .onChange(of: tracks) { _, newTracks in
                if !newTracks.isEmpty {
                    performBackgroundSort(with: sortOrder)
                }
            }
            .onAppear {
                initializeSortedTracks()
                restoreColumnCustomization()
            }
            .onReceive(NotificationCenter.default.publisher(for: .playEntityTracks)) { notification in
                handlePlayEntityNotification(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .playPlaylistTracks)) { notification in
                handlePlayPlaylistNotification(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .trackTableSortChanged)) { notification in
                handleSortChangedNotification(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .trackTableRowSizeChanged)) { notification in
                handleRowSizeChangedNotification(notification)
            }
    }
    
    private var tableView: some View {
        Table(sortedTracks, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            // Track Number
            TableColumn("#", value: \.sortableTrackNumber) { track in
                HStack {
                    Text(track.trackNumber != nil ? "\(track.trackNumber!)" : "")
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 20, ideal: 50, max: 100)
            .customizationID("trackNumber")
            .defaultVisibility(.hidden)
            
            // Disc Number
            TableColumn("Disc", value: \.sortableDiscNumber) { track in
                HStack {
                    Text(track.discNumber != nil ? "\(track.discNumber!)" : "")
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 20, ideal: 50, max: 100)
            .customizationID("discNumber")
            .defaultVisibility(.hidden)
            
            // Title
            TableColumn("Title", value: \.title) { track in
                TrackTitleCell(
                    tableRowSize: tableRowSize,
                    track: track,
                    isCurrentTrack: isCurrentTrack(track),
                    isPlaying: isPlaying(track),
                    isSelected: selection == track.id,
                    handlePlayTrack: handlePlayTrack
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 200, ideal: 300)
            .customizationID("title")
            .defaultVisibility(.visible)
            
            // Artist
            TableColumn("Artist", value: \.artist) { track in
                HStack {
                    Text(track.artist)
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 100, ideal: 200)
            .customizationID("artist")
            .defaultVisibility(.visible)
            
            // Album
            TableColumn("Album", value: \.album) { track in
                HStack {
                    Text(track.album)
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 100, ideal: 200)
            .customizationID("album")
            .defaultVisibility(.visible)
            
            // Genre
            TableColumn("Genre", value: \.genre) { track in
                HStack {
                    Text(track.genre)
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 80, ideal: 120)
            .customizationID("genre")
            .defaultVisibility(.hidden)
            
            // Year
            TableColumn("Year", value: \.year) { track in
                HStack {
                    Text(track.year)
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 40, ideal: 60, max: 100)
            .customizationID("year")
            .defaultVisibility(.visible)
            
            // Composer
            TableColumn("Composer", value: \.composer) { track in
                HStack {
                    Text(track.composer)
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 100, ideal: 150)
            .customizationID("composer")
            .defaultVisibility(.hidden)
            
            // Filename
            TableColumn("Filename", value: \.filename) { track in
                HStack {
                    Text(track.filename)
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 200, ideal: 300)
            .customizationID("filename")
            .defaultVisibility(.hidden)
            
            // Duration
            TableColumn("Duration", value: \.duration) { track in
                HStack {
                    Text(formatDuration(track.duration))
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 40, ideal: 60, max: 100)
            .customizationID("duration")
            .defaultVisibility(.visible)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .environment(\.defaultMinListRowHeight, tableRowSize.rowHeight)
    }
    
    // MARK: - Helper Methods
    
    private func initializeSortedTracks() {
        if let savedSort = UserDefaults.standard.dictionary(forKey: "trackTableSortOrder"),
           let key = savedSort["key"] as? String,
           let ascending = savedSort["ascending"] as? Bool {
            let sortComparators: [String: KeyPathComparator<Track>] = [
                "trackNumber": KeyPathComparator(\Track.sortableTrackNumber, order: ascending ? .forward : .reverse),
                "discNumber": KeyPathComparator(\Track.sortableDiscNumber, order: ascending ? .forward : .reverse),
                "title": KeyPathComparator(\Track.title, order: ascending ? .forward : .reverse),
                "artist": KeyPathComparator(\Track.artist, order: ascending ? .forward : .reverse),
                "album": KeyPathComparator(\Track.album, order: ascending ? .forward : .reverse),
                "genre": KeyPathComparator(\Track.genre, order: ascending ? .forward : .reverse),
                "year": KeyPathComparator(\Track.year, order: ascending ? .forward : .reverse),
                "composer": KeyPathComparator(\Track.composer, order: ascending ? .forward : .reverse),
                "filename": KeyPathComparator(\Track.filename, order: ascending ? .forward : .reverse),
                "duration": KeyPathComparator(\Track.duration, order: ascending ? .forward : .reverse),
                "dateAdded": KeyPathComparator(\Track.dateAdded, order: ascending ? .forward : .reverse)
            ]
            
            if let comparator = sortComparators[key] {
                sortOrder = [comparator]
                sortedTracks = tracks.sorted(using: [comparator])
                return
            }
        }
        
        let defaultComparator = KeyPathComparator(\Track.title, order: .forward)
        sortOrder = [defaultComparator]
        sortedTracks = tracks.sorted(using: [defaultComparator])
    }
    
    private func handleDoubleTap(on track: Track) {
        if isCurrentTrack(track) {
            playbackManager.togglePlayPause()
        } else {
            handlePlayTrack(track)
        }
    }
    
    private func handlePlayTrack(_ track: Track) {
        playlistManager.playTrack(track, fromTracks: sortedTracks)
        
        if let playlistID = playlistID,
           let playlist = playlistManager.playlists.first(where: { $0.id == playlistID }) {
            playlistManager.currentPlaylist = playlist
            playlistManager.currentQueueSource = .playlist
        } else {
            playlistManager.currentQueueSource = .library
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: StringFormat.mmss, minutes, remainingSeconds)
    }
    
    @ViewBuilder
    private func contextMenuItem(_ item: ContextMenuItem) -> some View {
        ContextMenuItemView(item: item)
    }
    
    // MARK: - Sorting Helpers
    
    private func performBackgroundSort(with newSortOrder: [KeyPathComparator<Track>]) {
        Task.detached(priority: .userInitiated) {
            let sorted = tracks.sorted(using: newSortOrder)
            await MainActor.run {
                self.sortedTracks = sorted
            }
        }
    }

    private func saveSortOrderToUserDefaults(_ sortOrder: [KeyPathComparator<Track>], key: String = "trackTableSortOrder") {
        guard let firstSort = sortOrder.first else { return }
        
        let sortString = String(describing: firstSort)
        let ascending = sortString.contains("forward")
        
        let sortKeys = [
            "dateAdded": "dateAdded",
            "sortableTrackNumber": "trackNumber",
            "sortableDiscNumber": "discNumber",
            "title": "title",
            "artist": "artist",
            "album": "album",
            "genre": "genre",
            "year": "year",
            "composer": "composer",
            "filename": "filename",
            "duration": "duration"
        ]
        
        if let keyValue = sortKeys.first(where: { sortString.contains($0.key) })?.value {
            let storage = ["key": keyValue, "ascending": ascending] as [String: Any]
            UserDefaults.standard.set(storage, forKey: key)
        }
    }
    
    // MARK: - Column Customization Persistence

    private func saveColumnCustomization(_ newValue: TableColumnCustomization<Track>) {
        do {
            let data = try JSONEncoder().encode(newValue)
            columnCustomizationData = data
        } catch {
            Logger.warning("Failed to encode TableColumnCustomization: \(error)")
        }
    }

    private func restoreColumnCustomization() {
        guard !columnCustomizationData.isEmpty else { return }
        do {
            let decoded = try JSONDecoder().decode(
                TableColumnCustomization<Track>.self,
                from: columnCustomizationData
            )
            columnCustomization = decoded
        } catch {
            Logger.warning("Failed to decode TableColumnCustomization: \(error)")
        }
    }
    
    // MARK: - Notification Handlers
        
    private func handlePlayEntityNotification(_ notification: Notification) {
        guard !sortedTracks.isEmpty,
              let notificationEntityId = notification.userInfo?["entityId"] as? String,
              entityID?.uuidString == notificationEntityId else { return }
        
        let shuffle = notification.userInfo?["shuffle"] as? Bool ?? false
        playlistManager.isShuffleEnabled = shuffle
        
        var tracksForPlayback = sortedTracks
        if shuffle {
            tracksForPlayback.shuffle()
        }
        
        if let firstTrack = tracksForPlayback.first {
            playlistManager.playTrack(firstTrack, fromTracks: tracksForPlayback)
            playlistManager.currentQueueSource = .library
        }
    }
    
    private func handlePlayPlaylistNotification(_ notification: Notification) {
        guard let notificationPlaylistID = notification.userInfo?["playlistID"] as? UUID,
              notificationPlaylistID == playlistID,
              !sortedTracks.isEmpty,
              let playlist = playlistManager.playlists.first(where: { $0.id == playlistID }) else { return }
        
        let shuffle = notification.userInfo?["shuffle"] as? Bool ?? false
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

    private func handleSortChangedNotification(_ notification: Notification) {
        if let newSortOrder = notification.userInfo?["sortOrder"] as? [KeyPathComparator<Track>] {
            sortOrder = newSortOrder
            
            if let userDefaultsKey = notification.userInfo?["userDefaultsKey"] as? String {
                saveSortOrderToUserDefaults(newSortOrder, key: userDefaultsKey)
            } else {
                saveSortOrderToUserDefaults(newSortOrder)
            }
        }
    }

    private func handleRowSizeChangedNotification(_ notification: Notification) {
        if let newRowSize = notification.userInfo?["rowSize"] as? TableRowSize {
            tableRowSize = newRowSize
        }
    }
}

// MARK: - Title Cell with Artwork & Playback Controls

private struct TrackTitleCell: View {
    let tableRowSize: TableRowSize
    let track: Track
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let isSelected: Bool
    let handlePlayTrack: (Track) -> Void
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var artworkImage: NSImage?
    
    var body: some View {
        HStack(spacing: 8) {
            if tableRowSize == .expanded {
                ZStack {
                    if let data = track.albumArtworkMedium,
                       let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
                            .overlay(
                                Image(systemName: Icons.musicNote)
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                            )
                    }
                    
                    if isCurrentTrack || isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.5))
                            .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
                        
                        Button(action: handleButtonAction) {
                            Image(systemName: buttonIcon)
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
                .animation(.none, value: isSelected)
            } else if tableRowSize == .compact {
                ZStack {
                    Image(systemName: Icons.playFill)
                        .font(.system(size: 14))
                        .foregroundColor(.clear)
                        .frame(width: 20, height: 20)
                    
                    if isSelected || isCurrentTrack {
                        Button(action: handleButtonAction) {
                            Image(systemName: buttonIcon)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(.none, value: isSelected)
            }
            
            // Title text
            Text(track.title)
                .font(.system(size: 13, weight: isCurrentTrack ? .bold : .regular))
                .lineLimit(1)
                .animation(.none, value: isSelected)
            
            Spacer()
        }
    }
    
    // MARK: - Private Helpers
    
    private func handleButtonAction() {
        if isCurrentTrack {
            playbackManager.togglePlayPause()
        } else {
            handlePlayTrack(track)
        }
    }
    
    private var buttonIcon: String {
        if isCurrentTrack && isPlaying {
            return Icons.pauseFill
        } else {
            return Icons.playFill
        }
    }
}

// MARK: - Track Extension for Sorting

extension Track {
    var sortableTrackNumber: Int {
        trackNumber ?? Int.max
    }
    
    var sortableDiscNumber: Int {
        discNumber ?? Int.max
    }
}
