//
// DatabaseManager class extension
//
// This extension contains all the methods for managing playlists in the Playlist tab view.
//

import Foundation
import GRDB

extension DatabaseManager {
    func savePlaylistAsync(_ playlist: Playlist) async throws {
        try await dbQueue.write { db in
            // Save the playlist using GRDB's save method
            try playlist.save(db)
            
            // Delete existing track associations
            try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlist.id.uuidString)
                .deleteAll(db)
            
            let deletedCount = db.changesCount
            Logger.info("Deleted \(deletedCount) existing track associations")
            
            // Batch insert track associations for regular playlists
            if playlist.type == .regular && !playlist.tracks.isEmpty {
                Logger.info("Saving \(playlist.tracks.count) tracks for playlist '\(playlist.name)'")
                
                // Create all PlaylistTrack objects at once
                let playlistTracks = playlist.tracks.enumerated().compactMap { index, track -> PlaylistTrack? in
                    guard let trackId = track.trackId else {
                        Logger.warning("Track '\(track.title)' has no database ID, skipping")
                        return nil
                    }
                    
                    return PlaylistTrack(
                        playlistId: playlist.id.uuidString,
                        trackId: trackId,
                        position: index,
                        dateAdded: Date()
                    )
                }
                
                // Batch insert all tracks at once
                if !playlistTracks.isEmpty {
                    try PlaylistTrack.insertMany(playlistTracks, db: db)
                    Logger.info("Batch inserted \(playlistTracks.count) tracks to playlist")
                }
                
                // Verify the save
                let savedCount = try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlist.id.uuidString)
                    .fetchCount(db)
                
                Logger.info("Verified \(savedCount) tracks saved for playlist in database")
            }
        }
    }
    
    func savePlaylist(_ playlist: Playlist) throws {
        try dbQueue.write { db in
            // Save the playlist using GRDB's save method
            try playlist.save(db)
            
            // Delete existing track associations
            try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlist.id.uuidString)
                .deleteAll(db)
            
            let deletedCount = db.changesCount
            Logger.info("Deleted \(deletedCount) existing track associations")
            
            // Batch insert track associations for regular playlists
            if playlist.type == .regular && !playlist.tracks.isEmpty {
                Logger.info("Saving \(playlist.tracks.count) tracks for playlist '\(playlist.name)'")
                
                // Create all PlaylistTrack objects at once
                let playlistTracks = playlist.tracks.enumerated().compactMap { index, track -> PlaylistTrack? in
                    guard let trackId = track.trackId else {
                        Logger.warning("Track '\(track.title)' has no database ID, skipping")
                        return nil
                    }
                    
                    return PlaylistTrack(
                        playlistId: playlist.id.uuidString,
                        trackId: trackId,
                        position: index,
                        dateAdded: Date()
                    )
                }
                
                // Batch insert all tracks at once
                if !playlistTracks.isEmpty {
                    try PlaylistTrack.insertMany(playlistTracks, db: db)
                    Logger.info("Batch inserted \(playlistTracks.count) tracks to playlist")
                }
                
                // Verify the save
                let savedCount = try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlist.id.uuidString)
                    .fetchCount(db)
                
                Logger.info("Verified \(savedCount) tracks saved for playlist in database")
            }
        }
    }
    
    /// Get track counts for all playlists without loading tracks
    func getPlaylistTrackCounts() -> [UUID: Int] {
        do {
            return try dbQueue.read { db in
                var counts: [UUID: Int] = [:]
                
                // Define a struct to fetch the aggregated result
                struct PlaylistCountResult: FetchableRecord {
                    let playlistId: String
                    let trackCount: Int
                    
                    init(row: Row) throws {
                        playlistId = row["playlist_id"]
                        trackCount = row["track_count"]
                    }
                }
                
                // Get counts for regular playlists using GRDB
                let sql = """
                    SELECT playlist_id, COUNT(track_id) as track_count
                    FROM playlist_tracks
                    GROUP BY playlist_id
                """
                
                let results = try PlaylistCountResult.fetchAll(db, sql: sql)
                
                for result in results {
                    if let playlistId = UUID(uuidString: result.playlistId) {
                        counts[playlistId] = result.trackCount
                    }
                }
                
                return counts
            }
        } catch {
            Logger.error("Failed to get playlist track counts: \(error)")
            return [:]
        }
    }
    
    /// Get track count for a smart playlist without loading tracks
    func getSmartPlaylistTrackCount(_ playlist: Playlist) async -> Int {
        guard playlist.type == .smart,
              let criteria = playlist.smartCriteria else {
            return 0
        }
        
        do {
            return try await dbQueue.read { db in
                // Build the same query as getTracksForSmartPlaylist but only count
                var query = self.applyDuplicateFilter(Track.all())
                
                // Pre-load artists and genres for normalized matching
                let artists = try Artist.fetchAll(db)
                let genres = try Genre.fetchAll(db)
                
                // Build query from criteria
                if let whereClause = self.buildWhereClause(for: criteria, artists: artists, genres: genres) {
                    query = query.filter(whereClause)
                }
                
                // Apply limit if specified (for "Top 25" playlists)
                if let limit = criteria.limit {
                    // For count with limit, we need to fetch and count
                    let limitedCount = try query.limit(limit).fetchCount(db)
                    return limitedCount
                } else {
                    // Without limit, just count
                    return try query.fetchCount(db)
                }
            }
        } catch {
            Logger.error("Failed to get count for smart playlist '\(playlist.name)': \(error)")
            return 0
        }
    }
    
    /// Load all playlists from the database
    func loadAllPlaylists() -> [Playlist] {
        do {
            return try dbQueue.read { db in
                // Fetch all playlists
                var playlists = try Playlist.fetchAll(db)
                
                // Define the result structure for counts
                struct PlaylistCount: FetchableRecord {
                    let playlistId: String
                    let trackCount: Int
                    
                    init(row: Row) throws {
                        playlistId = row["playlist_id"]
                        trackCount = row["track_count"]
                    }
                }
                
                // Get track counts using SQL
                let sql = """
                    SELECT playlist_id, COUNT(track_id) as track_count
                    FROM playlist_tracks
                    GROUP BY playlist_id
                """
                
                let playlistCounts = try PlaylistCount.fetchAll(db, sql: sql)
                
                // Create a dictionary for quick lookup
                var countsByPlaylistId: [String: Int] = [:]
                for item in playlistCounts {
                    countsByPlaylistId[item.playlistId] = item.trackCount
                }
                
                // Update playlists with counts
                for index in playlists.indices {
                    if playlists[index].type == .regular {
                        // Set track count from database
                        playlists[index].trackCount = countsByPlaylistId[playlists[index].id.uuidString] ?? 0
                        // Keep tracks array empty for lazy loading
                        playlists[index].tracks = []
                    } else if playlists[index].type == .smart {
                        // For smart playlists, we'll need to calculate count on demand
                        // For now, set to 0 - will be updated when viewed
                        playlists[index].trackCount = 0
                        playlists[index].tracks = []
                    }
                }
                
                return playlists
            }
        } catch {
            Logger.error("Failed to load playlists: \(error)")
            return []
        }
    }
    
    /// Load tracks for a specific playlist on demand
    func loadTracksForPlaylist(_ playlistId: UUID) -> [Track] {
        do {
            return try dbQueue.read { db in
                // Get playlist tracks in order
                let playlistTracks = try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlistId.uuidString)
                    .order(PlaylistTrack.Columns.position)
                    .fetchAll(db)
                
                guard !playlistTracks.isEmpty else {
                    return []
                }
                
                let trackIds = playlistTracks.map { $0.trackId }
                
                // Fetch tracks for this playlist only
                let tracks = try applyDuplicateFilter(Track.all())
                    .filter(trackIds.contains(Track.Columns.trackId))
                    .fetchAll(db)
                
                // Create a dictionary for quick lookup
                var trackDict: [Int64: Track] = [:]
                for track in tracks {
                    if let trackId = track.trackId {
                        trackDict[trackId] = track
                    }
                }
                
                // Sort tracks according to playlist order
                let sortedTracks = playlistTracks.compactMap { playlistTrack in
                    trackDict[playlistTrack.trackId]
                }
                
                // Populate album artwork for the tracks
                var finalTracks = sortedTracks
                try populateAlbumArtworkForTracks(&finalTracks, db: db)
                
                return finalTracks
            }
        } catch {
            Logger.error("Failed to load tracks for playlist \(playlistId): \(error)")
            return []
        }
    }
    
    func deletePlaylist(_ playlistId: UUID) async throws {
        try await dbQueue.write { db in
            // Use GRDB's model deletion
            if let playlist = try Playlist
                .filter(Playlist.Columns.id == playlistId.uuidString)
                .fetchOne(db) {
                try playlist.delete(db)
            }
        }
    }
    
    /// Add a single track to a playlist without rebuilding entire playlist
    func addTrackToPlaylist(playlistId: UUID, track: Track) async -> Bool {
        guard let trackId = track.trackId else {
            Logger.error("Cannot add track - no database ID")
            return false
        }
        
        do {
            try await dbQueue.write { db in
                // Get current max position
                let maxPosition = try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlistId.uuidString)
                    .select(max(PlaylistTrack.Columns.position))
                    .fetchOne(db) ?? -1
                
                // Insert new track at the end
                let playlistTrack = PlaylistTrack(
                    playlistId: playlistId.uuidString,
                    trackId: trackId,
                    position: maxPosition + 1,
                    dateAdded: Date()
                )
                
                try playlistTrack.insert(db)
                Logger.info("Added single track to playlist")
            }
            return true
        } catch {
            Logger.error("Failed to add track to playlist: \(error)")
            return false
        }
    }
    
    /// Remove a single track from a playlist without rebuilding
    func removeTrackFromPlaylist(playlistId: UUID, trackId: Int64) async -> Bool {
        do {
            try await dbQueue.write { db in
                let deleted = try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlistId.uuidString)
                    .filter(PlaylistTrack.Columns.trackId == trackId)
                    .deleteAll(db)
                
                Logger.info("Removed \(deleted) track from playlist")
                
                // Reorder remaining tracks to close the gap
                let remainingTracks = try PlaylistTrack
                    .filter(PlaylistTrack.Columns.playlistId == playlistId.uuidString)
                    .order(PlaylistTrack.Columns.position)
                    .fetchAll(db)
                
                // Update positions
                for (index, track) in remainingTracks.enumerated() {
                    try db.execute(
                        sql: "UPDATE playlist_tracks SET position = ? WHERE playlist_id = ? AND track_id = ?",
                        arguments: [index, track.playlistId, track.trackId]
                    )
                }
            }
            return true
        } catch {
            Logger.error("Failed to remove track from playlist: \(error)")
            return false
        }
    }
}
