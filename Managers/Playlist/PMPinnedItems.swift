//
// PlaylistManager class extension
//
// This extension contains methods for doing pin/unpin and related interactions on playlists,
// the methods internally also use DatabaseManager methods to work with database.
//

import Foundation
import SwiftUI

extension PlaylistManager {
    /// Pin a playlist
    func pinPlaylist(_ playlist: Playlist) async {
        guard let manager = libraryManager else { return }
        
        let pinnedItem = PinnedItem(playlist: playlist)
        
        do {
            try await manager.databaseManager.savePinnedItem(pinnedItem)
            await manager.loadPinnedItems()
        } catch {
            Logger.error("Failed to pin playlist: \(error)")
        }
    }
    
    /// Unpin a playlist
    func unpinPlaylist(_ playlist: Playlist) async {
        guard let manager = libraryManager else { return }
        
        do {
            try await manager.databaseManager.removePinnedItemMatching(
                filterType: nil,
                filterValue: nil,
                playlistId: playlist.id
            )
            await manager.loadPinnedItems()
        } catch {
            Logger.error("Failed to unpin playlist: \(error)")
        }
    }
    
    /// Check if a playlist is pinned
    func isPlaylistPinned(_ playlist: Playlist) -> Bool {
        guard let manager = libraryManager else { return false }
        
        return manager.pinnedItems.contains { item in
            item.itemType == .playlist && item.playlistId == playlist.id
        }
    }
    
    /// Get tracks for a pinned playlist item
    func getTracksForPinnedPlaylist(_ item: PinnedItem) -> [Track] {
        guard let manager = libraryManager else { return [] }
        
        // Only handle playlist items here
        guard item.itemType == .playlist,
              let playlistId = item.playlistId else { return [] }
        
        // Find the playlist in memory
        if let playlist = playlists.first(where: { $0.id == playlistId }) {
            if playlist.type == .smart {
                // Handle smart playlists using in-memory data
                return getSmartPlaylistTracks(playlist)
            } else {
                // For regular playlists, get from database
                return manager.databaseManager.getTracksForPinnedItem(item)
            }
        }
        
        return []
    }
    
    /// Create context menu item for playlist pinning
    func createPinContextMenuItem(for playlist: Playlist) -> ContextMenuItem {
        let isPinned = isPlaylistPinned(playlist)
        
        return .button(
            title: isPinned ? "Remove from Home" : "Pin to Home",
            role: nil
        ) {
                Task {
                    if isPinned {
                        await self.unpinPlaylist(playlist)
                    } else {
                        await self.pinPlaylist(playlist)
                    }
                }
        }
    }
    
    /// Handle playlist deletion - remove from pinned items if needed
    func handlePlaylistDeletionForPinnedItems(_ playlistId: UUID) async {
        guard let manager = libraryManager else { return }
        
        // Check if this playlist is pinned
        guard manager.pinnedItems.contains(where: { $0.playlistId == playlistId }) else {
            return
        }
        
        do {
            try await manager.databaseManager.removePinnedItemMatching(
                filterType: nil,
                filterValue: nil,
                playlistId: playlistId
            )
            await manager.loadPinnedItems()
        } catch {
            Logger.error("Failed to remove deleted playlist from pinned items: \(error)")
        }
    }

    private func getSmartPlaylistTracks(_ playlist: Playlist) -> [Track] {
        guard libraryManager != nil else { return [] }
        
        // Check if playlist needs refresh
        if smartPlaylistNeedsRefresh(playlist) {
            Task {
                await loadSmartPlaylistTracks(playlist)
            }
            return []
        }
        
        // Return cached tracks
        return playlist.tracks
    }
}
