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
            
            // Get existing dateAdded values before deleting
            let existingDateAdded: [Int64: Date] = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlist.id.uuidString)
                .fetchAll(db)
                .reduce(into: [:]) { dict, playlistTrack in
                    dict[playlistTrack.trackId] = playlistTrack.dateAdded
                }
            
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
                let now = Date()
                var seenTrackIds = Set<Int64>()
                let playlistTracks = playlist.tracks.enumerated().compactMap { index, track -> PlaylistTrack? in
                    guard let trackId = track.trackId else {
                        Logger.warning("Track '\(track.title)' has no database ID, skipping")
                        return nil
                    }
                    guard seenTrackIds.insert(trackId).inserted else {
                        Logger.info("Skipping duplicate trackId \(trackId) in playlist '\(playlist.name)'")
                        return nil
                    }
                    
                    // Use existing dateAdded if available, otherwise stagger timestamps to preserve order
                    let dateAdded = existingDateAdded[trackId] ?? now.addingTimeInterval(TimeInterval(index))
                    
                    return PlaylistTrack(
                        playlistId: playlist.id.uuidString,
                        trackId: trackId,
                        position: index,
                        dateAdded: dateAdded
                    )
                }
                
                // Batch insert all tracks at once
                if !playlistTracks.isEmpty {
                    try PlaylistTrack.insertMany(playlistTracks, db: db)
                    Logger.info("Batch inserted \(playlistTracks.count) tracks to playlist")
                }
            }
        }
    }
    
    /// Persist a frozen snapshot of tracks for a smart playlist into `playlist_tracks`.
    ///
    /// `savePlaylistAsync` only writes track associations for regular playlists, so a
    /// non-auto-updating ("frozen") smart playlist needs this explicit path to store the
    /// one-time evaluation result. Once stored, the snapshot is loaded back exactly like a
    /// regular playlist via `loadTracksForPlaylist`, and its count is picked up by the
    /// generic `playlist_tracks` count query in `loadAllPlaylists`.
    func saveSmartPlaylistSnapshot(playlistId: UUID, tracks: [Track]) async throws {
        try await dbQueue.write { db in
            // Replace any existing snapshot
            try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == playlistId.uuidString)
                .deleteAll(db)

            let now = Date()
            var seenTrackIds = Set<Int64>()
            let playlistTracks = tracks.enumerated().compactMap { index, track -> PlaylistTrack? in
                guard let trackId = track.trackId else { return nil }
                guard seenTrackIds.insert(trackId).inserted else { return nil }
                return PlaylistTrack(
                    playlistId: playlistId.uuidString,
                    trackId: trackId,
                    position: index,
                    // Stagger timestamps so the snapshot's evaluated order is preserved
                    dateAdded: now.addingTimeInterval(TimeInterval(index))
                )
            }

            if !playlistTracks.isEmpty {
                try PlaylistTrack.insertMany(playlistTracks, db: db)
            }
            Logger.info("Saved frozen smart playlist snapshot with \(playlistTracks.count) tracks")
        }
    }

    /// Update playlist metadata (name, dateModified) and the display name of any pinned item referencing this playlist
    func updatePlaylistMetadata(_ playlist: Playlist) async throws {
        _ = try await dbQueue.write { db in
            try playlist.update(db, columns: [Playlist.Columns.name, Playlist.Columns.dateModified])

            try PinnedItem
                .filter(PinnedItem.Columns.itemType == PinnedItem.ItemType.playlist.rawValue)
                .filter(PinnedItem.Columns.playlistId == playlist.id.uuidString)
                .updateAll(db, PinnedItem.Columns.displayName.set(to: playlist.name))
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
    
    /// Batch-compute track counts for many smart playlists in a single read transaction,
    /// sharing one Artists/Genres fetch (and skipping it entirely when no rule needs it).
    /// Replaces N separate awaited reads (each of which previously re-fetched the full
    /// artist and genre tables) with one read for the whole set.
    func getSmartPlaylistTrackCounts(_ playlists: [Playlist]) async -> [UUID: Int] {
        let smart = playlists.filter { $0.type == .smart && $0.smartCriteria != nil }
        guard !smart.isEmpty else { return [:] }

        let criteriaList = smart.compactMap { $0.smartCriteria }
        let needArtists = criteriaList.contains { criteriaNeedsArtists($0) }
        let needGenres = criteriaList.contains { criteriaNeedsGenres($0) }

        do {
            return try await dbQueue.read { db in
                let artists = needArtists ? try Artist.fetchAll(db) : []
                let genres = needGenres ? try Genre.fetchAll(db) : []

                var counts: [UUID: Int] = [:]
                for playlist in smart {
                    guard let criteria = playlist.smartCriteria else { continue }
                    counts[playlist.id] = try self.countSmartPlaylistTracks(
                        criteria, artists: artists, genres: genres, db: db
                    )
                }
                return counts
            }
        } catch {
            Logger.error("Failed to batch smart playlist counts: \(error)")
            return [:]
        }
    }
    
    /// Load all playlists from the database
    func loadAllPlaylists() -> [Playlist] {
        do {
            return try dbQueue.read { db in
                // Fetch all playlists
                var playlists = try Playlist.order(Playlist.Columns.sortOrder).fetchAll(db)
                
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
                        // Frozen smart playlists store a snapshot in playlist_tracks, so their
                        // count is available here. Auto-updating ones have no snapshot rows and
                        // get their count computed on demand via updateSmartPlaylistCounts().
                        playlists[index].trackCount = countsByPlaylistId[playlists[index].id.uuidString] ?? 0
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
    
    /// Update the sort order of playlists
    func updatePlaylistsOrder(_ playlists: [Playlist]) async throws {
        try await dbQueue.write { db in
            for (index, playlist) in playlists.enumerated() {
                var updated = playlist
                updated.sortOrder = index
                try updated.update(db)
            }
        }
    }

    /// Load tracks for a specific playlist on demand
    func loadTracksForPlaylist(_ playlistId: UUID) -> [Track] {
        do {
            return try dbQueue.read { db in
                // Get playlist tracks in order with their dateAdded
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
                
                // Create dictionaries for quick lookup
                var trackDict: [Int64: Track] = [:]
                for track in tracks {
                    if let trackId = track.trackId {
                        trackDict[trackId] = track
                    }
                }
                
                var sortedTracks: [Track] = []
                for playlistTrack in playlistTracks {
                    if var track = trackDict[playlistTrack.trackId] {
                        track.dateAdded = playlistTrack.dateAdded
                        sortedTracks.append(track)
                    }
                }
                
                try populateAlbumArtworkForTracks(&sortedTracks, db: db)
                
                return sortedTracks
            }
        } catch {
            Logger.error("Failed to load tracks for playlist \(playlistId): \(error)")
            return []
        }
    }
    
    // MARK: - Incremental Track Mutations

    /// Append tracks that aren't already present, preserving existing rows and their order.
    /// Unlike savePlaylistAsync this never deletes existing associations, so it is safe to
    /// call even when the in-memory track list is partially loaded. Returns how many were
    /// actually inserted.
    @discardableResult
    func appendTracksToPlaylist(playlistId: UUID, tracks: [Track]) async throws -> Int {
        try await dbQueue.write { db in
            let pid = playlistId.uuidString

            var seen = try PlaylistTrack
                .select(PlaylistTrack.Columns.trackId, as: Int64.self)
                .filter(PlaylistTrack.Columns.playlistId == pid)
                .fetchSet(db)

            let maxPosition = try Int.fetchOne(db, PlaylistTrack
                .select(max(PlaylistTrack.Columns.position))
                .filter(PlaylistTrack.Columns.playlistId == pid)) ?? -1

            let now = Date()
            var rows: [PlaylistTrack] = []
            for track in tracks {
                guard let trackId = track.trackId, seen.insert(trackId).inserted else { continue }
                rows.append(PlaylistTrack(
                    playlistId: pid,
                    trackId: trackId,
                    position: maxPosition + 1 + rows.count,
                    // Stagger so the appended order is preserved under a "date added" sort.
                    dateAdded: now.addingTimeInterval(TimeInterval(rows.count))
                ))
            }

            if !rows.isEmpty {
                try PlaylistTrack.insertMany(rows, db: db)
                try self.touchPlaylistModified(pid, db: db, date: now)
            }
            return rows.count
        }
    }

    /// Remove the given tracks and renumber the remaining positions, in a single write.
    func removeTracksFromPlaylist(playlistId: UUID, trackIds: [Int64]) async throws {
        guard !trackIds.isEmpty else { return }
        try await dbQueue.write { db in
            let pid = playlistId.uuidString
            let idSet = Set(trackIds)

            try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == pid)
                .filter(idSet.contains(PlaylistTrack.Columns.trackId))
                .deleteAll(db)

            try self.renumberPlaylistPositions(pid, db: db)
            try self.touchPlaylistModified(pid, db: db, date: Date())
        }
    }

    /// Set the explicit order of a playlist's tracks by updating positions only, in a single
    /// write. Avoids the delete-all-then-reinsert-all cost of savePlaylistAsync and preserves
    /// each row's dateAdded.
    func setPlaylistTrackOrder(playlistId: UUID, orderedTrackIds: [Int64]) async throws {
        try await dbQueue.write { db in
            let pid = playlistId.uuidString

            let currentPositions = try PlaylistTrack
                .filter(PlaylistTrack.Columns.playlistId == pid)
                .fetchAll(db)
                .reduce(into: [Int64: Int]()) { dict, row in dict[row.trackId] = row.position }

            for (index, trackId) in orderedTrackIds.enumerated() where currentPositions[trackId] != index {
                try db.execute(
                    sql: "UPDATE playlist_tracks SET position = ? WHERE playlist_id = ? AND track_id = ?",
                    arguments: [index, pid, trackId]
                )
            }

            try self.touchPlaylistModified(pid, db: db, date: Date())
        }
    }

    /// Renumber a playlist's positions to a contiguous 0-based sequence in current order.
    /// Only rows whose position actually changes are updated.
    private func renumberPlaylistPositions(_ playlistId: String, db: Database) throws {
        let remaining = try PlaylistTrack
            .filter(PlaylistTrack.Columns.playlistId == playlistId)
            .order(PlaylistTrack.Columns.position)
            .fetchAll(db)

        for (index, playlistTrack) in remaining.enumerated() where playlistTrack.position != index {
            try db.execute(
                sql: "UPDATE playlist_tracks SET position = ? WHERE playlist_id = ? AND track_id = ?",
                arguments: [index, playlistId, playlistTrack.trackId]
            )
        }
    }

    /// Bump a playlist's date_modified without rewriting its track associations.
    private func touchPlaylistModified(_ playlistId: String, db: Database, date: Date) throws {
        try db.execute(
            sql: "UPDATE playlists SET date_modified = ? WHERE id = ?",
            arguments: [date, playlistId]
        )
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
