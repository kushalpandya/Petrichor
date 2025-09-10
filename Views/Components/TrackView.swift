import SwiftUI

// MARK: - Track View
struct TrackView: View {
    let tracks: [Track]
    @Binding var selectedTrackID: UUID?
    let playlistID: UUID?
    let entityID: UUID?
    let onPlayTrack: (Track) -> Void
    let contextMenuItems: (Track) -> [ContextMenuItem]
    
    @State private var sortOrder = [KeyPathComparator(\Track.title)]
    @EnvironmentObject var playbackManager: PlaybackManager
    
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
            contextMenuItem(item)
        }
    }

    @ViewBuilder
    private func contextMenuItem(_ item: ContextMenuItem) -> some View {
        switch item {
        case .button(let title, let role, let action):
            Button(title, role: role, action: action)
        case .menu(let title, let items):
            Menu(title) {
                ForEach(items, id: \.id) { subItem in
                    switch subItem {
                    case .button(let subTitle, let subRole, let subAction):
                        Button(subTitle, role: subRole, action: subAction)
                    case .menu(let subMenuTitle, let subMenuItems):
                        Menu(subMenuTitle) {
                            ForEach(subMenuItems, id: \.id) { nestedItem in
                                if case .button(let nestedTitle, let nestedRole, let nestedAction) = nestedItem {
                                    Button(nestedTitle, role: nestedRole, action: nestedAction)
                                }
                            }
                        }
                    case .divider:
                        Divider()
                    }
                }
            }
        case .divider:
            Divider()
        }
    }
}

// MARK: - Async Track Artwork Loading

extension View {
    /// Load track artwork asynchronously with optional delay
    func loadTrackArtworkAsync(
        from data: Data?,
        into imageBinding: Binding<NSImage?>,
        delay: UInt64 = TimeConstants.fiftyMilliseconds
    ) async {
        guard imageBinding.wrappedValue == nil, let data = data else { return }
        
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
        }
        
        let image = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = NSImage(data: data)
                continuation.resume(returning: image)
            }
        }
        
        guard !Task.isCancelled else { return }
        
        if let image = image {
            await MainActor.run {
                imageBinding.wrappedValue = image
            }
        }
    }
}

// MARK: - Preview
#Preview("Tracks View") {
    let sampleTracks = (0..<5).map { i in
        var track = Track(url: URL(fileURLWithPath: "/path/to/sample\(i).mp3"))
        track.title = "Sample Song \(i)"
        track.artist = "Sample Artist"
        track.album = "Sample Album"
        track.duration = 180.0
        track.isMetadataLoaded = true
        return track
    }

    TrackView(
        tracks: sampleTracks,
        selectedTrackID: .constant(nil),
        playlistID: nil,
        entityID: nil,
        onPlayTrack: { track in
            Logger.debugPrint("Playing \(track.title)")
        },
        contextMenuItems: { _ in [] }
    )
    .frame(height: 400)
    .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
}

#Preview("Tracks View with Playlist") {
    let sampleTracks = (0..<10).map { i in
        var track = Track(url: URL(fileURLWithPath: "/path/to/sample\(i).mp3"))
        track.title = "Playlist Song \(i)"
        track.artist = "Artist \(i % 3)"
        track.album = "Album \(i % 2)"
        track.genre = "Genre"
        track.year = "202\(i % 10)"
        track.duration = Double(180 + i * 10)
        track.isMetadataLoaded = true
        return track
    }

    TrackView(
        tracks: sampleTracks,
        selectedTrackID: .constant(nil),
        playlistID: nil,
        entityID: nil,
        onPlayTrack: { track in
            Logger.debugPrint("Playing \(track.title)")
        },
        contextMenuItems: { _ in [] }
    )
    .frame(height: 600)
    .environmentObject(PlaybackManager(libraryManager: LibraryManager(), playlistManager: PlaylistManager()))
}
