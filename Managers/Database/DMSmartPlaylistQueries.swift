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
    // MARK: - Normalized-table need detection

    /// Whether evaluating these rules requires the normalized Artists table. Artist matching
    /// now resolves against the denormalized column in all cases, so this never requires the
    /// fetch; kept as a gate for clarity/future use.
    func criteriaNeedsArtists(_ criteria: SmartPlaylistCriteria) -> Bool {
        false
    }

    /// Whether evaluating these rules requires the normalized Genres table.
    /// Genre matching always resolves against the denormalized column, so this is only
    /// kept as a gate for clarity/future use; it currently never requires the fetch.
    func criteriaNeedsGenres(_ criteria: SmartPlaylistCriteria) -> Bool {
        false
    }

    // MARK: - Smart Playlist Query Builder

    /// The filtered (not yet sorted or limited) track query for a smart playlist's criteria.
    /// Shared by the track-fetch and count paths so the filter logic lives in one place.
    func smartPlaylistFilteredQuery(
        _ criteria: SmartPlaylistCriteria,
        artists: [Artist],
        genres: [Genre]
    ) -> QueryInterfaceRequest<Track> {
        var query = applyDuplicateFilter(Track.all())
        if let whereClause = buildWhereClause(for: criteria, artists: artists, genres: genres) {
            query = query.filter(whereClause)
        }
        return query
    }

    /// Count tracks matching a criteria (honoring its limit) within an already-open read.
    func countSmartPlaylistTracks(
        _ criteria: SmartPlaylistCriteria,
        artists: [Artist],
        genres: [Genre],
        db: Database
    ) throws -> Int {
        let query = smartPlaylistFilteredQuery(criteria, artists: artists, genres: genres)
        if let limit = criteria.limit {
            return try query.limit(limit).fetchCount(db)
        }
        return try query.fetchCount(db)
    }

    /// Count how many library tracks match a criteria's rules, ignoring any limit. Used by
    /// the editor's live "Matches N songs" footer to convey how selective the rules are
    /// (the limit is a separate, explicit cap). Opens its own read.
    func countMatchesForCriteria(_ criteria: SmartPlaylistCriteria) async -> Int {
        do {
            return try await dbQueue.read { db in
                let artists = self.criteriaNeedsArtists(criteria) ? try Artist.fetchAll(db) : []
                let genres = self.criteriaNeedsGenres(criteria) ? try Genre.fetchAll(db) : []
                return try self.smartPlaylistFilteredQuery(criteria, artists: artists, genres: genres).fetchCount(db)
            }
        } catch {
            Logger.error("Failed to count smart playlist matches: \(error)")
            return 0
        }
    }

    /// Build and run a smart playlist's full track query (filter, sort, limit, artwork) within
    /// an already-open read, loading the normalized tables only when a rule needs them.
    private func fetchSmartPlaylistTracks(for criteria: SmartPlaylistCriteria, db: Database) throws -> [Track] {
        let artists = criteriaNeedsArtists(criteria) ? try Artist.fetchAll(db) : []
        let genres = criteriaNeedsGenres(criteria) ? try Genre.fetchAll(db) : []

        var query = smartPlaylistFilteredQuery(criteria, artists: artists, genres: genres)
        query = applySorting(to: query, criteria: criteria)
        if let limit = criteria.limit {
            query = query.limit(limit)
        }

        var tracks = try query.fetchAll(db)
        try populateAlbumArtworkForTracks(&tracks, db: db)
        return tracks
    }

    /// Build and execute a database query for a smart playlist
    func getTracksForSmartPlaylist(_ playlist: Playlist) async throws -> [Track] {
        guard playlist.type == .smart,
              let criteria = playlist.smartCriteria else {
            return []
        }

        return try await dbQueue.read { db in
            try self.fetchSmartPlaylistTracks(for: criteria, db: db)
        }
    }

    /// Get tracks for a smart playlist synchronously (for use in pinned items)
    func getTracksForSmartPlaylistSync(_ playlist: Playlist) -> [Track] {
        guard playlist.type == .smart,
              let criteria = playlist.smartCriteria else {
            return []
        }

        do {
            return try dbQueue.read { db in
                try self.fetchSmartPlaylistTracks(for: criteria, db: db)
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

        case "trackNumber":
            return buildNumericExpression(column: Track.Columns.trackNumber, rule: rule)

        case "discNumber":
            return buildNumericExpression(column: Track.Columns.discNumber, rule: rule)

        case "filename":
            return buildStringExpression(column: Track.Columns.filename, rule: rule)

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
            // Match the whole integer unit so a fractional-second duration still matches a
            // "M:SS" rule; for integer columns (play count, track/disc number) this is exact.
            return column >= numericValue && column < numericValue + 1
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
        
        // Handle absolute calendar dates ("yyyy-MM-dd"), matching by day in the local
        // calendar so the stored time-of-day is ignored.
        if let day = SmartPlaylistDate.date(from: rule.value) {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: day)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }

            switch rule.condition {
            case .equals:
                // "on" that day
                return column != nil && column >= startOfDay && column < nextDay
            case .greaterThan:
                // "after" that day (strictly later than the whole day)
                return column != nil && column >= nextDay
            case .lessThan:
                // "before" the start of that day
                return column != nil && column < startOfDay
            default:
                return nil
            }
        }

        return nil
    }
    
    private func buildYearExpression(column: Column, rule: SmartPlaylistCriteria.Rule) -> SQLExpression? {
        // Year is stored as text. Exact match is a plain string compare, but greater/less
        // must compare numerically: a lexicographic compare would match non-numeric years
        // like "Unknown Year" (which sorts after digits). CAST makes the compare numeric and
        // turns non-numeric years into 0, which we exclude.
        switch rule.condition {
        case .equals:
            return column == rule.value
        case .greaterThan, .lessThan:
            guard let yearValue = Int(rule.value) else { return nil }
            let numericYear = cast(column, as: .integer)
            if rule.condition == .greaterThan {
                return numericYear > yearValue
            } else {
                return numericYear > 0 && numericYear < yearValue
            }
        default:
            return buildStringExpression(column: column, rule: rule)
        }
    }
    
    // MARK: - Normalized Table Expressions
    
    private func buildArtistExpression(rule: SmartPlaylistCriteria.Rule, artists: [Artist]) -> SQLExpression? {
        // Match against the denormalized artist column. Querying the normalized track_artists
        // table here would need a raw SQL literal subquery, so we accept the same limitation
        // as genre/composer matching and compare the track's own artist string.
        switch rule.condition {
        case .equals:
            return Track.Columns.artist.collating(.nocase) == rule.value
        case .contains, .startsWith, .endsWith:
            let pattern = buildLikePattern(for: rule.value, condition: rule.condition)
            return Track.Columns.artist.collating(.nocase).like(pattern)
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
        case "genre":
            return ascending ? query.order(Track.Columns.genre) : query.order(Track.Columns.genre.desc)
        case "trackNumber":
            return ascending ? query.order(Track.Columns.trackNumber) : query.order(Track.Columns.trackNumber.desc)
        case "discNumber":
            return ascending ? query.order(Track.Columns.discNumber) : query.order(Track.Columns.discNumber.desc)
        case "filename":
            return ascending ? query.order(Track.Columns.filename) : query.order(Track.Columns.filename.desc)
        default:
            return query
        }
    }
}
