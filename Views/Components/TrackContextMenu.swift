import SwiftUI

extension Notification.Name {
    static let goToLibraryFilter = Notification.Name("GoToLibraryFilter")
}

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
    
    // MARK: - Helper Methods
    
    private static func createPlaybackItems(
        for track: Track,
        playlistManager: PlaylistManager,
        currentContext: MenuContext
    ) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        
        // Play
        items.append(.button(title: "Play") {
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
        items.append(.button(title: "Play Next") {
            playlistManager.playNext(track)
        })
        
        // Add to Queue
        items.append(.button(title: "Add to Queue") {
            playlistManager.addToQueue(track)
        })
        
        return items
    }
    
    private static func createShowInfoItem(for track: Track) -> ContextMenuItem {
        .button(title: "Show Info") {
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowTrackInfo"),
                object: nil,
                userInfo: ["track": track]
            )
        }
    }
    
    private static func createRevealInFinderItem(for track: Track) -> ContextMenuItem {
        .button(title: "Reveal in Finder") {
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
        
        return .menu(title: "Go to", items: goToItems)
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
            playlistManager.showCreatePlaylistModal(with: track)
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
        
        items.append(.menu(title: "Add to Playlist", items: playlistItems))
        
        items.append(.button(title: track.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            playlistManager.toggleFavorite(for: track)
        })
        
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
            items.append(.button(title: "Show in Finder") {
                NSWorkspace.shared.selectFile(
                    track.url.path,
                    inFileViewerRootedAtPath: track.url.deletingLastPathComponent().path
                )
            })
            
        case .playlist(let playlist):
            if playlist.type == .regular {
                items.append(.divider)
                items.append(.button(title: "Remove from Playlist", role: .destructive) {
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
