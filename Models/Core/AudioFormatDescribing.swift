import Foundation

/// Audio-format metadata shared by the lightweight `Track` and the full
/// `FullTrack` records. The display helpers below are the single source of
/// truth for how codec / bitrate / sample-rate / channels / lossless are
/// rendered, used by both the player badges and the track-detail view.
protocol AudioFormatDescribing {
    var format: String { get }
    var codec: String? { get }
    var bitrate: Int? { get }
    var sampleRate: Int? { get }
    var channels: Int? { get }
    var lossless: Bool? { get }
}

private enum AudioFormatTables {
    // Canonical, properly-cased codec display names. Engines report codec casing
    // differently (SFB upper-cases, Crescendo uses TagLib's lowercase short name),
    // so we normalize for display. A blanket uppercase won't do - Opus/Vorbis/
    // WavPack/Musepack aren't acronyms; unknown codecs fall back to uppercase
    // since they're almost always acronyms.
    static let codecDisplayNames: [String: String] = [
        "flac": "FLAC",
        "alac": "ALAC",
        "aac": "AAC",
        "mp3": "MP3",
        "opus": "Opus",
        "vorbis": "Vorbis",
        "ogg": "Ogg",
        "wav": "WAV",
        "aiff": "AIFF",
        "aifc": "AIFF",
        "wavpack": "WavPack",
        "ape": "APE",
        "musepack": "Musepack",
        "tta": "TTA",
        "dsd": "DSD",
        "speex": "Speex",
        "pcm": "PCM"
    ]
}

// MARK: - Display Formatting

extension AudioFormatDescribing {
    /// The codec name normalized for display, or nil when no codec is recorded.
    var codecDisplay: String? {
        guard let codec = codec, !codec.isEmpty else { return nil }
        return AudioFormatTables.codecDisplayNames[codec.lowercased()] ?? codec.uppercased()
    }

    /// The bitrate formatted for display (e.g. "320 kbps"), or nil when absent.
    /// Assumes the stored value is kbps - the metadata readers normalize to kbps
    /// at scan time (SFB/TagLib already reports kbps; Crescendo reports bps).
    var bitrateDisplay: String? {
        guard let bitrate = bitrate, bitrate > 0 else { return nil }
        return "\(bitrate) kbps"
    }

    /// The sample rate formatted for display (e.g. "44.1 kHz"), or nil when absent.
    var sampleRateDisplay: String? {
        guard let sampleRate = sampleRate, sampleRate > 0 else { return nil }
        if sampleRate >= 1000 {
            let khz = Double(sampleRate) / 1000.0
            return String(format: "%.1f kHz", khz)
        }
        return "\(sampleRate) Hz"
    }

    /// The channel layout formatted for display (e.g. "Stereo"), or nil when absent.
    var channelsDisplay: String? {
        guard let channels = channels, channels > 0 else { return nil }
        switch channels {
        case 1: return String(localized: "Mono")
        case 2: return String(localized: "Stereo")
        case 4: return String(localized: "Quadraphonic")
        case 6: return String(localized: "5.1 Surround")
        case 8: return String(localized: "7.1 Surround")
        default: return String(localized: "\(channels) channels")
        }
    }
}

// MARK: - Quality

extension AudioFormatDescribing {
    /// Determines if the track is in a lossless format.
    var isLossless: Bool {
        // Check if we already have flag set in db during metadata extraction
        if let lossless = lossless {
            return lossless
        }

        // Fallback to manual computation
        let formatLower = format.lowercased()
        let codecLower = codec?.lowercased() ?? ""

        let losslessCodecs: Set<String> = [
            "flac", "apple lossless", "alac", "wavpack", "ape", "tta",
            "dsd", "dsf", "dff"
        ]

        for losslessCodec in losslessCodecs where codecLower.contains(losslessCodec) {
            return true
        }

        let losslessFormats: Set<String> = [
            // Lossless PCM
            "flac", "alac", "wav", "wave", "aiff", "aif", "aifc",
            // Lossless compressed
            "ape", "wv", "tta",
            // DSD formats
            "dsf", "dff",
            // Legacy lossless
            "au",
            // Module/tracker formats
            "mod", "it", "s3m", "xm"
        ]

        return losslessFormats.contains(formatLower)
    }
}
