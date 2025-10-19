//
// DatabaseManager class extension
//
// This extension contains all search-related query methods using FTS5.
//

import Foundation
import GRDB

extension DatabaseManager {
    /// Search tracks using FTS5 with language-aware query strategy
    func searchTracksUsingFTS(_ searchText: String) -> [Track] {
        do {
            var tracks = try dbQueue.read { db in
                let ftsQuery = buildAdaptiveFTS5Query(searchText)

                let matchingTrackIds = try Int64.fetchAll(db, sql: """
                    SELECT track_id
                    FROM tracks_fts
                    WHERE tracks_fts MATCH ?
                    ORDER BY rank
                    """, arguments: [ftsQuery])
                
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
                let prefixQuery = buildAdaptiveFTS5Query(searchText)
                
                // Build the WHERE clause based on exclusions
                let whereClause: String
                let arguments: StatementArguments
                
                if excludingTrackIds.isEmpty {
                    whereClause = "WHERE tracks_fts MATCH ?"
                    arguments = [prefixQuery]
                } else {
                    let excludedIds = Array(excludingTrackIds)
                    let placeholders = databaseQuestionMarks(count: excludedIds.count)
                    whereClause = "WHERE tracks_fts MATCH ? AND t.id NOT IN (\(placeholders))"
                    
                    var args: [DatabaseValueConvertible] = [prefixQuery]
                    args.append(contentsOf: excludedIds)
                    arguments = StatementArguments(args)
                }
                
                return try Track.fetchAll(
                    db,
                    sql: """
                    SELECT t.*
                    FROM tracks t
                    JOIN tracks_fts fts ON t.id = fts.track_id
                    \(whereClause)
                    ORDER BY rank
                    LIMIT 200
                    """,
                    arguments: arguments
                )
            }
            
            populateAlbumArtworkForTracks(&tracks)
            
            return tracks
        } catch {
            Logger.error("FTS playlist search failed: \(error)")
            return []
        }
    }

    // MARK: - Helper Methods
    
    /// FTS query builder with support for handling special characters
    private func buildFTS5Query(_ searchText: String) -> String {
        let tokens = searchText.split(separator: " ").map { String($0) }
        
        let processedTokens = tokens.map { token -> String in
            let tokenStr = String(token)
            
            let problematicChars = CharacterSet(charactersIn: "\"*^:()[]{}~-")
            
            if tokenStr.rangeOfCharacter(from: problematicChars) != nil {
                let escaped = tokenStr.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            } else if tokenStr.contains(".") {
                let escaped = tokenStr.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\" OR \"\(escaped)\"*"
            } else {
                return "\(tokenStr)*"
            }
        }
        
        return processedTokens.joined(separator: " AND ")
    }
    
    /// Build FTS query without stemming for non-ASCII characters
    private func buildFTS5QueryWithoutStemming(_ searchText: String) -> String {
        let tokens = searchText.split(separator: " ").map { String($0) }
        
        let processedTokens = tokens.map { token -> String in
            let tokenStr = String(token)
            let escaped = tokenStr.replacingOccurrences(of: "\"", with: "\"\"")
            
            // Bypass stemming and do prefix matching at character level
            return "\"\(escaped)\"*"
        }
        
        return processedTokens.joined(separator: " ")
    }
    
    /// Determines the appropriate FTS query based on search text character type
    private func buildAdaptiveFTS5Query(_ searchText: String) -> String {
        let containsNonASCII = searchText.unicodeScalars.contains { !$0.isASCII }
        
        if containsNonASCII {
            // For non-ASCII, use phrase matching to bypass porter stemmer
            // This allows substring matching for CJK characters
            return buildFTS5QueryWithoutStemming(searchText)
        } else {
            // For ASCII/English, use normal query with stemming
            return buildFTS5Query(searchText)
        }
    }
    
    /// Generate SQL placeholders for IN clause
    private func databaseQuestionMarks(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }
}
