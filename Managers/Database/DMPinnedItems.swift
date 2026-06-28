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
    func removePinnedItemMatching(filterType: LibraryFilterType?, filterValue: String?, albumId: Int64? = nil, playlistId: UUID?) async throws {
        try await dbQueue.write { db in
            var request = PinnedItem.all()

            if let albumId, filterType == .albums {
                // Albums match strictly by id (legacy nil-albumId pins are backfilled on upgrade).
                request = request.filter(PinnedItem.Columns.albumId == albumId)
            } else {
                if let filterType = filterType {
                    request = request.filter(PinnedItem.Columns.filterType == filterType.rawValue)
                }
                if let filterValue = filterValue {
                    request = request.filter(PinnedItem.Columns.filterValue == filterValue)
                }
                if let playlistId = playlistId {
                    request = request.filter(PinnedItem.Columns.playlistId == playlistId.uuidString)
                }
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
            
            // Use the same dispatch as the Library sidebar so pinned-item track lists
            // match Library track lists for multi-artist filter types (artists, album
            // artists, composers).
            var tracks = filterType.usesMultiArtistParsing && filterValue != filterType.unknownPlaceholder
                ? getTracksByFilterTypeContaining(filterType, value: filterValue)
                : getTracksByFilterType(filterType, value: filterValue)

            // Populate album artwork if needed
            populateAlbumArtworkForTracks(&tracks)

            return tracks

        case .folder:
            guard let path = item.filterValue else { return [] }
            return getImmediateTracksForFolderPath(path)

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
    
    // Get track counts for multiple pinned playlist items in a single query.
    // Library-item counts are computed in `LibraryManager.getTrackCountForPinnedItems`
    // by reading the same `cachedLibraryCategories` the Library sidebar renders, so
    // pinned and Library counts can never diverge.
    func getTrackCountForPinnedPlaylists(_ items: [PinnedItem]) async -> [Int64: Int] {
        do {
            // One read: fetch the referenced playlists once, compute regular counts inline,
            // and collect the smart playlists (reusing the already-fetched records).
            let (counts0, smartPlaylists) = try await dbQueue.read { db -> ([Int64: Int], [Playlist]) in
                var counts: [Int64: Int] = [:]

                let playlistIds = items.compactMap { $0.playlistId?.uuidString }
                guard !playlistIds.isEmpty else { return (counts, []) }

                let playlists = try Playlist
                    .filter(playlistIds.contains(Playlist.Columns.id))
                    .fetchAll(db)
                let playlistsById = Dictionary(playlists.map { ($0.id, $0) }) { first, _ in first }

                var smart: [Playlist] = []
                for item in items {
                    guard let itemId = item.id,
                          let playlistId = item.playlistId,
                          let playlist = playlistsById[playlistId] else { continue }

                    // Regular playlists and frozen smart playlists (autoUpdate == false) serve
                    // a persisted snapshot, so count its rows. Only live smart playlists are
                    // re-evaluated against the current library below.
                    let isFrozenSmart = playlist.type == .smart && playlist.smartCriteria?.autoUpdate == false
                    if playlist.type == .regular || isFrozenSmart {
                        counts[itemId] = try PlaylistTrack
                            .filter(PlaylistTrack.Columns.playlistId == playlistId.uuidString)
                            .fetchCount(db)
                    } else {
                        smart.append(playlist)
                    }
                }

                return (counts, smart)
            }

            var counts = counts0

            // Batch all pinned smart-playlist counts in a single read (shared artist fetch)
            // instead of a separate playlist re-fetch + count read per pinned item.
            if !smartPlaylists.isEmpty {
                let smartCounts = await getSmartPlaylistTrackCounts(smartPlaylists)
                for item in items {
                    guard let itemId = item.id, let playlistId = item.playlistId,
                          smartPlaylists.contains(where: { $0.id == playlistId }) else { continue }
                    counts[itemId] = smartCounts[playlistId] ?? 0
                }
            }

            return counts
        } catch {
            Logger.error("Failed to get batch pinned playlist counts: \(error)")
            return [:]
        }
    }

    // MARK: - Private Helpers
    
    private func findExistingPinnedItem(_ item: PinnedItem, in db: Database) throws -> PinnedItem? {
        switch item.itemType {
        case .library:
            guard let filterType = item.filterType,
                  let filterValue = item.filterValue else { return nil }

            // Albums dedupe by exact id (titles aren't unique); legacy nil falls back to title.
            if filterType == .albums, let albumId = item.albumId {
                return try PinnedItem
                    .filter(PinnedItem.Columns.itemType == PinnedItem.ItemType.library.rawValue)
                    .filter(PinnedItem.Columns.albumId == albumId)
                    .fetchOne(db)
            }

            return try PinnedItem
                .filter(PinnedItem.Columns.itemType == PinnedItem.ItemType.library.rawValue)
                .filter(PinnedItem.Columns.filterType == filterType.rawValue)
                .filter(PinnedItem.Columns.filterValue == filterValue)
                .fetchOne(db)

        case .folder:
            guard let path = item.filterValue else { return nil }
            return try PinnedItem
                .filter(PinnedItem.Columns.itemType == PinnedItem.ItemType.folder.rawValue)
                .filter(PinnedItem.Columns.filterValue == path)
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
