import SwiftUI

enum TrackContextMenu {
    static func createMenuItems(
        for track: Track,
        playbackManager: PlaybackManager,
        playlistManager: PlaylistManager,
        currentContext: MenuContext
    ) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        
        // Add playback items
        items.append(contentsOf: createPlaybackItems(
            for: track,
            playlistManager: playlistManager,
            currentContext: currentContext
        ))
        
        // Add info item
        items.append(createShowInfoItem(for: track))
        
        items.append(createRevealInFinderItem(for: track))
        
        items.append(.divider)
        
        // Add "Go to" submenu
        items.append(createGoToMenu(for: track))
        
        items.append(.divider)
        
        // Add playlist items
        items.append(contentsOf: createPlaylistItems(
            for: track,
            playlistManager: playlistManager,
            existingItems: &items
        ))
        
        // Add context-specific items
        items.append(contentsOf: createContextSpecificItems(
            for: track,
            playlistManager: playlistManager,
            currentContext: currentContext
        ))
        
        return items
    }
    
    static func createMenuItems(
        for tracks: [Track],
        playbackManager: PlaybackManager,
        playlistManager: PlaylistManager,
        currentContext: MenuContext
    ) -> [ContextMenuItem] {
        if tracks.count == 1, let track = tracks.first {
            return createMenuItems(
                for: track,
                playbackManager: playbackManager,
                playlistManager: playlistManager,
                currentContext: currentContext
            )
        }
        
        var items: [ContextMenuItem] = []
        
        items.append(contentsOf: createBulkPlaybackItems(
            for: tracks,
            playlistManager: playlistManager,
            currentContext: currentContext
        ))
        
        items.append(.divider)
        
        items.append(contentsOf: createBulkPlaylistItems(
            for: tracks,
            playlistManager: playlistManager,
            currentContext: currentContext
        ))
        
        return items
    }
    
    static func createPlayerViewMenuItems(
        for track: Track,
        playbackManager: PlaybackManager,
        playlistManager: PlaylistManager
    ) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        
        // Add info item
        items.append(createShowInfoItem(for: track))
        
        items.append(createRevealInFinderItem(for: track))
        
        items.append(.divider)
        
        // Add "Go to" submenu
        items.append(createGoToMenu(for: track))
        
        items.append(.divider)
        
        // Add playlist items
        items.append(contentsOf: createPlaylistItems(
            for: track,
            playlistManager: playlistManager,
            existingItems: &items
        ))
        
        return items
    }
    
    // MARK: - Helper Methods
    
    private static func createPlaybackItems(
        for track: Track,
        playlistManager: PlaylistManager,
        currentContext: MenuContext
    ) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        
        // Play
        items.append(.button(title: "Play", icon: Icons.playFill) {
            switch currentContext {
            case .library:
                playlistManager.playTrack(track, fromTracks: [track])
            case .folder(let folder):
                playlistManager.playTrackFromFolder(track, folder: folder, folderTracks: [track])
            case .playlist(let playlist):
                if let index = playlist.tracks.firstIndex(of: track) {
                    playlistManager.playTrackFromPlaylist(playlist, at: index)
                }
            }
        })
        
        // Play Next
        items.append(.button(title: "Play Next", icon: "text.line.first.and.arrowtriangle.forward") {
            playlistManager.playNext(track)
        })
        
        // Add to Queue
        items.append(.button(title: "Add to Queue", icon: "text.append") {
            playlistManager.addToQueue(track)
        })
        
        return items
    }
    
    private static func createBulkPlaybackItems(
        for tracks: [Track],
        playlistManager: PlaylistManager,
        currentContext: MenuContext
    ) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        
        // Play
        items.append(.button(title: "Play", icon: Icons.playFill) {
            if let firstTrack = tracks.first {
                playlistManager.playTrack(firstTrack, fromTracks: tracks)
            }
        })
        
        // Play Next
        items.append(.button(title: "Play Next", icon: "text.line.first.and.arrowtriangle.forward") {
            for track in tracks.reversed() {
                playlistManager.playNext(track)
            }
        })
        
        // Add to Queue
        items.append(.button(title: "Add to Queue", icon: "text.append") {
            for track in tracks {
                playlistManager.addToQueue(track)
            }
        })
        
        return items
    }
    
    private static func createShowInfoItem(for track: Track) -> ContextMenuItem {
        .button(title: "Show Info", icon: Icons.infoCircle) {
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowTrackInfo"),
                object: nil,
                userInfo: ["track": track]
            )
        }
    }
    
    private static func createRevealInFinderItem(for track: Track) -> ContextMenuItem {
        .button(title: "Reveal in Finder", icon: "finder") {
            NSWorkspace.shared.selectFile(track.url.path, inFileViewerRootedAtPath: "")
        }
    }
    
    private static func createGoToMenu(for track: Track) -> ContextMenuItem {
        var goToItems: [ContextMenuItem] = []
        
        for filterType in LibraryFilterType.allCases {
            if filterType.usesMultiArtistParsing {
                goToItems.append(contentsOf: createMultiValueFilterItems(
                    for: track,
                    filterType: filterType
                ))
            } else {
                goToItems.append(createSingleValueFilterItem(
                    for: track,
                    filterType: filterType
                ))
            }
        }
        
        return .menu(title: "Go to", icon: "arrow.up.right.square", items: goToItems)
    }
    
    private static func createMultiValueFilterItems(
        for track: Track,
        filterType: LibraryFilterType
    ) -> [ContextMenuItem] {
        let value = filterType.getValue(from: track)
        let parsedValues = ArtistParser.parse(value, unknownPlaceholder: filterType.unknownPlaceholder)
        
        if parsedValues.count > 1 {
            var subItems: [ContextMenuItem] = []
            for parsedValue in parsedValues {
                subItems.append(.button(title: parsedValue) {
                    postGoToNotification(filterType: filterType, filterValue: parsedValue)
                })
            }
            return [
                .menu(title: filterType.rawValue, items: subItems)
            ]
        } else {
            let displayValue = parsedValues.first ?? filterType.unknownPlaceholder
            return [
                .button(title: "\(filterType.rawValue): \(displayValue)") {
                    postGoToNotification(filterType: filterType, filterValue: displayValue)
                }
            ]
        }
    }
    
    private static func createSingleValueFilterItem(
        for track: Track,
        filterType: LibraryFilterType
    ) -> ContextMenuItem {
        let value = filterType.getValue(from: track)
        let displayValue = value.isEmpty ? filterType.unknownPlaceholder : value
        
        return .button(title: "\(filterType.rawValue): \(displayValue)") {
            postGoToNotification(filterType: filterType, filterValue: displayValue)
        }
    }
    
    private static func postGoToNotification(filterType: LibraryFilterType, filterValue: String) {
        NotificationCenter.default.post(
            name: .goToLibraryFilter,
            object: nil,
            userInfo: [
                "filterType": filterType,
                "filterValue": filterValue
            ]
        )
    }
    
    private static func createPlaylistItems(
        for track: Track,
        playlistManager: PlaylistManager,
        existingItems: inout [ContextMenuItem]
    ) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        
        // Cache playlists to avoid repeated access
        let playlists = playlistManager.playlists.filter { $0.type == .regular }
        
        // Create playlist items more efficiently
        var playlistItems: [ContextMenuItem] = []
        
        // Create new playlist item
        playlistItems.append(.button(title: "New Playlist...") {
            playlistManager.showCreatePlaylistModal(with: [track])
        })
        
        // Add to existing playlists - optimize the containment check
        if !playlists.isEmpty {
            playlistItems.append(.divider)
            
            // Pre-compute track ID for efficiency
            let trackId = track.trackId
            
            for playlist in playlists {
                // More efficient containment check
                let isInPlaylist = trackId != nil && playlist.tracks.contains { $0.trackId == trackId }
                let title = isInPlaylist ? "✓ \(playlist.name)" : playlist.name
                
                playlistItems.append(.button(title: title) {
                    playlistManager.updateTrackInPlaylist(
                        track: track,
                        playlist: playlist,
                        add: !isInPlaylist
                    )
                })
            }
        }
        
        items.append(.menu(title: "Add to Playlist", icon: "text.badge.plus", items: playlistItems))
        
        items.append(
            .button(
                title: track.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                icon: track.isFavorite ? Icons.starFill : Icons.star
            ) { playlistManager.toggleFavorite(for: track) }
        )
        
        return items
    }
    
    private static func createBulkPlaylistItems(
        for tracks: [Track],
        playlistManager: PlaylistManager,
        currentContext: MenuContext
    ) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        
        let playlists = playlistManager.playlists.filter { $0.type == .regular }
        var playlistItems: [ContextMenuItem] = []
        
        playlistItems.append(.button(title: "New Playlist...") {
            playlistManager.showCreatePlaylistModal(with: tracks)
        })
        
        if !playlists.isEmpty {
            playlistItems.append(.divider)
            
            for playlist in playlists {
                playlistItems.append(.button(title: playlist.name) {
                    Task {
                        await playlistManager.addTracksToPlaylist(tracks: tracks, playlistID: playlist.id)
                    }
                })
            }
        }
        
        items.append(.menu(title: "Add to Playlist", icon: "text.badge.plus", items: playlistItems))
        
        let allFavorited = tracks.allSatisfy { $0.isFavorite }
        let title = allFavorited ? "Remove from Favorites" : "Add to Favorites"
        items.append(.button(title: title, icon: Icons.star) {
            playlistManager.toggleFavorite(for: tracks, setTo: !allFavorited)
        })
        
        if case .playlist(let playlist) = currentContext, playlist.type == .regular {
            items.append(.button(title: "Remove from Playlist", icon: Icons.trash, role: .destructive) {
                Task {
                    await playlistManager.removeTracksFromPlaylist(tracks: tracks, playlistID: playlist.id)
                }
            })
        }
        
        return items
    }

    private static func createContextSpecificItems(
        for track: Track,
        playlistManager: PlaylistManager,
        currentContext: MenuContext
    ) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        
        switch currentContext {
        case .folder:
            items.append(.divider)
            items.append(.button(title: "Show in Finder", icon: "finder") {
                NSWorkspace.shared.selectFile(
                    track.url.path,
                    inFileViewerRootedAtPath: track.url.deletingLastPathComponent().path
                )
            })
            
        case .playlist(let playlist):
            if playlist.type == .regular {
                items.append(.button(title: "Remove from Playlist", icon: Icons.trash, role: .destructive) {
                    playlistManager.removeTrackFromPlaylist(
                        track: track,
                        playlistID: playlist.id
                    )
                })
            }
            
        case .library:
            break
        }
        
        return items
    }
    
    enum MenuContext {
        case library
        case folder(Folder)
        case playlist(Playlist)
    }
}

struct ContextMenuItemView: View {
    let item: ContextMenuItem
    
    var body: some View {
        switch item {
        case .button(_, _, _, let action):
            Button(action: action) {
                HStack {
                    if let icon = item.icon {
                        Image(systemName: icon)
                            .frame(width: 16)
                    }
                    Text(item.title)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
        case .menu(_, _, let items):
            Menu {
                ForEach(items, id: \.id) { subItem in
                    ContextMenuItemView(item: subItem)
                }
            } label: {
                HStack {
                    if let icon = item.icon {
                        Image(systemName: icon)
                            .frame(width: 16)
                    }
                    Text(item.title)
                    Spacer()
                }
            }
            
        case .divider:
            Divider()
        }
    }
}
