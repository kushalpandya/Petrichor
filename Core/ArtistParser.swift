import Foundation

struct ArtistParser {
    // Common separators used in artist fields
    private static let separators = [
        " feat. ", " feat ", " featuring ", " ft. ", " ft ",
        " & ", " and ", " x ", " X ", " vs. ", " vs ",
        ", ", " with ", " / ", "／", "/", "、", ";"
    ]

    // MARK: - Caching
    private static let cacheQueue = DispatchQueue(label: "com.petrichor.artistparser.cache", attributes: .concurrent)
    private static var parseCache = [String: [String]]()
    private static var normalizeCache = [String: String]()

    // Pre-compiled regex for better performance
    private static let initialsRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(\b[a-z]\.?\s*)+"#, options: [])
    }()

    private static let extraSpacesRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\s+"#, options: [])
    }()

    // MARK: - Cache Management

    static func clearCache() {
        cacheQueue.async(flags: .barrier) {
            parseCache.removeAll()
            normalizeCache.removeAll()
        }
    }

    // MARK: - Normalization

    static func normalizeArtistName(_ name: String) -> String {
        // Check cache first
        if let cached = cacheQueue.sync(execute: { normalizeCache[name] }) {
            return cached
        }

        var normalized = name.lowercased()

        // Handle initials with pre-compiled regex
        if let regex = initialsRegex {
            let range = NSRange(normalized.startIndex..., in: normalized)
            let matches = regex.matches(in: normalized, options: [], range: range)

            // Process matches in reverse order to not mess up ranges
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: normalized) {
                    let matchedString = String(normalized[matchRange])
                    // Remove dots and spaces from the matched initials
                    let cleaned = matchedString
                        .replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: " ", with: "")
                    normalized.replaceSubrange(matchRange, with: cleaned)
                }
            }
        }

        // Normalize hyphen variations (with or without spaces)
        // Using a single pass with replacingOccurrences
        normalized = normalized
            .replacingOccurrences(of: " - ", with: "-")
            .replacingOccurrences(of: " -", with: "-")
            .replacingOccurrences(of: "- ", with: "-")

        // Remove extra spaces using pre-compiled regex
        if let regex = extraSpacesRegex {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: " ")
        }

        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cache the result
        cacheQueue.async(flags: .barrier) {
            normalizeCache[name] = normalized
        }

        return normalized
    }

    /// Parses a multi-artist string into individual artist names
    static func parse(_ artistString: String, unknownPlaceholder: String = "Unknown Artist") -> [String] {
        // Create cache key that includes the placeholder
        let cacheKey = "\(artistString)|\(unknownPlaceholder)"

        // Check cache first
        if let cached = cacheQueue.sync(execute: { parseCache[cacheKey] }) {
            return cached
        }

        // Fast path for empty strings
        if artistString.isEmpty {
            let result = [unknownPlaceholder]
            cacheQueue.async(flags: .barrier) {
                parseCache[cacheKey] = result
            }
            return result
        }

        // Fast path for strings without separators
        let lowercasedArtist = artistString.lowercased()
        let hasSeparator = separators.contains { separator in
            lowercasedArtist.contains(separator.lowercased())
        }

        if !hasSeparator {
            let trimmed = artistString.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = trimmed.isEmpty ? [unknownPlaceholder] : [trimmed]
            cacheQueue.async(flags: .barrier) {
                parseCache[cacheKey] = result
            }
            return result
        }

        // Full parsing logic
        var artists: [String] = [artistString]

        // Process each separator
        for separator in separators {
            var newArtists: [String] = []

            for artist in artists {
                if artist.localizedCaseInsensitiveContains(separator) {
                    // Split by this separator (case-insensitive)
                    let components = artist.components(separatedBy: separator, options: .caseInsensitive)
                    newArtists.append(contentsOf: components)
                } else {
                    newArtists.append(artist)
                }
            }

            artists = newArtists
        }

        // Clean up
        let cleanedArtists = artists
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != unknownPlaceholder }

        // Remove duplicates while preserving the best version of each name
        var normalizedToOriginal: [String: String] = [:]

        for artist in cleanedArtists {
            let normalized = normalizeArtistName(artist)

            // If we haven't seen this normalized form, or the current version is "better"
            if let existing = normalizedToOriginal[normalized] {
                // Prefer the version with more formatting (dots, spaces) as it's likely more "correct"
                if artist.count > existing.count {
                    normalizedToOriginal[normalized] = artist
                }
            } else {
                normalizedToOriginal[normalized] = artist
            }
        }

        // Return unique artists using the best version of each name
        let uniqueArtists = Array(normalizedToOriginal.values)

        let result = uniqueArtists.isEmpty ? [unknownPlaceholder] : uniqueArtists

        // Cache the result
        cacheQueue.async(flags: .barrier) {
            parseCache[cacheKey] = result
        }

        return result
    }

    /// Checks if a specific artist appears in a track's artist field
    static func trackContainsArtist(_ track: Track, artistName: String) -> Bool {
        // Fast path for exact match
        if track.artist == artistName {
            return true
        }

        let artists = parse(track.artist)

        // Fast path for single artist
        if artists.count == 1 && artists[0] == artistName {
            return true
        }

        // Normalized comparison
        let normalizedSearchName = normalizeArtistName(artistName)

        return artists.contains { artist in
            artist == artistName || normalizeArtistName(artist) == normalizedSearchName
        }
    }
}

// Extension to String for case-insensitive split
extension String {
    func components(separatedBy separator: String, options: String.CompareOptions) -> [String] {
        var result: [String] = []
        result.reserveCapacity(2) // Most splits result in 2 components

        var currentIndex = self.startIndex

        while currentIndex < self.endIndex {
            if let range = self.range(of: separator, options: options, range: currentIndex..<self.endIndex) {
                result.append(String(self[currentIndex..<range.lowerBound]))
                currentIndex = range.upperBound
            } else {
                result.append(String(self[currentIndex..<self.endIndex]))
                break
            }
        }

        return result
    }
}
