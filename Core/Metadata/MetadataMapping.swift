//
// MetadataMapping
//
// Small engine-agnostic helpers shared by the metadata readers (SFB and
// Crescendo) so year parsing, rating normalization, and artwork compression
// behave identically no matter which backend produced the raw values.
//

import Foundation

enum MetadataMapping {
    /// Extract a 4-digit year from a date string, or "" if none is present.
    static func year(fromDateString dateString: String) -> String {
        let yearPattern = #"\b(19|20)\d{2}\b"#

        if let regex = try? NSRegularExpression(pattern: yearPattern),
           let match = regex.firstMatch(
            in: dateString,
            range: NSRange(dateString.startIndex..., in: dateString)
           ) {
            if let range = Range(match.range, in: dateString) { return String(dateString[range]) }
        }

        return ""
    }

    /// Normalize a raw rating value onto a 0-5 scale. Handles both a plain 1-5
    /// rating and the ID3v2 POPM 1-255 byte range.
    static func normalizedRating(fromRaw rawRating: Int?) -> Int? {
        guard let raw = rawRating, raw > 0 else { return nil }

        let normalized: Int

        // Default rating range (1-5)
        if raw <= 5 {
            normalized = raw
        }
        // ID3v2 POPM rating range (1-255 mapped to 1-5)
        else if raw <= 31 {
            normalized = 1
        } else if raw <= 95 {
            normalized = 2
        } else if raw <= 159 {
            normalized = 3
        } else if raw <= 223 {
            normalized = 4
        } else {
            normalized = 5
        }

        return min(max(normalized, 0), 5)
    }

    /// Size-cap, compress, and cache embedded artwork bytes. Returns the
    /// compressed data, or nil if it is oversized or compression fails.
    static func compressedArtwork(
        from rawData: Data,
        source: String?,
        cache: ArtworkCompressionCache?
    ) async -> Data? {
        if rawData.count > AlbumArtFormat.maxArtworkSize {
            let context = source.map { " for \($0)" } ?? ""
            Logger.warning("Skipping oversized embedded artwork\(context) (\(rawData.count) bytes)")
            return nil
        }

        // Check cache for previously compressed identical artwork
        if let cache = cache, let cached = await cache.get(for: rawData) {
            return cached
        }

        // If compression fails, leave artwork nil rather than persisting undecodable bytes
        // that would re-fail on every later read (sidebar, now-playing, color extraction).
        guard let compressed = ImageUtils.compressImage(from: rawData, source: source) else { return nil }

        if let cache = cache {
            await cache.store(original: rawData, compressed: compressed)
        }
        return compressed
    }
}
