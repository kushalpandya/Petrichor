import SwiftUI

// MARK: - Track View
struct TrackView: View {
    let tracks: [Track]
    @Binding var selectedTrackID: UUID?
    let playlistID: UUID?
    let entityID: UUID?
    @Binding var sortOrder: [KeyPathComparator<Track>]
    let onPlayTrack: (Track) -> Void
    let contextMenuItems: ([Track], PlaybackManager) -> [ContextMenuItem]
    
    @AppStorage("trackTableRowSize")
    private var tableRowSize: TableRowSize = .expanded

    var body: some View {
        TrackTableView(
            tracks: tracks,
            playlistID: playlistID,
            entityID: entityID,
            onPlayTrack: onPlayTrack,
            contextMenuItems: contextMenuItems,
            sortOrder: $sortOrder,
            tableRowSize: $tableRowSize
        )
    }
}

// MARK: - Track Context Menu
struct TrackContextMenuContent: View {
    let items: [ContextMenuItem]

    var body: some View {
        ForEach(items, id: \.id) { item in
            ContextMenuItemView(item: item)
        }
    }
}

// MARK: - Preview
#Preview("Tracks View") {
    @Previewable @State var sortOrder = [KeyPathComparator(\Track.title)]
    let sampleTracks = (0..<5).map { i in
        var track = Track(url: URL(fileURLWithPath: "/path/to/sample\(i).mp3"))
        track.title = "Sample Song \(i)"
        track.artist = "Sample Artist"
        track.album = "Sample Album"
        track.duration = 180.0
        return track
    }

    TrackView(
        tracks: sampleTracks,
        selectedTrackID: .constant(nil),
        playlistID: nil,
        entityID: nil,
        sortOrder: $sortOrder,
        onPlayTrack: { track in
            Logger.debugPrint("Playing \(track.title)")
        },
        contextMenuItems: { _, _ in [] }
    )
    .frame(height: 400)
    .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
}

#Preview("Tracks View with Playlist") {
    @Previewable @State var sortOrder = [KeyPathComparator(\Track.title)]
    let sampleTracks = (0..<10).map { i in
        var track = Track(url: URL(fileURLWithPath: "/path/to/sample\(i).mp3"))
        track.title = "Playlist Song \(i)"
        track.artist = "Artist \(i % 3)"
        track.album = "Album \(i % 2)"
        track.genre = "Genre"
        track.year = "202\(i % 10)"
        track.duration = Double(180 + i * 10)
        return track
    }

    TrackView(
        tracks: sampleTracks,
        selectedTrackID: .constant(nil),
        playlistID: nil,
        entityID: nil,
        sortOrder: $sortOrder,
        onPlayTrack: { track in
            Logger.debugPrint("Playing \(track.title)")
        },
        contextMenuItems: { _, _ in [] }
    )
    .frame(height: 600)
    .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
}
