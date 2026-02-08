//
//  DatabaseManager class extension
//  Petrichor
//
//  Smart playlist query builder for fetching tracks from database
//  based on Smart Playlist criteria
//

import Foundation
import GRDB

extension DatabaseManager {
    // MARK: - Smart Playlist Query Builder
    
    /// Build and execute a database query for a smart playlist
    func getTracksForSmartPlaylist(_ playlist: Playlist) async throws -> [Track] {
        guard playlist.type == .smart,
              let criteria = playlist.smartCriteria else {
            return []
        }
        
        // Pre-load artists and genres for normalized matching
        let artists = try await dbQueue.read { db in
            try Artist.fetchAll(db)
        }
        
        let genres = try await dbQueue.read { db in
            try Genre.fetchAll(db)
        }
        
        return try await dbQueue.read { db in
            // Start with base query
            var query = self.applyDuplicateFilter(Track.all())
            
            // Build query from criteria
            if let whereClause = self.buildWhereClause(for: criteria, artists: artists, genres: genres) {
                query = query.filter(whereClause)
            }
            
            // Apply sorting
            query = self.applySorting(to: query, criteria: criteria)
            
            // Apply limit
            if let limit = criteria.limit {
                query = query.limit(limit)
            }
            
            // Fetch tracks
            var tracks = try query.fetchAll(db)
            
            // Populate album artwork using existing method
            try self.populateAlbumArtworkForTracks(&tracks, db: db)
            
            return tracks
        }
    }
    
    /// Get tracks for a smart playlist synchronously (for use in pinned items)
    func getTracksForSmartPlaylistSync(_ playlist: Playlist) -> [Track] {
        guard playlist.type == .smart,
              let criteria = playlist.smartCriteria else {
            return []
        }
        
        do {
            // Load artists and genres synchronously
            let artists = try dbQueue.read { db in
                try Artist.fetchAll(db)
            }
            
            let genres = try dbQueue.read { db in
                try Genre.fetchAll(db)
            }
            
            return try dbQueue.read { db in
                // Start with base query
                var query = self.applyDuplicateFilter(Track.all())
                
                // Build query from criteria
                if let whereClause = self.buildWhereClause(for: criteria, artists: artists, genres: genres) {
                    query = query.filter(whereClause)
                }
                
                // Apply sorting
                query = self.applySorting(to: query, criteria: criteria)
                
                // Apply limit
                if let limit = criteria.limit {
                    query = query.limit(limit)
                }
                
                // Fetch tracks
                var tracks = try query.fetchAll(db)
                
                // Populate album artwork
                try self.populateAlbumArtworkForTracks(&tracks, db: db)
                
                return tracks
            }
        } catch {
            Logger.error("Failed to get tracks for smart playlist '\(playlist.name)': \(error)")
            return []
        }
    }
    
    /// Build WHERE clause from smart playlist criteria
    internal func buildWhereClause(for criteria: SmartPlaylistCriteria, artists: [Artist], genres: [Genre]) -> SQLExpression? {
        let expressions = criteria.rules.compactMap { rule in
            buildExpression(for: rule, artists: artists, genres: genres)
        }
        
        guard !expressions.isEmpty else { return nil }
        
        switch criteria.matchType {
        case .all:
            // AND all conditions together
            guard let first = expressions.first else { return nil }
            return expressions.dropFirst().reduce(first) { result, expr in
                result && expr
            }
        case .any:
            // OR all conditions together
            guard let first = expressions.first else { return nil }
            return expressions.dropFirst().reduce(first) { result, expr in
                result || expr
            }
        }
    }
    
    /// Build SQL expression for a single rule
    private func buildExpression(for rule: SmartPlaylistCriteria.Rule, artists: [Artist], genres: [Genre]) -> SQLExpression? {
        switch rule.field {
        case "isFavorite":
            return buildBooleanExpression(column: Track.Columns.isFavorite, rule: rule)
            
        case "playCount":
            return buildNumericExpression(column: Track.Columns.playCount, rule: rule)
            
        case "lastPlayedDate":
            return buildDateExpression(column: Track.Columns.lastPlayedDate, rule: rule)
            
        case "dateAdded":
            return buildDateExpression(column: Track.Columns.dateAdded, rule: rule)
            
        case "title":
            return buildStringExpression(column: Track.Columns.title, rule: rule)
            
        case "artist":
            return buildArtistExpression(rule: rule, artists: artists)
            
        case "album":
            return buildStringExpression(column: Track.Columns.album, rule: rule)
            
        case "albumArtist":
            return buildStringExpression(column: Track.Columns.albumArtist, rule: rule)
            
        case "genre":
            return buildGenreExpression(rule: rule, genres: genres)
            
        case "year":
            return buildYearExpression(column: Track.Columns.year, rule: rule)
            
        case "composer":
            return buildComposerExpression(rule: rule, artists: artists)
            
        case "duration":
            return buildNumericExpression(column: Track.Columns.duration, rule: rule)
            
        default:
            Logger.warning("Unsupported smart playlist field: \(rule.field)")
            return nil
        }
    }
    
    // MARK: - Helper Methods
    
    /// Build LIKE pattern based on condition
    private func buildLikePattern(for value: String, condition: SmartPlaylistCriteria.Condition) -> String {
        switch condition {
        case .contains:
            return "%\(value)%"
        case .startsWith:
            return "\(value)%"
        case .endsWith:
            return "%\(value)"
        default:
            return "%\(value)%"
        }
    }
    
    // MARK: - Expression Builders
    
    private func buildBooleanExpression(column: Column, rule: SmartPlaylistCriteria.Rule) -> SQLExpression? {
        let value = rule.value.lowercased() == "true"
        
        switch rule.condition {
        case .equals:
            return column == value
        default:
            return nil
        }
    }
    
    private func buildStringExpression(column: Column, rule: SmartPlaylistCriteria.Rule) -> SQLExpression? {
        switch rule.condition {
        case .equals:
            // Case-insensitive exact match using COLLATE NOCASE
            return column.collating(.nocase) == rule.value
        case .contains, .startsWith, .endsWith:
            // Case-insensitive pattern matching
            let pattern = buildLikePattern(for: rule.value, condition: rule.condition)
            return column.collating(.nocase).like(pattern)
        default:
            return nil
        }
    }
    
    private func buildNumericExpression(column: Column, rule: SmartPlaylistCriteria.Rule) -> SQLExpression? {
        guard let numericValue = Double(rule.value) else { return nil }
        
        switch rule.condition {
        case .equals:
            return column == numericValue
        case .greaterThan:
            return column > numericValue
        case .greaterThanOrEqual:
            return column >= numericValue
        case .lessThan:
            return column < numericValue
        case .lessThanOrEqual:
            return column <= numericValue
        default:
            return nil
        }
    }
    
    private func buildDateExpression(column: Column, rule: SmartPlaylistCriteria.Rule) -> SQLExpression? {
        // Handle "Xdays" format for relative dates
        if rule.value.hasSuffix("days") {
            let daysString = rule.value.replacingOccurrences(of: "days", with: "")
            guard let days = Int(daysString) else { return nil }
            
            let cutoffDate = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
            
            switch rule.condition {
            case .greaterThan:
                // For "in the last X days", we want dates greater than the cutoff
                return column != nil && column > cutoffDate
            case .lessThan:
                return column != nil && column < cutoffDate
            default:
                return nil
            }
        }
        
        // Handle absolute date comparisons if needed in the future
        return nil
    }
    
    private func buildYearExpression(column: Column, rule: SmartPlaylistCriteria.Rule) -> SQLExpression? {
        // For year comparisons, we'll use string comparison since years are stored as strings
        switch rule.condition {
        case .equals:
            return column == rule.value
        case .greaterThan, .lessThan:
            // For numeric comparisons on year strings, we need to ensure proper ordering
            // We'll compare as strings which works for 4-digit years
            if rule.condition == .greaterThan {
                return column > rule.value
            } else {
                return column < rule.value
            }
        default:
            return buildStringExpression(column: column, rule: rule)
        }
    }
    
    // MARK: - Normalized Table Expressions
    
    private func buildArtistExpression(rule: SmartPlaylistCriteria.Rule, artists: [Artist]) -> SQLExpression? {
        switch rule.condition {
        case .equals:
            // Find matching artists by name or normalized name
            let normalizedSearch = ArtistParser.normalizeArtistName(rule.value)
            let matchingArtistIds = artists.compactMap { artist -> Int64? in
                if artist.name == rule.value || artist.normalizedName == normalizedSearch {
                    return artist.id
                }
                return nil
            }
            
            if !matchingArtistIds.isEmpty {
                // Check track_artists table for these artist IDs
                return matchingArtistIds.contains(TrackArtist.Columns.artistId) &&
                       TrackArtist.Columns.trackId == Track.Columns.trackId
            }
            
            // Fall back to denormalized column
            return Track.Columns.artist.collating(.nocase) == rule.value
            
        case .contains, .startsWith, .endsWith:
            // For partial matching, find artists whose normalized names match the pattern
            let normalizedSearch = ArtistParser.normalizeArtistName(rule.value)
            let pattern = buildLikePattern(for: normalizedSearch, condition: rule.condition)
            
            let matchingArtistIds = artists.compactMap { artist -> Int64? in
                if matchesPattern(artist.normalizedName, pattern: pattern) {
                    return artist.id
                }
                return nil
            }
            
            if !matchingArtistIds.isEmpty {
                // For now, fall back to denormalized column with the pattern
                // This is because we can't easily create complex subqueries without SQL literals
                let stringPattern = buildLikePattern(for: rule.value, condition: rule.condition)
                return Track.Columns.artist.collating(.nocase).like(stringPattern)
            }
            
            // Fall back to denormalized column
            let stringPattern = buildLikePattern(for: rule.value, condition: rule.condition)
            return Track.Columns.artist.collating(.nocase).like(stringPattern)
            
        default:
            return buildStringExpression(column: Track.Columns.artist, rule: rule)
        }
    }
    
    private func buildGenreExpression(rule: SmartPlaylistCriteria.Rule, genres: [Genre]) -> SQLExpression? {
        switch rule.condition {
        case .equals:
            // Find matching genre by exact name
            let matchingGenreIds = genres.compactMap { genre -> Int64? in
                if genre.name == rule.value {
                    return genre.id
                }
                return nil
            }
            
            if !matchingGenreIds.isEmpty {
                // For now, fall back to denormalized column
                // This is because we can't easily create complex subqueries without SQL literals
                return Track.Columns.genre.collating(.nocase) == rule.value
            }
            
            // Fall back to denormalized column
            return Track.Columns.genre.collating(.nocase) == rule.value
            
        case .contains, .startsWith, .endsWith:
            // For partial matching
            let pattern = buildLikePattern(for: rule.value, condition: rule.condition)
            
            // Use denormalized column for genre pattern matching
            return Track.Columns.genre.collating(.nocase).like(pattern)
            
        default:
            return buildStringExpression(column: Track.Columns.genre, rule: rule)
        }
    }
    
    private func buildComposerExpression(rule: SmartPlaylistCriteria.Rule, artists: [Artist]) -> SQLExpression? {
        // For composer, we'll primarily use the denormalized column
        // since the normalized data is in track_artists with role='composer'
        // and we can't easily query that without SQL literals
        buildStringExpression(column: Track.Columns.composer, rule: rule)
    }
    
    /// Helper function to check if a string matches a SQL LIKE pattern
    private func matchesPattern(_ string: String, pattern: String) -> Bool {
        // Convert SQL LIKE pattern to regex
        var regexPattern = pattern
            .replacingOccurrences(of: "%", with: ".*")
            .replacingOccurrences(of: "_", with: ".")
        
        // Escape regex special characters
        let specialChars = ["[", "]", "(", ")", "{", "}", "^", "$", "+", "?", "|", "\\", ".", "*"]
        for char in specialChars {
            if char != "." && char != "*" { // Don't escape our wildcards
                regexPattern = regexPattern.replacingOccurrences(of: char, with: "\\\(char)")
            }
        }
        
        do {
            let regex = try NSRegularExpression(pattern: "^" + regexPattern + "$", options: .caseInsensitive)
            let range = NSRange(location: 0, length: string.utf16.count)
            return regex.firstMatch(in: string, options: [], range: range) != nil
        } catch {
            // If regex fails, fall back to simple contains check
            return string.lowercased().contains(pattern.replacingOccurrences(of: "%", with: "").lowercased())
        }
    }
    
    // MARK: - Sorting
    
    private func applySorting(to query: QueryInterfaceRequest<Track>, criteria: SmartPlaylistCriteria) -> QueryInterfaceRequest<Track> {
        guard let sortBy = criteria.sortBy else { return query }
        
        let ascending = criteria.sortAscending
        
        switch sortBy {
        case "title":
            return ascending ? query.order(Track.Columns.title) : query.order(Track.Columns.title.desc)
        case "artist":
            return ascending ? query.order(Track.Columns.artist) : query.order(Track.Columns.artist.desc)
        case "album":
            return ascending ? query.order(Track.Columns.album) : query.order(Track.Columns.album.desc)
        case "playCount":
            return ascending ? query.order(Track.Columns.playCount) : query.order(Track.Columns.playCount.desc)
        case "lastPlayedDate":
            // Handle nil dates by treating them as distant past/future
            let nilDate = ascending ? Date.distantPast : Date.distantFuture
            return ascending
                ? query.order(Track.Columns.lastPlayedDate ?? nilDate)
                : query.order((Track.Columns.lastPlayedDate ?? nilDate).desc)
        case "dateAdded":
            return ascending ? query.order(Track.Columns.dateAdded) : query.order(Track.Columns.dateAdded.desc)
        case "duration":
            return ascending ? query.order(Track.Columns.duration) : query.order(Track.Columns.duration.desc)
        case "year":
            return ascending ? query.order(Track.Columns.year) : query.order(Track.Columns.year.desc)
        default:
            return query
        }
    }
}
