import Foundation

enum ArtistParser {
    // High-confidence separators - always split, never part of an artist name
    private static let highConfidenceSeparators = [
        " feat. ", " feat ", " featuring ", " ft. ", " ft ",
        ";", "、"
    ]

    // Ambiguous separators - may be part of an artist name (e.g., "Mumford & Sons")
    // Resolved via known-artist lookup when data is available.
    // Note: " / " must come before "/" so the longer match is preferred in tokenization.
    private static let ambiguousSeparators = [
        " & ", " and ", " x ", " X ", " vs. ", " vs ",
        ", ", " with ", " / ", "/", "／"
    ]

    // Bare "/" is only safe with known-artist lookup (protects "AC/DC" etc.)
    private static let unsafeSeparators: Set<String> = ["/"]

    // All separators including unsafe ones (used when known artists are loaded)
    private static let allSeparators = highConfidenceSeparators + ambiguousSeparators

    // Safe separators (used when no known artists data is available)
    private static let safeSeparators = highConfidenceSeparators + ambiguousSeparators.filter { !unsafeSeparators.contains($0) }

    // MARK: - Caching
    private static let cacheQueue = DispatchQueue(label: "org.Petrichor.artistparser.cache", attributes: .concurrent)
    private static var parseCache = [String: [String]]()
    private static var normalizeCache = [String: String]()

    // Pre-compiled regex for better performance
    private static let initialsRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(\b[a-z]\.?\s*)+"#, options: [])
    }()

    private static let extraSpacesRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\s+"#, options: [])
    }()

    // MARK: - Known Artists

    // Concurrent so that reads (`hasKnownArtists`, `isKnownArtist`) run in parallel during
    // a scan; load/unload mutate state behind a `.barrier` for exclusive access.
    private static let knownArtistsQueue = DispatchQueue(label: "org.Petrichor.artistparser.knownArtists", attributes: .concurrent)

    /// In-memory set of known artist names, loaded on-demand from bundled text file.
    private static var knownArtists = Set<String>()
    private static var knownArtistsRetainCount = 0

    /// Load known artists from the bundled text file into memory.
    ///
    /// Reference-counted: each call must be balanced by exactly one `unloadKnownArtists()`.
    /// Prefer pairing the two with `defer` so a throwing scan can't leak the retain count.
    static func loadKnownArtists() {
        let result = knownArtistsQueue.sync(flags: .barrier) { () -> (loadedCount: Int, fileName: String?, warning: String?) in
            knownArtistsRetainCount += 1

            guard knownArtists.isEmpty else { return (0, nil, nil) }

            guard let url = findKnownArtistsFile() else {
                return (0, nil, "No known artists data file found in bundle")
            }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                return (0, nil, "Failed to read known artists file: \(url.lastPathComponent)")
            }

            knownArtists = Set(
                content.components(separatedBy: .newlines).lazy
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            )
            return (knownArtists.count, url.lastPathComponent, nil)
        }

        if result.loadedCount > 0 {
            clearParseCache()
            Logger.info("Loaded \(result.loadedCount) known artists from \(result.fileName ?? "bundle")")
        } else if let warning = result.warning {
            Logger.warning(warning)
        }
    }

    /// Release known artists from memory after scanning completes.
    static func unloadKnownArtists() {
        let unloadedCount = knownArtistsQueue.sync(flags: .barrier) { () -> Int in
            knownArtistsRetainCount = max(knownArtistsRetainCount - 1, 0)
            guard knownArtistsRetainCount == 0, !knownArtists.isEmpty else { return 0 }

            let count = knownArtists.count
            knownArtists.removeAll()
            return count
        }

        guard unloadedCount > 0 else { return }
        clearParseCache()
        Logger.info("Unloaded \(unloadedCount) known artists from memory")
    }

    /// Whether known artists data is available for enhanced parsing.
    private static var hasKnownArtists: Bool {
        knownArtistsQueue.sync { !knownArtists.isEmpty }
    }

    /// Check if a name matches a known artist.
    static func isKnownArtist(_ name: String) -> Bool {
        let normalized = normalizeArtistName(name)
        guard !normalized.isEmpty else { return false }
        return knownArtistsQueue.sync { knownArtists.contains(normalized) }
    }

    private static func clearParseCache() {
        cacheQueue.sync(flags: .barrier) {
            parseCache.removeAll()
        }
    }

    /// Find the known artists data file in the bundle (known_artists_YYYYMMDD.txt).
    private static func findKnownArtistsFile() -> URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: resourcePath), includingPropertiesForKeys: nil
        ) else { return nil }

        return contents
            .filter {
                $0.lastPathComponent.hasPrefix("known_artists_") &&
                $0.lastPathComponent.hasSuffix(".txt") &&
                $0.lastPathComponent != About.knownArtistsSampleFile
            }
            .max { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Normalization

    static func normalizeArtistName(_ name: String) -> String {
        if let cached = cacheQueue.sync(execute: { normalizeCache[name] }) {
            return cached
        }

        var normalized = name.lowercased()

        // Handle initials with pre-compiled regex
        if let regex = initialsRegex {
            let range = NSRange(normalized.startIndex..., in: normalized)
            let matches = regex.matches(in: normalized, options: [], range: range)

            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: normalized) {
                    let matchedString = String(normalized[matchRange])
                    let cleaned = matchedString
                        .replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: " ", with: "")
                    normalized.replaceSubrange(matchRange, with: cleaned)
                }
            }
        }

        // Normalize hyphen variations
        normalized = normalized
            .replacingOccurrences(of: " - ", with: "-")
            .replacingOccurrences(of: " -", with: "-")
            .replacingOccurrences(of: "- ", with: "-")

        // Collapse extra spaces
        if let regex = extraSpacesRegex {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: " ")
        }

        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        cacheQueue.async(flags: .barrier) { normalizeCache[name] = normalized }
        return normalized
    }

    // MARK: - Parsing

    /// Parses a multi-artist string into individual artist names.
    /// When known artists data is loaded, uses two-phase parsing with greedy matching
    /// to preserve artist names containing separators (e.g., "Mumford & Sons").
    /// Otherwise falls back to splitting on all safe separators.
    static func parse(_ artistString: String, unknownPlaceholder: String = "Unknown Artist") -> [String] {
        let usingKnownArtists = hasKnownArtists
        let cacheKey = "\(artistString)|\(unknownPlaceholder)|\(usingKnownArtists ? "known" : "plain")"

        if let cached = cacheQueue.sync(execute: { parseCache[cacheKey] }) {
            return cached
        }

        if artistString.isEmpty {
            return cacheAndReturn([unknownPlaceholder], forKey: cacheKey)
        }

        let activeSeparators = usingKnownArtists ? allSeparators : safeSeparators

        // Fast path: no separators at all
        if !containsAnySeparator(artistString, in: activeSeparators) {
            let trimmed = artistString.trimmingCharacters(in: .whitespacesAndNewlines)
            return cacheAndReturn(trimmed.isEmpty ? [unknownPlaceholder] : [trimmed], forKey: cacheKey)
        }

        let result: [String]
        if usingKnownArtists {
            result = parseWithKnownArtists(artistString)
        } else {
            result = splitBySeparators([artistString], separators: activeSeparators)
        }

        return cacheAndReturn(
            deduplicateArtists(result, unknownPlaceholder: unknownPlaceholder),
            forKey: cacheKey
        )
    }

    // MARK: - Known-Artist-Aware Parsing

    /// Two-phase parsing: split on high-confidence separators first,
    /// then resolve ambiguous separators using greedy known-artist matching.
    private static func parseWithKnownArtists(_ artistString: String) -> [String] {
        // Fast path: entire string is a known artist
        if isKnownArtist(artistString) {
            return [artistString.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        // Phase 1: Split on high-confidence separators
        let segments = splitBySeparators([artistString], separators: highConfidenceSeparators)

        // Phase 2: Resolve ambiguous separators using known-artist lookup
        var resolvedArtists: [String] = []
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            resolvedArtists.append(contentsOf: resolveAmbiguousSeparators(trimmed))
        }

        return resolvedArtists
    }

    // MARK: - Ambiguous Separator Resolution

    /// Resolves ambiguous separators in a segment using greedy known-artist matching.
    /// Tokenizes the segment at all ambiguous separator positions simultaneously,
    /// then tries joining atoms left-to-right (longest first) to find known artists.
    private static func resolveAmbiguousSeparators(_ segment: String) -> [String] {
        let (atoms, separators) = tokenizeAmbiguousSeparators(segment)

        if atoms.count <= 1 {
            return [segment]
        }

        // Greedy left-to-right, longest-first matching
        var result: [String] = []
        var i = 0

        while i < atoms.count {
            var matched = false

            for j in stride(from: atoms.count - 1, through: i + 1, by: -1) {
                let candidate = reconstructSegment(atoms: atoms, separators: separators, from: i, to: j)
                if isKnownArtist(candidate) {
                    result.append(candidate.trimmingCharacters(in: .whitespacesAndNewlines))
                    i = j + 1
                    matched = true
                    break
                }
            }

            if !matched {
                let atom = atoms[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !atom.isEmpty {
                    result.append(atom)
                }
                i += 1
            }
        }

        return result
    }

    /// Tokenizes a string at all ambiguous separator positions.
    /// Returns (atoms, separators) where separators[i] is between atoms[i] and atoms[i+1].
    private static func tokenizeAmbiguousSeparators(_ segment: String) -> (atoms: [String], separators: [String]) {
        struct SeparatorMatch {
            let range: Range<String.Index>
            let separator: String
        }

        var matches: [SeparatorMatch] = []
        for separator in ambiguousSeparators {
            var searchStart = segment.startIndex
            while searchStart < segment.endIndex,
                  let range = segment.range(of: separator, options: .caseInsensitive, range: searchStart..<segment.endIndex) {
                matches.append(SeparatorMatch(range: range, separator: String(segment[range])))
                searchStart = range.upperBound
            }
        }

        if matches.isEmpty {
            return ([segment], [])
        }

        // Sort by position, resolve overlaps (keep earliest)
        matches.sort { $0.range.lowerBound < $1.range.lowerBound }

        var filtered: [SeparatorMatch] = []
        for match in matches {
            if let last = filtered.last, match.range.lowerBound < last.range.upperBound {
                continue
            }
            filtered.append(match)
        }

        // Split into atoms and separators
        var atoms: [String] = []
        var separatorStrings: [String] = []
        var currentStart = segment.startIndex

        for match in filtered {
            atoms.append(String(segment[currentStart..<match.range.lowerBound]))
            separatorStrings.append(match.separator)
            currentStart = match.range.upperBound
        }
        atoms.append(String(segment[currentStart..<segment.endIndex]))

        return (atoms, separatorStrings)
    }

    /// Reconstructs a segment from atoms[from...to] with the original separators between them.
    private static func reconstructSegment(atoms: [String], separators: [String], from: Int, to: Int) -> String {
        var result = atoms[from]
        for k in from..<to {
            result += separators[k] + atoms[k + 1]
        }
        return result
    }

    // MARK: - Shared Helpers

    /// Checks if the string contains any separator from the given list
    private static func containsAnySeparator(_ string: String, in separators: [String]) -> Bool {
        let lowercased = string.lowercased()
        return separators.contains { lowercased.contains($0.lowercased()) }
    }

    /// Iteratively splits input strings by each separator in order
    private static func splitBySeparators(_ input: [String], separators: [String]) -> [String] {
        var result = input
        for separator in separators {
            var newResult: [String] = []
            for segment in result {
                if segment.localizedCaseInsensitiveContains(separator) {
                    newResult.append(contentsOf: segment.components(separatedBy: separator, options: .caseInsensitive))
                } else {
                    newResult.append(segment)
                }
            }
            result = newResult
        }
        return result
    }

    /// Caches a parse result and returns it
    private static func cacheAndReturn(_ result: [String], forKey key: String) -> [String] {
        cacheQueue.async(flags: .barrier) { parseCache[key] = result }
        return result
    }

    // MARK: - Deduplication

    /// Deduplicates and cleans artist names, preferring longer formatting.
    private static func deduplicateArtists(_ artists: [String], unknownPlaceholder: String) -> [String] {
        let cleanedArtists = artists
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != unknownPlaceholder }

        var normalizedToOriginal: [String: String] = [:]
        for artist in cleanedArtists {
            let normalized = normalizeArtistName(artist)
            if let existing = normalizedToOriginal[normalized] {
                if artist.count > existing.count {
                    normalizedToOriginal[normalized] = artist
                }
            } else {
                normalizedToOriginal[normalized] = artist
            }
        }

        let uniqueArtists = Array(normalizedToOriginal.values)
        return uniqueArtists.isEmpty ? [unknownPlaceholder] : uniqueArtists
    }
}

// Extension to String for case-insensitive split
extension String {
    func components(separatedBy separator: String, options: String.CompareOptions) -> [String] {
        var result: [String] = []
        result.reserveCapacity(2)

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
