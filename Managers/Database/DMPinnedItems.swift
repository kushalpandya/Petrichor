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
    
    // Get track counts for multiple pinned items in a single query
    // swiftlint:disable:next cyclomatic_complexity
    func getTrackCountForPinnedItems(_ items: [PinnedItem]) async -> [Int64: Int] {
        do {
            var counts = try await dbQueue.read { db -> [Int64: Int] in
                var counts: [Int64: Int] = [:]
                
                // Group items by type for efficient querying
                let libraryItems = items.filter { $0.itemType == .library }
                let playlistItems = items.filter { $0.itemType == .playlist }
                
                // Handle library items
                for item in libraryItems {
                    guard let id = item.id,
                          let filterType = item.filterType,
                          let filterValue = item.filterValue else { continue }
                    
                    let count: Int
                    
                    switch filterType {
                    case .artists:
                        // For artists, we need to find the artist ID first
                        let normalizedName = ArtistParser.normalizeArtistName(filterValue)
                        
                        let artistId: Int64?
                        if let storedId = item.artistId {
                            artistId = storedId
                        } else {
                            artistId = try Artist
                                .filter((Artist.Columns.name == filterValue) || (Artist.Columns.normalizedName == normalizedName))
                                .fetchOne(db)?.id
                        }
                        
                        if let artistId = artistId {
                            // Get unique track IDs for this artist
                            let trackIds = try TrackArtist
                                .filter(TrackArtist.Columns.artistId == artistId)
                                .filter(TrackArtist.Columns.role == TrackArtist.Role.artist)
                                .select(TrackArtist.Columns.trackId, as: Int64.self)
                                .fetchSet(db)
                            
                            // Count tracks, applying duplicate filter
                            if !trackIds.isEmpty {
                                count = try applyDuplicateFilter(Track.all())
                                    .filter(trackIds.contains(Track.Columns.trackId))
                                    .fetchCount(db)
                            } else {
                                count = 0
                            }
                        } else {
                            count = 0
                        }
                        
                    case .albums:
                        if let albumId = item.albumId {
                            count = try applyDuplicateFilter(Track.all())
                                .filter(Track.Columns.albumId == albumId)
                                .fetchCount(db)
                        } else {
                            // Fallback to name-based search
                            count = try applyDuplicateFilter(Track.all())
                                .filter(Track.Columns.album == filterValue)
                                .fetchCount(db)
                        }
                        
                    case .genres:
                        count = try applyDuplicateFilter(Track.all())
                            .filter(Track.Columns.genre == filterValue)
                            .fetchCount(db)
                        
                    case .years:
                        count = try applyDuplicateFilter(Track.all())
                            .filter(Track.Columns.year == filterValue)
                            .fetchCount(db)
                        
                    case .decades:
                        // Decades need special handling
                        let decade = filterValue.replacingOccurrences(of: "s", with: "")
                        if let decadeInt = Int(decade) {
                            let startYear = String(decadeInt)
                            let endYear = String(decadeInt + 9)
                            count = try applyDuplicateFilter(Track.all())
                                .filter(Track.Columns.year >= startYear)
                                .filter(Track.Columns.year <= endYear)
                                .fetchCount(db)
                        } else {
                            count = 0
                        }
                        
                    case .composers:
                        let normalizedName = ArtistParser.normalizeArtistName(filterValue)
                        let composerArtistId = try Artist
                            .filter((Artist.Columns.name == filterValue) || (Artist.Columns.normalizedName == normalizedName))
                            .fetchOne(db)?.id
                        
                        if let artistId = composerArtistId {
                            let trackIds = try TrackArtist
                                .filter(TrackArtist.Columns.artistId == artistId)
                                .filter(TrackArtist.Columns.role == TrackArtist.Role.composer)
                                .select(TrackArtist.Columns.trackId, as: Int64.self)
                                .fetchSet(db)
                            
                            if !trackIds.isEmpty {
                                count = try applyDuplicateFilter(Track.all())
                                    .filter(trackIds.contains(Track.Columns.trackId))
                                    .fetchCount(db)
                            } else {
                                count = try applyDuplicateFilter(Track.all())
                                    .filter(Track.Columns.composer == filterValue)
                                    .fetchCount(db)
                            }
                        } else {
                            count = try applyDuplicateFilter(Track.all())
                                .filter(Track.Columns.composer == filterValue)
                                .fetchCount(db)
                        }
                        
                    case .albumArtists:
                        count = try applyDuplicateFilter(Track.all())
                            .filter(Track.Columns.albumArtist == filterValue)
                            .fetchCount(db)
                    }
                    
                    counts[id] = count
                }
                
                // Handle playlist items
                if !playlistItems.isEmpty {
                    let playlistIds = playlistItems.compactMap { $0.playlistId?.uuidString }
                    
                    if !playlistIds.isEmpty {
                        // Get all playlists with their types
                        let playlists = try Playlist
                            .filter(playlistIds.contains(Playlist.Columns.id))
                            .fetchAll(db)
                        
                        for item in playlistItems {
                            guard let itemId = item.id,
                                  let playlistId = item.playlistId else { continue }
                            
                            if let playlist = playlists.first(where: { $0.id == playlistId }) {
                                if playlist.type == .regular {
                                    // For regular playlists, count the tracks
                                    let count = try PlaylistTrack
                                        .filter(PlaylistTrack.Columns.playlistId == playlistId.uuidString)
                                        .fetchCount(db)
                                    counts[itemId] = count
                                } else {
                                    counts[itemId] = -1
                                }
                            }
                        }
                    }
                }
                
                return counts
            }
            
            // Now handle smart playlists outside the database read
            for item in items {
                guard let itemId = item.id,
                      let playlistId = item.playlistId,
                      counts[itemId] == -1 else { continue }
                
                // Get the playlist and calculate count
                if let playlist = try? await dbQueue.read({ db in
                    try Playlist
                        .filter(Playlist.Columns.id == playlistId.uuidString)
                        .fetchOne(db)
                }), playlist.type == .smart {
                    counts[itemId] = await getSmartPlaylistTrackCount(playlist)
                } else {
                    counts[itemId] = 0
                }
            }
            
            return counts
        } catch {
            Logger.error("Failed to get batch pinned item counts: \(error)")
            return [:]
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
