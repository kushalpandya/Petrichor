import Foundation

struct LibrarySearch {
    // MARK: - Track Search

    /// Searches tracks based on a query string across multiple metadata fields
    /// - Parameters:
    ///   - tracks: The tracks to search through
    ///   - query: The search query string
    /// - Returns: Filtered tracks that match the query
    static func searchTracks(_ tracks: [Track], with query: String) -> [Track] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return tracks }

        // Try FTS5 search first for performance
        if let coordinator = AppCoordinator.shared {
            let ftsResults = coordinator.libraryManager.databaseManager.searchTracksUsingFTS(trimmedQuery)
            if !ftsResults.isEmpty {
                return ftsResults
            }
        }

        // Fallback to sophisticated in-memory search
        let searchTerms = parseSearchTerms(from: trimmedQuery)

        return tracks.filter { track in
            searchTerms.allSatisfy { term in
                matchesTrack(track, searchTerm: term)
            }
        }
    }

    // MARK: - Private Helper Methods

    /// Parses search query into individual terms, handling quoted phrases
    private static func parseSearchTerms(from query: String) -> [String] {
        var terms: [String] = []
        var currentTerm = ""
        var inQuotes = false

        for char in query {
            if char == "\"" {
                inQuotes.toggle()
                if !inQuotes && !currentTerm.isEmpty {
                    terms.append(currentTerm.trimmingCharacters(in: .whitespaces))
                    currentTerm = ""
                }
            } else if char == " " && !inQuotes {
                if !currentTerm.isEmpty {
                    terms.append(currentTerm.trimmingCharacters(in: .whitespaces))
                    currentTerm = ""
                }
            } else {
                currentTerm.append(char)
            }
        }

        // Add any remaining term
        if !currentTerm.isEmpty {
            terms.append(currentTerm.trimmingCharacters(in: .whitespaces))
        }

        // If no terms were parsed, use the entire query as a single term
        if terms.isEmpty && !query.isEmpty {
            terms.append(query)
        }

        return terms
    }

    /// Checks if a track matches a single search term
    private static func matchesTrack(_ track: Track, searchTerm: String) -> Bool {
        let lowercasedTerm = searchTerm.lowercased()

        // First check the title field (not part of LibraryFilterType)
        if track.title.lowercased().contains(lowercasedTerm) {
            return true
        }

        // Check all fields defined in LibraryFilterType
        for filterType in LibraryFilterType.allCases {
            if matchesFilterType(track, filterType: filterType, searchTerm: lowercasedTerm) {
                return true
            }
        }

        // Check additional fields from extended metadata
        if let extended = track.extendedMetadata {
            if matchesExtendedMetadata(extended, searchTerm: lowercasedTerm) {
                return true
            }
        }

        // Check other track properties not covered by LibraryFilterType
        if matchesAdditionalFields(track, searchTerm: lowercasedTerm) {
            return true
        }

        return false
    }

    /// Checks if a track matches a search term for a specific filter type
    private static func matchesFilterType(_ track: Track, filterType: LibraryFilterType, searchTerm: String) -> Bool {
        // Special handling for decades
        if filterType == .decades {
            // Extract decade from track's year
            if let yearInt = Int(track.year.prefix(4)) {
                let trackDecade = (yearInt / 10) * 10
                let trackDecadeString = "\(trackDecade)s"
                return trackDecadeString.lowercased().contains(searchTerm)
            }
            return false
        }
        
        let fieldValue = filterType.getValue(from: track)

        // For filter types that use multi-artist parsing
        if filterType.usesMultiArtistParsing {
            return matchesMultiArtistField(fieldValue, searchTerm: searchTerm)
        } else {
            // Direct field comparison
            return fieldValue.lowercased().contains(searchTerm)
        }
    }

    /// Special handling for multi-artist fields
    private static func matchesMultiArtistField(_ field: String, searchTerm: String) -> Bool {
        // First check if the entire field contains the term
        if field.lowercased().contains(searchTerm) {
            return true
        }

        // Then parse and check individual artists
        let artists = ArtistParser.parse(field)
        return artists.contains { artist in
            let normalizedArtist = ArtistParser.normalizeArtistName(artist)
            return artist.lowercased().contains(searchTerm) ||
                   normalizedArtist.contains(searchTerm)
        }
    }

    /// Checks extended metadata fields
    private static func matchesExtendedMetadata(_ extended: ExtendedMetadata, searchTerm: String) -> Bool {
        // Check all string fields in extended metadata
        let fieldsToCheck: [String?] = [
            extended.originalArtist,
            extended.producer,
            extended.engineer,
            extended.lyricist,
            extended.conductor,
            extended.remixer,
            extended.label,
            extended.publisher,
            extended.copyright,
            extended.key,
            extended.mood,
            extended.language,
            extended.lyrics,
            extended.comment,
            extended.subtitle,
            extended.grouping,
            extended.movement,
            extended.encodedBy,
            extended.isrc,
            extended.barcode,
            extended.catalogNumber,
            extended.podcastUrl,
            extended.podcastCategory,
            extended.podcastDescription,
            extended.podcastKeywords
        ]

        for field in fieldsToCheck {
            if let fieldValue = field, fieldValue.lowercased().contains(searchTerm) {
                return true
            }
        }

        // Check performer dictionary
        if let performers = extended.performer {
            for (_, performer) in performers {
                if performer.lowercased().contains(searchTerm) {
                    return true
                }
            }
        }

        // Check custom fields
        if let customFields = extended.customFields {
            for (_, value) in customFields {
                if value.lowercased().contains(searchTerm) {
                    return true
                }
            }
        }

        return false
    }

    /// Checks additional track fields not covered by LibraryFilterType
    private static func matchesAdditionalFields(_ track: Track, searchTerm: String) -> Bool {
        // Check format
        if track.format.lowercased().contains(searchTerm) {
            return true
        }

        // Check codec
        if let codec = track.codec, codec.lowercased().contains(searchTerm) {
            return true
        }

        // Check media type
        if let mediaType = track.mediaType, mediaType.lowercased().contains(searchTerm) {
            return true
        }

        // Check release dates
        if let releaseDate = track.releaseDate, releaseDate.lowercased().contains(searchTerm) {
            return true
        }

        if let originalReleaseDate = track.originalReleaseDate, originalReleaseDate.lowercased().contains(searchTerm) {
            return true
        }

        // Check numeric fields as strings
        if let bpm = track.bpm, String(bpm).contains(searchTerm) {
            return true
        }

        if let trackNumber = track.trackNumber, String(trackNumber).contains(searchTerm) {
            return true
        }

        if let discNumber = track.discNumber, String(discNumber).contains(searchTerm) {
            return true
        }

        return false
    }
}

// MARK: - Search Result Ranking

extension LibrarySearch {
    struct SearchResult {
        let track: Track
        let relevanceScore: Int
    }

    /// Searches and ranks tracks by relevance
    static func searchTracksWithRanking(_ tracks: [Track], with query: String) -> [Track] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return tracks }

        // Try FTS5 search first (already returns ranked results)
        if let coordinator = AppCoordinator.shared {
            let ftsResults = coordinator.libraryManager.databaseManager.searchTracksUsingFTS(trimmedQuery)
            if !ftsResults.isEmpty {
                return ftsResults
            }
        }

        // Fallback to in-memory search with ranking
        let searchTerms = parseSearchTerms(from: trimmedQuery)

        let results = tracks.compactMap { track -> SearchResult? in
            let score = calculateRelevanceScore(for: track, searchTerms: searchTerms)
            return score > 0 ? SearchResult(track: track, relevanceScore: score) : nil
        }

        return results
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .map { $0.track }
    }

    /// Calculates relevance score for a track based on search terms
    private static func calculateRelevanceScore(for track: Track, searchTerms: [String]) -> Int {
        var score = 0

        for term in searchTerms {
            let lowercasedTerm = term.lowercased()

            // Title matches score highest
            if track.title.lowercased().contains(lowercasedTerm) {
                score += 10
                if track.title.lowercased() == lowercasedTerm {
                    score += 5  // Exact match bonus
                }
            }

            // Artist matches score high
            if track.artist.lowercased().contains(lowercasedTerm) {
                score += 8
                if track.artist.lowercased() == lowercasedTerm {
                    score += 3
                }
            }

            // Album matches
            if track.album.lowercased().contains(lowercasedTerm) {
                score += 5
            }

            // Other field matches
            if track.genre.lowercased().contains(lowercasedTerm) {
                score += 3
            }

            if track.year.contains(lowercasedTerm) {
                score += 2
            }

            // Extended metadata matches score lower
            if let extended = track.extendedMetadata {
                if matchesExtendedMetadata(extended, searchTerm: lowercasedTerm) {
                    score += 1
                }
            }
        }

        return score
    }
}
