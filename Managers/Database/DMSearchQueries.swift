//
// DatabaseManager class extension
//
// This extension contains all search-related query methods using FTS5.
//

import Foundation
import GRDB

extension DatabaseManager {
    /// Search tracks using FTS5 for general search
    func searchTracksUsingFTS(_ query: String) -> [Track] {
        do {
            var tracks = try dbQueue.read { db in
                let pattern = FTS5Pattern(matchingAllTokensIn: query)
                let matchingTrackIds = try Int64.fetchAll(db, sql: """
                    SELECT track_id
                    FROM tracks_fts
                    WHERE tracks_fts MATCH ?
                    ORDER BY rank
                    """, arguments: [pattern])
                
                guard !matchingTrackIds.isEmpty else { return [Track]() }
                
                return try Track.lightweightRequest()
                    .filter(matchingTrackIds.contains(Track.Columns.trackId))
                    .fetchAll(db)
            }
            
            populateAlbumArtworkForTracks(&tracks)
            
            return tracks
        } catch {
            Logger.error("FTS search failed: \(error)")
            return []
        }
    }

    /// Search tracks for playlist addition with exclusions
    func searchTracksForPlaylist(_ searchText: String, excludingTrackIds: Set<Int64> = []) -> [Track] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        do {
            var tracks = try dbQueue.read { db in
                let searchPattern = FTS5Pattern(matchingAllTokensIn: searchText)
                
                if excludingTrackIds.isEmpty {
                    // Simple case - no exclusions
                    return try Track.fetchAll(
                        db,
                        sql: """
                        SELECT t.*
                        FROM tracks t
                        JOIN tracks_fts fts ON t.id = fts.track_id
                        WHERE tracks_fts MATCH ?
                        ORDER BY rank
                        LIMIT 200
                        """,
                        arguments: [searchPattern]
                    )
                } else {
                    // With exclusions - still need some SQL
                    let excludedIds = Array(excludingTrackIds)
                    let placeholders = databaseQuestionMarks(count: excludedIds.count)
                    
                    var arguments: [DatabaseValueConvertible] = [searchPattern]
                    arguments.append(contentsOf: excludedIds)
                    
                    return try Track.fetchAll(
                        db,
                        sql: """
                        SELECT t.*
                        FROM tracks t
                        JOIN tracks_fts fts ON t.id = fts.track_id
                        WHERE tracks_fts MATCH ? AND t.id NOT IN (\(placeholders))
                        ORDER BY rank
                        LIMIT 200
                        """,
                        arguments: StatementArguments(arguments)
                    )
                }
            }
            
            populateAlbumArtworkForTracks(&tracks)
            
            return tracks
        } catch {
            Logger.error("FTS playlist search failed: \(error)")
            return []
        }
    }
    
    /// Fallback search using LIKE queries (when FTS is not available)
    func searchTracksUsingLike(_ searchText: String) -> [Track] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        do {
            var tracks = try dbQueue.read { db in
                let searchPattern = "%\(searchText)%"
                
                return try Track
                    .filter(
                        Track.Columns.title.like(searchPattern) ||
                        Track.Columns.artist.like(searchPattern) ||
                        Track.Columns.album.like(searchPattern) ||
                        Track.Columns.albumArtist.like(searchPattern) ||
                        Track.Columns.composer.like(searchPattern) ||
                        Track.Columns.genre.like(searchPattern)
                    )
                    .limit(500)
                    .fetchAll(db)
            }
            
            populateAlbumArtworkForTracks(&tracks)
            
            return tracks
        } catch {
            Logger.error("LIKE search failed: \(error)")
            return []
        }
    }
    
    // MARK: - Helper Methods
    
    /// Generate SQL placeholders for IN clause
    private func databaseQuestionMarks(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }
}
