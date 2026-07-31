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
    // Display names keyed by the lowercased stored codec. Only codecs whose
    // uppercased form is wrong need an entry; acronyms (DTS, MLP, TAK) fall
    // through. Second group is the previous engine's free-form names, kept
    // until those rows are rescanned.
    static let codecDisplayNames: [String: String] = [
        "flac": "FLAC",
        "alac": "ALAC",
        "aac": "AAC",
        "mp3": "MP3",
        "opus": "Opus",
        "vorbis": "Vorbis",
        "wav": "WAV",
        "aiff": "AIFF",
        "ape": "APE",
        "wavpack": "WavPack",
        "tta": "TTA",
        "musepack": "Musepack",
        "dsf": "DSD",
        "dsdiff": "DSD",
        "wma": "WMA",
        "speex": "Speex",
        "pcm": "PCM",
        "ac3": "AC-3",
        "eac3": "E-AC-3",
        "truehd": "TrueHD",
        "shorten": "Shorten",

        "ogg": "Ogg",
        "aifc": "AIFF",
        "dsd": "DSD"
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
    /// Assumes the stored value is kbps - the reader converts at scan time, since
    /// the engine reports bits/sec.
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
    /// Whether the track is losslessly encoded. The stored flag is authoritative;
    /// rows without one reuse the scanner's tables so both paths agree, and anything
    /// still undecidable reads as lossy - the safe default for a badge.
    var isLossless: Bool {
        MetadataMapping.isTrackLossless(codec: codec, fileExtension: format, fallback: lossless) ?? false
    }
}
