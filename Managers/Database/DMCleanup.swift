//
// DatabaseManager class extension
//
// This extension contains methods for cleaning up orphaned database entries
// on folder updates when tracks are removed or updated.
//

import Foundation
import GRDB

extension DatabaseManager {
    /// Clean up all orphaned data in the database
    func cleanupOrphanedData() async throws {
        Logger.info("Starting comprehensive database cleanup...")
        
        try await dbQueue.write { db in
            var deletedCounts = [String: Int]()
            
            // 1. Clean up orphaned entries in junction tables first
            // Using raw SQL for these as GRDB doesn't have clean syntax for NOT IN subqueries
            
            // Remove track_artists entries where track no longer exists
            try db.execute(
                sql: """
                DELETE FROM track_artists
                WHERE track_id NOT IN (SELECT id FROM tracks)
                """
            )
            deletedCounts["track_artists"] = Int(db.changesCount)
            
            // Remove track_genres entries where track no longer exists
            try db.execute(
                sql: """
                DELETE FROM track_genres
                WHERE track_id NOT IN (SELECT id FROM tracks)
                """
            )
            deletedCounts["track_genres"] = Int(db.changesCount)
            
            // Remove album_artists entries where album no longer exists
            try db.execute(
                sql: """
                DELETE FROM album_artists
                WHERE album_id NOT IN (SELECT id FROM albums)
                """
            )
            deletedCounts["album_artists"] = Int(db.changesCount)
            
            // Remove playlist_tracks entries where track no longer exists
            try db.execute(
                sql: """
                DELETE FROM playlist_tracks
                WHERE track_id NOT IN (SELECT id FROM tracks)
                """
            )
            deletedCounts["playlist_tracks"] = Int(db.changesCount)
            
            deletedCounts.merge(try deleteOrphanedEntities(in: db)) { $0 + $1 }
            
            // 3. Clean up other orphaned data using raw SQL
            
            // Check if extended_metadata table exists before cleaning
            let hasExtendedMetadata = try db.tableExists("extended_metadata")
            if hasExtendedMetadata {
                try db.execute(
                    sql: """
                    DELETE FROM extended_metadata
                    WHERE track_id NOT IN (SELECT id FROM tracks)
                    """
                )
                deletedCounts["extended_metadata"] = Int(db.changesCount)
            }
            
            deletedCounts["pinned_items"] = try deleteOrphanedPins(in: db)
            
            // Log cleanup results
            var totalDeleted = 0
            for (table, count) in deletedCounts where count > 0 {
                Logger.info("Cleaned up \(count) orphaned entries from \(table)")
                totalDeleted += count
            }
            
            if totalDeleted > 0 {
                Logger.info("Database cleanup completed: \(totalDeleted) total orphaned entries removed")
            } else {
                Logger.info("Database cleanup completed: No orphaned entries found")
            }
        }
    }
    
    /// Remove specific tracks and clean up entities and pins orphaned by them.
    func cleanupAfterTrackRemoval(_ tracks: [Track]) async throws {
        let trackIds = tracks.compactMap(\.trackId)
        guard !trackIds.isEmpty else { return }
        
        Logger.info("Cleaning up after removing \(trackIds.count) tracks...")
        
        try await dbQueue.write { db in
            var removedTrackCount = 0
            for start in stride(from: 0, to: trackIds.count, by: 500) {
                let ids = Array(trackIds[start..<min(start + 500, trackIds.count)])
                removedTrackCount += try Track
                    .filter(ids.contains(Track.Columns.trackId))
                    .deleteAll(db)
            }
            Logger.info("Removed \(removedTrackCount) tracks that no longer exist")

            for (table, count) in try deleteOrphanedEntities(in: db) where count > 0 {
                Logger.info("Removed \(count) orphaned \(table)")
            }

            let removedPinCount = try deleteOrphanedPins(in: db)
            if removedPinCount > 0 {
                Logger.info("Removed \(removedPinCount) orphaned pinned items")
            }
        }
    }

    /// Albums go first because deleting one can make its album-only artists orphaned.
    private func deleteOrphanedEntities(in db: Database) throws -> [String: Int] {
        var deletedCounts = [String: Int]()

        try db.execute(sql: "DELETE FROM albums WHERE NOT EXISTS (SELECT 1 FROM tracks WHERE tracks.album_id = albums.id)")
        deletedCounts["albums"] = Int(db.changesCount)

        try db.execute(
            sql: """
            DELETE FROM artists
            WHERE NOT EXISTS (SELECT 1 FROM track_artists WHERE track_artists.artist_id = artists.id)
              AND NOT EXISTS (SELECT 1 FROM album_artists WHERE album_artists.artist_id = artists.id)
            """
        )
        deletedCounts["artists"] = Int(db.changesCount)

        try db.execute(sql: "DELETE FROM genres WHERE NOT EXISTS (SELECT 1 FROM track_genres WHERE track_genres.genre_id = genres.id)")
        deletedCounts["genres"] = Int(db.changesCount)

        return deletedCounts
    }

    private func deleteOrphanedPins(in db: Database) throws -> Int {
        try db.execute(
            sql: """
            DELETE FROM pinned_items
            WHERE (artist_id IS NOT NULL AND artist_id NOT IN (SELECT id FROM artists))
               OR (album_id IS NOT NULL AND album_id NOT IN (SELECT id FROM albums))
               OR (playlist_id IS NOT NULL AND playlist_id NOT IN (SELECT id FROM playlists))
            """
        )
        return Int(db.changesCount)
    }
}
