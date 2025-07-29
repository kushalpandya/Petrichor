//
// DatabaseManager class extension
//
// This extension contains all the methods for managing pinned items in the Home tab sidebar view.
//

import Foundation
import GRDB

extension DatabaseManager {
    // MARK: - Pinned Items Management
    
    /// Save a pinned item to the database
    func savePinnedItem(_ item: PinnedItem) async throws {
        try await dbQueue.write { db in
            // Check if item already exists to prevent duplicates
            if let existingItem = try self.findExistingPinnedItem(item, in: db) {
                Logger.info("Item already pinned: \(existingItem.displayName)")
                return
            }
            
            // Get the next sort order
            var newItem = item
            let maxSortOrder = try PinnedItem
                .select(max(PinnedItem.Columns.sortOrder))
                .fetchOne(db) ?? 0
            newItem.sortOrder = maxSortOrder + 1
            
            try newItem.save(db)
            Logger.info(String(format: "Pinned item added: %@", newItem.displayName))
        }
    }
    
    /// Remove a pinned item from the database
    func removePinnedItem(_ item: PinnedItem) async throws {
        try await dbQueue.write { db in
            if let id = item.id {
                try PinnedItem.deleteOne(db, key: id)
                
                // Reorder remaining items
                try self.reorderPinnedItems(in: db)
            }
        }
    }
    
    /// Remove a pinned item by matching criteria
    func removePinnedItemMatching(filterType: LibraryFilterType?, filterValue: String?, playlistId: UUID?) async throws {
        try await dbQueue.write { db in
            var request = PinnedItem.all()
            
            if let filterType = filterType {
                request = request.filter(PinnedItem.Columns.filterType == filterType.rawValue)
            }
            if let filterValue = filterValue {
                request = request.filter(PinnedItem.Columns.filterValue == filterValue)
            }
            if let playlistId = playlistId {
                request = request.filter(PinnedItem.Columns.playlistId == playlistId.uuidString)
            }
            
            let deletedCount = try request.deleteAll(db)
            if deletedCount > 0 {
                try self.reorderPinnedItems(in: db)
            }
        }
    }
    
    /// Get all pinned items ordered by sort order
    func getPinnedItems() async throws -> [PinnedItem] {
        try await dbQueue.read { db in
            try PinnedItem
                .order(PinnedItem.Columns.sortOrder)
                .fetchAll(db)
        }
    }
    
    /// Get all pinned items synchronously for initial load
    func getPinnedItemsSync() -> [PinnedItem] {
        do {
            return try dbQueue.read { db in
                try PinnedItem
                    .order(PinnedItem.Columns.sortOrder)
                    .fetchAll(db)
            }
        } catch {
            Logger.error("Failed to load pinned items synchronously: \(error)")
            return []
        }
    }
    
    /// Update the sort order of pinned items
    func updatePinnedItemsOrder(_ items: [PinnedItem]) async throws {
        try await dbQueue.write { db in
            for (index, item) in items.enumerated() {
                var updatedItem = item
                updatedItem.sortOrder = index
                try updatedItem.update(db)
            }
        }
    }
    
    /// Check if an item is pinned
    func isItemPinned(filterType: LibraryFilterType?, filterValue: String?, entityId: UUID?, playlistId: UUID?) async throws -> Bool {
        try await dbQueue.read { db in
            var request = PinnedItem.all()
            
            if let playlistId = playlistId {
                request = request.filter(PinnedItem.Columns.playlistId == playlistId.uuidString)
            } else if let filterType = filterType, let filterValue = filterValue {
                request = request
                    .filter(PinnedItem.Columns.filterType == filterType.rawValue)
                    .filter(PinnedItem.Columns.filterValue == filterValue)
            } else if let entityId = entityId {
                request = request.filter(PinnedItem.Columns.entityId == entityId.uuidString)
            }
            
            return try request.fetchCount(db) > 0
        }
    }
    
    /// Get tracks for a pinned item
    func getTracksForPinnedItem(_ item: PinnedItem) -> [Track] {
        switch item.itemType {
        case .library:
            guard let filterType = item.filterType,
                  let filterValue = item.filterValue else { return [] }
            
            // For artist entities, use the same method as EntityDetailView
            if filterType == .artists && item.artistId != nil {
                return getTracksForArtistEntity(filterValue)
            }
            
            // For album entities with albumId, use the dedicated method
            if filterType == .albums && item.albumId != nil {
                // Try to reconstruct the AlbumEntity to use the proper method
                if let albumEntity = getAlbumEntities().first(where: {
                    $0.albumId == item.albumId && $0.name == filterValue
                }) {
                    return getTracksForAlbumEntity(albumEntity)
                }
            }
            
            // Use optimized database query for filter-based retrieval
            var tracks = getTracksByFilterType(filterType, value: filterValue)

            // Populate album artwork if needed
            populateAlbumArtworkForTracks(&tracks)

            return tracks
            
        case .playlist:
            guard let playlistId = item.playlistId else { return [] }
            
            // Get playlist tracks using GRDB relationships
            do {
                return try dbQueue.read { db in
                    // First get the playlist
                    guard let playlist = try Playlist
                        .filter(Playlist.Columns.id == playlistId.uuidString)
                        .fetchOne(db) else {
                        return []
                    }
                    
                    if playlist.type == .smart {
                        // For smart playlists, return empty - let the caller handle it
                        return []
                    } else {
                        // For regular playlists, fetch tracks using GRDB
                        let playlistTracks = try PlaylistTrack
                            .filter(PlaylistTrack.Columns.playlistId == playlistId.uuidString)
                            .order(PlaylistTrack.Columns.position)
                            .fetchAll(db)
                        
                        let trackIds = playlistTracks.map { $0.trackId }
                        
                        // Fetch all tracks at once
                        let tracks = try Track
                            .filter(trackIds.contains(Track.Columns.trackId))
                            .fetchAll(db)
                        
                        // Sort tracks according to playlist order
                        return playlistTracks.compactMap { playlistTrack in
                            tracks.first { $0.trackId == playlistTrack.trackId }
                        }
                    }
                }
            } catch {
                Logger.error("Failed to get tracks for pinned playlist \(item.displayName): \(error)")
                return []
            }
        }
    }

    // MARK: - Private Helpers
    
    private func findExistingPinnedItem(_ item: PinnedItem, in db: Database) throws -> PinnedItem? {
        switch item.itemType {
        case .library:
            guard let filterType = item.filterType,
                  let filterValue = item.filterValue else { return nil }
            
            return try PinnedItem
                .filter(PinnedItem.Columns.itemType == PinnedItem.ItemType.library.rawValue)
                .filter(PinnedItem.Columns.filterType == filterType.rawValue)
                .filter(PinnedItem.Columns.filterValue == filterValue)
                .fetchOne(db)
            
        case .playlist:
            guard let playlistId = item.playlistId else { return nil }
            
            return try PinnedItem
                .filter(PinnedItem.Columns.itemType == PinnedItem.ItemType.playlist.rawValue)
                .filter(PinnedItem.Columns.playlistId == playlistId.uuidString)
                .fetchOne(db)
        }
    }
    
    private func reorderPinnedItems(in db: Database) throws {
        let items = try PinnedItem
            .order(PinnedItem.Columns.sortOrder)
            .fetchAll(db)
        
        for (index, var item) in items.enumerated() {
            item.sortOrder = index
            try item.update(db)
        }
    }
}
