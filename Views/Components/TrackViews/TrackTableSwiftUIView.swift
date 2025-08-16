import SwiftUI

struct TrackTableSwiftUIView: View {
    let tracks: [Track]
    let playlistID: UUID?
    let onPlayTrack: (Track) -> Void
    let contextMenuItems: (Track) -> [ContextMenuItem]
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @StateObject private var columnManager = ColumnVisibilityManager.shared
    
    @State private var selection: Track.ID?
    @State private var sortOrder = [KeyPathComparator(\Track.title)]
    @State private var lastSelectionTime: Date = Date()
    @State private var lastSelectedTrackID: Track.ID?
    
    @State private var columnCustomization = TableColumnCustomization<Track>()
    @AppStorage("trackTableColumnCustomizationData")
    private var columnCustomizationData = Data()
    
    @AppStorage("trackTableSortOrder") private var sortOrderData = Data()
    
    private var sortedTracks: [Track] {
        tracks.sorted(using: sortOrder)
    }
    
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
            }
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: columnCustomization) { _, newValue in
                saveColumnCustomization(newValue)
            }
            .onChange(of: sortOrder) { _, newSortOrder in
                // Save sort order to UserDefaults
                if let firstSort = newSortOrder.first {
                    var key = ""
                    var ascending = true
                    
                    // Determine which column is being sorted
                    let sortString = String(describing: firstSort)
                    if sortString.contains("title") {
                        key = "title"
                    } else if sortString.contains("artist") {
                        key = "artist"
                    } else if sortString.contains("album") {
                        key = "album"
                    } else if sortString.contains("genre") {
                        key = "genre"
                    } else if sortString.contains("year") {
                        key = "year"
                    } else if sortString.contains("composer") {
                        key = "composer"
                    } else if sortString.contains("sortableTrackNumber") {
                        key = "trackNumber"
                    } else if sortString.contains("duration") {
                        key = "duration"
                    }
                    
                    ascending = sortString.contains("forward")
                    
                    if !key.isEmpty {
                        let storage = ["key": key, "ascending": ascending] as [String: Any]
                        UserDefaults.standard.set(storage, forKey: "trackTableSortOrder")
                    }
                }
            }
            .onAppear {
                // Load saved sort order
                if let savedSort = UserDefaults.standard.dictionary(forKey: "trackTableSortOrder"),
                   let key = savedSort["key"] as? String,
                   let ascending = savedSort["ascending"] as? Bool {
                    switch key {
                    case "title":
                        sortOrder = [KeyPathComparator(\Track.title, order: ascending ? .forward : .reverse)]
                    case "artist":
                        sortOrder = [KeyPathComparator(\Track.artist, order: ascending ? .forward : .reverse)]
                    case "album":
                        sortOrder = [KeyPathComparator(\Track.album, order: ascending ? .forward : .reverse)]
                    case "genre":
                        sortOrder = [KeyPathComparator(\Track.genre, order: ascending ? .forward : .reverse)]
                    case "year":
                        sortOrder = [KeyPathComparator(\Track.year, order: ascending ? .forward : .reverse)]
                    case "composer":
                        sortOrder = [KeyPathComparator(\Track.composer, order: ascending ? .forward : .reverse)]
                    case "trackNumber":
                        sortOrder = [KeyPathComparator(\Track.sortableTrackNumber, order: ascending ? .forward : .reverse)]
                    case "duration":
                        sortOrder = [KeyPathComparator(\Track.duration, order: ascending ? .forward : .reverse)]
                    default:
                        break
                    }
                }
                
                restoreColumnCustomization()
            }
    }
    
    private var tableView: some View {
        Table(sortedTracks, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            // Play/Pause column
            TableColumn("", value: \.id) { track in
                TrackPlayPauseCell(
                    track: track,
                    isCurrentTrack: isCurrentTrack(track),
                    isPlaying: isPlaying(track)
                ) { handlePlayTrack(track) }
            }
            .width(32)
            .customizationID("playPause")
            .defaultVisibility(.visible)
            
            // Title column
            TableColumn("Title", value: \.title) { track in
                TrackTitleCell(
                    track: track,
                    isCurrentTrack: isCurrentTrack(track),
                    isPlaying: isPlaying(track),
                    isSelected: selection == track.id
                )
                .onTapGesture(count: 2) {
                    // Double-click handler
                    if isCurrentTrack(track) {
                        playbackManager.togglePlayPause()
                    } else {
                        handlePlayTrack(track)
                    }
                }
                .onTapGesture(count: 1) {
                    // Single click to select
                    selection = track.id
                }
            }
            .width(min: 200, ideal: 300)
            .customizationID("title")
            .defaultVisibility(.visible)
            
            // Artist column
            TableColumn("Artist", value: \.artist) { track in
                Text(track.artist)
                    .lineLimit(1)
                    .foregroundColor(isCurrentTrack(track) ? .accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if isCurrentTrack(track) {
                            playbackManager.togglePlayPause()
                        } else {
                            handlePlayTrack(track)
                        }
                    }
                    .onTapGesture(count: 1) {
                        selection = track.id
                    }
            }
            .width(min: 100, ideal: 200)
            .customizationID("artist")
            .defaultVisibility(columnManager.isVisible(.libraryFilter(.artists)) ? .visible : .hidden)
            
            // Album column
            TableColumn("Album", value: \.album) { track in
                Text(track.album)
                    .lineLimit(1)
                    .foregroundColor(isCurrentTrack(track) ? .accentColor : .primary)
            }
            .width(min: 100, ideal: 200)
            .customizationID("album")
            .defaultVisibility(columnManager.isVisible(.libraryFilter(.albums)) ? .visible : .hidden)
            
            // Genre column
            TableColumn("Genre", value: \.genre) { track in
                Text(track.genre)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 120)
            .customizationID("genre")
            .defaultVisibility(columnManager.isVisible(.libraryFilter(.genres)) ? .visible : .hidden)
            
            // Year column
            TableColumn("Year", value: \.year) { track in
                Text(track.year)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .width(60)
            .customizationID("year")
            .defaultVisibility(columnManager.isVisible(.libraryFilter(.years)) ? .visible : .hidden)
            
            // Composer column
            TableColumn("Composer", value: \.composer) { track in
                Text(track.composer)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .width(min: 100, ideal: 150)
            .customizationID("composer")
            .defaultVisibility(columnManager.isVisible(.libraryFilter(.composers)) ? .visible : .hidden)
            
            // Track Number column
            TableColumn("#", value: \.sortableTrackNumber) { track in
                if let trackNumber = track.trackNumber {
                    Text("\(trackNumber)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                } else {
                    Text("")
                }
            }
            .width(50)
            .customizationID("trackNumber")
            .defaultVisibility(columnManager.isVisible(.special(.trackNumber)) ? .visible : .hidden)
            
            // Duration column
            TableColumn("Duration", value: \.duration) { track in
                Text(formatDuration(track.duration))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .width(60)
            .customizationID("duration")
            .defaultVisibility(.visible)
        }
    }
    
    // MARK: - Helper Methods
    
    private func handlePlayTrack(_ track: Track) {
        if let playlistID = playlistID,
           let playlist = playlistManager.playlists.first(where: { $0.id == playlistID }) {
            if let originalIndex = playlist.tracks.firstIndex(where: { $0.id == track.id }) {
                playlistManager.playTrackFromPlaylist(playlist, at: originalIndex)
            }
        } else {
            playlistManager.playTrack(track, fromTracks: sortedTracks)
            playlistManager.currentQueueSource = .library
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    @ViewBuilder
    private func contextMenuItem(_ item: ContextMenuItem) -> some View {
        switch item {
        case .button(let title, _, let action):
            Button(title, action: action)
        case .menu(let title, let items):
            Menu(title) {
                ForEach(items, id: \.id) { subItem in
                    contextMenuSubItem(subItem)
                }
            }
        case .divider:
            Divider()
        }
    }
    
    @ViewBuilder
    private func contextMenuSubItem(_ item: ContextMenuItem) -> some View {
        switch item {
        case .button(let title, _, let action):
            Button(title, action: action)
        case .menu(let title, let items):
            Menu(title) {
                ForEach(items, id: \.id) { nestedItem in
                    if case .button(let nestedTitle, _, let nestedAction) = nestedItem {
                        Button(nestedTitle, action: nestedAction)
                    }
                }
            }
        case .divider:
            Divider()
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
}

// MARK: - Play/Pause Cell

private struct TrackPlayPauseCell: View {
    let track: Track
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    
    @EnvironmentObject var playbackManager: PlaybackManager
    
    var body: some View {
        HStack {
            if isCurrentTrack {
                if isPlaying {
                    Button(action: { playbackManager.togglePlayPause() }) {
                        Image(systemName: Icons.pauseFill)
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { playbackManager.togglePlayPause() }) {
                        Image(systemName: Icons.playFill)
                            .font(.system(size: 10))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // No hover support in SwiftUI Table - play button only visible for current track
                Color.clear
                    .frame(width: 16, height: 16)
            }
        }
        .frame(width: 32, height: 20)
    }
}

// MARK: - Title Cell with Artwork

private struct TrackTitleCell: View {
    let track: Track
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let isSelected: Bool
    
    @State private var artworkImage: NSImage?
    
    var body: some View {
        HStack(spacing: 8) {
            // Album artwork
            if let image = artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: Icons.musicNote)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    )
            }
            
            // Title text
            Text(track.title)
                .font(.system(size: 13, weight: isCurrentTrack ? .medium : .regular))
                .foregroundColor(isCurrentTrack ? .accentColor : .primary)
                .lineLimit(1)
                .animation(.none, value: isSelected)  // Disable animation for text color
            
            // Playing indicator
            if isPlaying {
                PlayingIndicator()
                    .frame(width: 16, height: 16)
            }
            
            Spacer()
        }
        .task(id: track.id) {
            // Reset artwork when track changes
            artworkImage = nil
            
            // Load the new track's artwork
            await loadTrackArtworkAsync(
                from: track.albumArtworkSmall,
                into: $artworkImage,
                delay: 0
            )
        }
    }
}

// MARK: - Track Extension for Sorting

extension Track {
    var sortableTrackNumber: Int {
        trackNumber ?? Int.max
    }
}

// MARK: - Preview

#Preview("SwiftUI Table View") {
    let sampleTracks = (0..<20).map { i in
        var track = Track(url: URL(fileURLWithPath: "/path/to/sample\(i).mp3"))
        track.title = "Sample Song \(i)"
        track.artist = "Sample Artist \(i % 3)"
        track.album = "Sample Album \(i % 2)"
        track.genre = "Sample Genre"
        track.year = "202\(i % 10)"
        track.duration = Double(180 + i * 10)
        track.composer = "Sample Composer \(i % 4)"
        track.trackNumber = i + 1
        track.isMetadataLoaded = true
        return track
    }
    
    TrackTableSwiftUIView(
        tracks: sampleTracks,
        playlistID: nil,
        onPlayTrack: { track in
            print("Playing \(track.title)")
        },
        contextMenuItems: { _ in [] }
    )
    .frame(height: 600)
    .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
    .environmentObject(PlaylistManager())
}
