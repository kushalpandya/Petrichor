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

    // Bare "/" is only safe with a name lookup to fall back on (protects "AC/DC" etc.)
    private static let unsafeSeparators: Set<String> = ["/"]

    // Ambiguous separators minus the unsafe ones
    private static let safeAmbiguousSeparators = ambiguousSeparators.filter { !unsafeSeparators.contains($0) }

    // All separators including unsafe ones (used when a name lookup is available)
    private static let allSeparators = highConfidenceSeparators + ambiguousSeparators

    // Safe separators (used when there's nothing to match names against)
    private static let safeSeparators = highConfidenceSeparators + safeAmbiguousSeparators

    /// Name data available to resolve ambiguous separators. Raw values double as cache-key parts.
    private enum LookupSource: String {
        /// Nothing to match against - ambiguous separators are split blindly.
        case none = "plain"
        /// Bundled known-artists file, resident only while scanning.
        case bundled = "known"
        /// Names the scanner already resolved into this library, for one role.
        case library
    }

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

    /// Per-role map of normalized name (including merge aliases) to canonical artist name, standing
    /// in for the bundled file once it's unloaded so runtime parsing matches the scan.
    ///
    /// Keyed by role because the roles disagree: an unparsed album-artist tag can leave a combined
    /// `artists` row no `track_artists` relationship uses, which would be a destination with no
    /// tracks. Only names a role can navigate to belong in its map.
    private static var libraryArtists: [String: [String: String]] = [:]

    /// Bumped on every lookup change; part of the cache key, so results computed against replaced
    /// data become unreachable.
    private static var lookupGeneration = 0

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
            lookupGeneration += 1
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
            lookupGeneration += 1
            return count
        }

        guard unloadedCount > 0 else { return }
        clearParseCache()
        Logger.info("Unloaded \(unloadedCount) known artists from memory")
    }

    /// Replace the library-artist lookup: role (`TrackArtist.Role`) to normalized name to canonical
    /// artist name. Keys must already be in lookup form.
    static func setLibraryArtists(_ namesByRole: [String: [String: String]]) {
        // Swap and bump together, or a parse could pair the new data with the old generation and
        // read a cached result the old data produced.
        let changed = knownArtistsQueue.sync(flags: .barrier) { () -> Bool in
            guard libraryArtists != namesByRole else { return false }
            libraryArtists = namesByRole
            lookupGeneration += 1
            return true
        }

        guard changed else { return }
        clearParseCache()
        let total = namesByRole.values.reduce(0) { $0 + $1.count }
        Logger.info("Artist lookup updated with \(total) library names across \(namesByRole.count) roles")
    }

    /// An immutable view of the lookup data, taken once per parse - a retain, not a copy, since the
    /// collections are copy-on-write. Pins the parse to one `generation`.
    private struct Lookup {
        let source: LookupSource
        let generation: Int
        private let bundled: Set<String>
        private let library: [String: String]

        init(source: LookupSource, generation: Int, bundled: Set<String> = [], library: [String: String] = [:]) {
            self.source = source
            self.generation = generation
            self.bundled = bundled
            self.library = library
        }

        /// The name to use for a candidate if it's a known artist, else nil.
        ///
        /// The library map answers first, and with the canonical name, so a tag carrying a
        /// pre-merge alias resolves to the artist it was merged into even mid-scan, where the
        /// bundled file would recognise the old name and hand back the tag text.
        func resolvedName(for candidate: String) -> String? {
            guard source != .none else { return nil }

            let normalized = normalizeArtistName(candidate)
            guard !normalized.isEmpty else { return nil }

            if let canonical = library[normalized] { return canonical }
            return bundled.contains(normalized) ? candidate.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }
    }

    /// Best available name data for a role. The bundled file adds recognition breadth while loaded;
    /// the role's names ride along to canonicalize. With neither, `.none` rather than empty.
    private static func currentLookup(for role: String?) -> Lookup {
        knownArtistsQueue.sync {
            let names = role.flatMap { libraryArtists[$0] } ?? [:]

            if !knownArtists.isEmpty {
                return Lookup(source: .bundled, generation: lookupGeneration, bundled: knownArtists, library: names)
            }
            if !names.isEmpty {
                return Lookup(source: .library, generation: lookupGeneration, library: names)
            }
            return Lookup(source: .none, generation: lookupGeneration)
        }
    }

    /// Check if a name matches a known artist in the currently available data.
    static func isKnownArtist(_ name: String) -> Bool {
        let normalized = normalizeArtistName(name)
        guard !normalized.isEmpty else { return false }

        return knownArtistsQueue.sync {
            knownArtists.contains(normalized) || libraryArtists.values.contains { $0[normalized] != nil }
        }
    }

    /// Reclaims entries stranded by a generation bump; correctness comes from the generation.
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
    /// When artist name data is available, uses two-phase parsing with greedy matching
    /// to preserve artist names containing separators (e.g., "Mumford & Sons").
    /// Otherwise falls back to splitting on all safe separators.
    ///
    /// - Parameter role: the `TrackArtist.Role` the string was tagged in. No default, so a caller
    ///   can't silently lose the library lookup: outside a scan it's the only lookup there is, and
    ///   during one it's what resolves merged-away names. Pass nil only when there's genuinely no
    ///   role, accepting that ambiguous separators are then split blindly.
    static func parse(
        _ artistString: String,
        unknownPlaceholder: String = "Unknown Artist",
        role: String?
    ) -> [String] {
        let lookup = currentLookup(for: role)
        let cacheKey = "\(artistString)|\(unknownPlaceholder)|\(lookup.source.rawValue)|\(role ?? "")|\(lookup.generation)"

        if let cached = cacheQueue.sync(execute: { parseCache[cacheKey] }) {
            return cached
        }

        if artistString.isEmpty {
            return cacheAndReturn([unknownPlaceholder], forKey: cacheKey)
        }

        let activeSeparators = lookup.source == .none ? safeSeparators : allSeparators

        // Fast path: no separators at all. Still resolved, so a merged-away tag ("P!nk") points at
        // the artist that now holds its tracks ("Pink").
        if !containsAnySeparator(artistString, in: activeSeparators) {
            let trimmed = artistString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return cacheAndReturn([unknownPlaceholder], forKey: cacheKey) }
            return cacheAndReturn([lookup.resolvedName(for: trimmed) ?? trimmed], forKey: cacheKey)
        }

        let result: [String]
        if lookup.source == .none {
            result = splitBySeparators([artistString], separators: activeSeparators)
        } else {
            result = parseWithKnownArtists(artistString, lookup: lookup)
        }

        return cacheAndReturn(
            deduplicateArtists(result, unknownPlaceholder: unknownPlaceholder),
            forKey: cacheKey
        )
    }

    // MARK: - Known-Artist-Aware Parsing

    /// Two-phase parsing: split on high-confidence separators first,
    /// then resolve ambiguous separators using greedy known-artist matching.
    private static func parseWithKnownArtists(_ artistString: String, lookup: Lookup) -> [String] {
        // Fast path: entire string is a known artist
        if let resolved = lookup.resolvedName(for: artistString) {
            return [resolved]
        }

        // Phase 1: Split on high-confidence separators
        let segments = splitBySeparators([artistString], separators: highConfidenceSeparators)

        // Phase 2: Resolve ambiguous separators using known-artist lookup
        var resolvedArtists: [String] = []
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            resolvedArtists.append(contentsOf: resolveAmbiguousSeparators(trimmed, lookup: lookup))
        }

        return resolvedArtists
    }

    // MARK: - Ambiguous Separator Resolution

    /// Resolves ambiguous separators in a segment using greedy known-artist matching.
    /// Tokenizes the segment at all ambiguous separator positions simultaneously,
    /// then tries joining atoms left-to-right (longest first) to find known artists.
    private static func resolveAmbiguousSeparators(_ segment: String, lookup: Lookup) -> [String] {
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
                if let resolved = lookup.resolvedName(for: candidate) {
                    result.append(resolved)
                    i = j + 1
                    matched = true
                    break
                }
            }

            if !matched {
                let atom = atoms[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !atom.isEmpty {
                    result.append(lookup.resolvedName(for: atom) ?? atom)
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
