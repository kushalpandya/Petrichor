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
            return try dbQueue.read { db in
                // First get matching track IDs from FTS
                let pattern = FTS5Pattern(matchingAllTokensIn: query)
                let trackIds = try Row
                    .fetchAll(db, sql: """
                        SELECT track_id
                        FROM tracks_fts
                        WHERE tracks_fts MATCH ?
                        ORDER BY rank
                    """, arguments: [pattern])
                    .compactMap { row in
                        row["track_id"] as Int64?
                    }
                
                guard !trackIds.isEmpty else { return [] }
                
                // Fetch lightweight tracks for those IDs
                var tracks = try Track.lightweightRequest()
                    .filter(trackIds.contains(Track.Columns.trackId))
                    .fetchAll(db)
                
                // Sort by the FTS rank order
                let idToIndex = Dictionary(uniqueKeysWithValues: trackIds.enumerated().map { ($1, $0) })
                tracks.sort { track1, track2 in
                    let index1 = idToIndex[track1.trackId ?? -1] ?? Int.max
                    let index2 = idToIndex[track2.trackId ?? -1] ?? Int.max
                    return index1 < index2
                }
                
                // Populate album artwork
                populateAlbumArtworkForTracks(&tracks)
                
                return tracks
            }
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
