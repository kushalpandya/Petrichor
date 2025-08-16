import SwiftUI

struct TrackTableSwiftUIView: View {
    let tracks: [Track]
    let playlistID: UUID?
    let entityID: UUID?
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
            .onChange(of: columnCustomization) { _, newValue in
                saveColumnCustomization(newValue)
            }
            .onChange(of: sortOrder) { _, newSortOrder in
                if let firstSort = newSortOrder.first {
                    var key = ""
                    var ascending = true
                    
                    let sortString = String(describing: firstSort)
                    if sortString.contains("sortableTrackNumber") {
                        key = "trackNumber"
                    } else if sortString.contains("title") {
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
                    case "trackNumber":
                        sortOrder = [KeyPathComparator(\Track.sortableTrackNumber, order: ascending ? .forward : .reverse)]
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
            // Track Number
            TableColumn("#", value: \.sortableTrackNumber) { track in
                HStack {
                    Text(track.trackNumber != nil ? "\(track.trackNumber!)" : "")
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleDoubleTap(on: track)
                }
                .onTapGesture(count: 1) {
                    selection = track.id
                }
            }
            .width(min: 20, ideal: 50, max: 100)
            .customizationID("trackNumber")
            .defaultVisibility(columnManager.isVisible(.special(.trackNumber)) ? .visible : .hidden)
            
            // Title
            TableColumn("Title", value: \.title) { track in
                TrackTitleCell(
                    track: track,
                    isCurrentTrack: isCurrentTrack(track),
                    isPlaying: isPlaying(track),
                    isSelected: selection == track.id,
                    handlePlayTrack: handlePlayTrack
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleDoubleTap(on: track)
                }
                .onTapGesture(count: 1) {
                    selection = track.id
                }
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
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleDoubleTap(on: track)
                }
                .onTapGesture(count: 1) {
                    selection = track.id
                }
            }
            .width(min: 100, ideal: 200)
            .customizationID("artist")
            .defaultVisibility(columnManager.isVisible(.libraryFilter(.artists)) ? .visible : .hidden)
            
            // Album
            TableColumn("Album", value: \.album) { track in
                HStack {
                    Text(track.album)
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleDoubleTap(on: track)
                }
                .onTapGesture(count: 1) {
                    selection = track.id
                }
            }
            .width(min: 100, ideal: 200)
            .customizationID("album")
            .defaultVisibility(columnManager.isVisible(.libraryFilter(.albums)) ? .visible : .hidden)
            
            // Genre
            TableColumn("Genre", value: \.genre) { track in
                HStack {
                    Text(track.genre)
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleDoubleTap(on: track)
                }
                .onTapGesture(count: 1) {
                    selection = track.id
                }
            }
            .width(min: 80, ideal: 120)
            .customizationID("genre")
            .defaultVisibility(columnManager.isVisible(.libraryFilter(.genres)) ? .visible : .hidden)
            
            // Year
            TableColumn("Year", value: \.year) { track in
                HStack {
                    Text(track.year)
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleDoubleTap(on: track)
                }
                .onTapGesture(count: 1) {
                    selection = track.id
                }
            }
            .width(min: 40, ideal: 60, max: 100)
            .customizationID("year")
            .defaultVisibility(columnManager.isVisible(.libraryFilter(.years)) ? .visible : .hidden)
            
            // Composer
            TableColumn("Composer", value: \.composer) { track in
                HStack {
                    Text(track.composer)
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleDoubleTap(on: track)
                }
                .onTapGesture(count: 1) {
                    selection = track.id
                }
            }
            .width(min: 100, ideal: 150)
            .customizationID("composer")
            .defaultVisibility(columnManager.isVisible(.libraryFilter(.composers)) ? .visible : .hidden)
            
            // Duration
            TableColumn("Duration", value: \.duration) { track in
                HStack {
                    Text(formatDuration(track.duration))
                        .font(.system(size: 13, weight: isCurrentTrack(track) ? .medium : .regular))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    handleDoubleTap(on: track)
                }
                .onTapGesture(count: 1) {
                    selection = track.id
                }
            }
            .width(min: 40, ideal: 60, max: 100)
            .customizationID("duration")
            .defaultVisibility(.visible)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Helper Methods
    
    private func handleDoubleTap(on track: Track) {
        if isCurrentTrack(track) {
            playbackManager.togglePlayPause()
        } else {
            handlePlayTrack(track)
        }
    }
    
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
        return String(format: StringFormat.mmss, minutes, remainingSeconds)
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

// MARK: - Title Cell with Artwork & Playback Controls

private struct TrackTitleCell: View {
    let track: Track
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let isSelected: Bool
    let handlePlayTrack: (Track) -> Void
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var artworkImage: NSImage?
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                // Album Artwork or placeholder
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
                
                if isCurrentTrack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 30, height: 30)
                    
                    // Play/Pause button
                    Button(action: { playbackManager.togglePlayPause() }) {
                        Image(systemName: isPlaying ? Icons.pauseFill : Icons.playFill)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 18, height: 18)
                }
            }
            .frame(width: 30, height: 30)
            
            // Title text
            Text(track.title)
                .font(.system(size: 13, weight: isCurrentTrack ? .bold : .regular))
                .lineLimit(1)
                .animation(.none, value: isSelected)
            
            Spacer()
        }
        .task(id: track.id) {
            artworkImage = nil
            await loadTrackArtworkAsync(
                from: track.albumArtworkSmall,
                into: $artworkImage,
                delay: TimeConstants.oneHundredMilliseconds
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
        entityID: nil,
        onPlayTrack: { track in
            print("Playing \(track.title)")
        },
        contextMenuItems: { _ in [] }
    )
    .frame(height: 600)
    .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
    .environmentObject(PlaylistManager())
}
