//
// MetadataMapping
//
// Small engine-agnostic helpers shared by the metadata readers (SFB and
// Crescendo) so year parsing, rating normalization, and artwork compression
// behave identically no matter which backend produced the raw values.
//

import AVFoundation
import Foundation

enum MetadataMapping {
    /// Extracts a 4-digit year (1900-2099) from a date string, or nil if none is
    /// present. Returning nil (rather than "") lets callers assign the result
    /// straight to the optional `year` without an empty-string guard at each site.
    static func year(fromDateString dateString: String) -> String? {
        let yearPattern = #"\b(19|20)\d{2}\b"#

        if let regex = try? NSRegularExpression(pattern: yearPattern),
           let match = regex.firstMatch(
            in: dateString,
            range: NSRange(dateString.startIndex..., in: dateString)
           ) {
            if let range = Range(match.range, in: dateString) { return String(dateString[range]) }
        }

        return nil
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

    /// TagLib-backed readers can report unreliable MPEG durations for files with
    /// missing VBR headers. Only pay the AVFoundation cost when the value is
    /// obviously suspicious.
    static func validatedDuration(_ duration: Double, codec: String?, url: URL, sourceName: String) async -> Double {
        guard isMPEG(codec: codec) else { return duration }
        let suspicious = duration <= 0 || duration.isNaN || duration.isInfinite || duration < 1.0
        guard suspicious else { return duration }

        let asset = AVURLAsset(url: url)
        let avDuration: Double
        do {
            avDuration = try await asset.load(.duration).seconds
        } catch {
            avDuration = 0
        }

        if avDuration.isFinite, avDuration > 0, abs(avDuration - duration) > 1.0 {
            Logger.warning(
                """
                MPEG duration mismatch for \(url.lastPathComponent) - \
                \(sourceName): \(duration)s, AVAsset: \(avDuration)s. Using AVAsset value.
                """
            )
            return avDuration
        }

        return duration
    }

    static func isTrackLossless(codec: String?, url: URL, fallback: Bool? = nil) -> Bool? {
        if let fallback { return fallback }

        if let codec {
            let normalized = codec.lowercased()
            let losslessCodecs = [
                "flac", "alac", "apple lossless", "aiff", "wav", "wave", "pcm",
                "ape", "wavpack", "tta", "dsf", "dsdiff"
            ]
            if losslessCodecs.contains(where: { normalized.contains($0) }) {
                return true
            }

            let lossyCodecs = ["mp3", "mpeg", "aac", "vorbis", "ogg", "opus", "musepack", "mpc", "wma"]
            if lossyCodecs.contains(where: { normalized.contains($0) }) {
                return false
            }
        }

        switch url.pathExtension.lowercased() {
        case "flac", "ape", "wv", "tta", "wav", "wave", "aiff", "aif", "aifc", "alac", "dsf", "dff":
            return true
        case "mp3", "aac", "m4a", "ogg", "oga", "opus", "mpc", "wma":
            return false
        default:
            return nil
        }
    }

    private static func isMPEG(codec: String?) -> Bool {
        guard let codec else { return false }
        let normalized = codec.lowercased()
        return normalized == "mp3" || normalized.contains("mpeg")
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
