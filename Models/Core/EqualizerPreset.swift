import Foundation

// MARK: - Equalizer Preset

/// Available equalizer presets matching Apple Music presets
public enum EqualizerPreset: String, CaseIterable {
    case flat = "flat"
    case acoustic = "acoustic"
    case classical = "classical"
    case dance = "dance"
    case deep = "deep"
    case electronic = "electronic"
    case hipHop = "hiphop"
    case increaseBass = "increasebass"
    case increaseTreble = "increasetreble"
    case increaseVocals = "increasevocals"
    case jazz = "jazz"
    case latin = "latin"
    case loudness = "loudness"
    case lounge = "lounge"
    case piano = "piano"
    case pop = "pop"
    case rnb = "rnb"
    case reduceBass = "reducebass"
    case reduceTreble = "reducetreble"
    case rock = "rock"
    case smallSpeakers = "smallspeakers"
    case spokenWord = "spokenword"
    case wow = "wow"

    /// Configuration for each preset (gains, display name, description)
    private var config:
        (gains: [Float], displayName: String, description: String) {
        switch self {
        case .flat:
            return (
                [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                "Flat",
                "No adjustments"
            )
        case .acoustic:
            return (
                [5, 4, 3, 1, 2, 2, 3, 3, 3, 2],
                "Acoustic",
                "Enhanced clarity and warmth for acoustic music"
            )
        case .rock:
            return (
                [4, 3, -1, -1, 1, 2, 3, 3, 3, 3],
                "Rock",
                "Enhanced bass and treble with boosted mids"
            )
        case .pop:
            return (
                [-1, -1, 0, 2, 4, 4, 2, 0, -1, -1],
                "Pop",
                "Boosted mids with controlled bass and treble"
            )
        case .jazz:
            return (
                [3, 2, 1, 2, -1, -1, 0, 1, 2, 3],
                "Jazz",
                "Enhanced warmth with clear highs"
            )
        case .classical:
            return (
                [4, 3, 2, 0, 0, 0, -1, -2, -2, -3],
                "Classical",
                "Natural sound with enhanced clarity"
            )
        case .electronic:
            return (
                [6, 5, 3, 0, -2, 0, 2, 3, 4, 5],
                "Electronic",
                "Strong bass with crystal clear highs"
            )
        case .dance:
            return (
                [5, 6, 4, 0, 2, 3, 4, 3, 2, 1],
                "Dance",
                "Strong bass with punchy mids"
            )
        case .hipHop:
            return (
                [7, 6, 3, 2, -1, -1, 1, 2, 3, 4],
                "Hip-Hop",
                "Heavy bass with vocal clarity"
            )
        case .rnb:
            return (
                [6, 5, 2, -1, -2, 1, 2, 2, 3, 4],
                "R&B",
                "Smooth bass with vocal presence"
            )
        case .latin:
            return (
                [4, 3, 0, 0, -1, -1, 2, 3, 4, 5],
                "Latin",
                "Bright and energetic sound"
            )
        case .increaseBass:
            return (
                [8, 7, 6, 4, 2, 0, 0, 0, 0, 0],
                "Bass Booster",
                "Maximum bass boost"
            )
        case .reduceBass:
            return (
                [-6, -5, -4, -2, -1, 0, 0, 0, 0, 0],
                "Bass Reducer",
                "Reduced bass frequencies"
            )
        case .increaseTreble:
            return (
                [0, 0, 0, 0, 0, 2, 4, 6, 7, 8],
                "Treble Booster",
                "Maximum treble boost"
            )
        case .reduceTreble:
            return (
                [0, 0, 0, 0, 0, -1, -2, -4, -5, -6],
                "Treble Reducer",
                "Reduced treble frequencies"
            )
        case .increaseVocals:
            return (
                [-2, -1, -1, 1, 3, 4, 4, 3, 1, 0],
                "Vocal Booster",
                "Enhanced vocal presence"
            )
        case .deep:
            return (
                [7, 6, 4, 2, 1, -1, -2, -3, -3, -4],
                "Deep",
                "Maximum bass presence"
            )
        case .lounge:
            return (
                [-3, -2, -1, 1, 3, 2, 0, -1, 2, 1],
                "Lounge",
                "Smooth and relaxed sound"
            )
        case .piano:
            return (
                [-1, 0, 1, 2, 3, 2, 1, 3, 4, 3],
                "Piano",
                "Clarity for piano and strings"
            )
        case .spokenWord:
            return (
                [-3, -2, 0, 1, 3, 4, 4, 3, 2, 0],
                "Spoken Word",
                "Enhanced vocal clarity for podcasts"
            )
        case .smallSpeakers:
            return (
                [5, 4, 3, 2, 1, 0, -1, -2, -2, -3],
                "Small Speakers",
                "Optimized for small speakers"
            )
        case .loudness:
            return (
                [6, 4, 0, 0, 0, 0, -1, 3, 5, 6],
                "Loudness",
                "Enhanced perceived loudness"
            )
        case .wow:
            return (
                [8, 7, 5, 2, 1, 1, 2, 3, 4, 3],
                "Wow",
                "Extreme enhancement for maximum impact"
            )
        }
    }

    /// Gain values for 10 bands: 32Hz, 64Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz
    /// Values are in dB, range typically -12 to +12
    var gains: [Float] {
        config.gains
    }

    /// Human-readable display name for the preset
    var displayName: String {
        config.displayName
    }

    /// Description of what the preset does
    var description: String {
        config.description
    }
}

// MARK: - Equalizer Frequencies

/// Standard 10-band equalizer frequencies
public enum EqualizerFrequency: Float, CaseIterable {
    case hz32 = 32
    case hz64 = 64
    case hz125 = 125
    case hz250 = 250
    case hz500 = 500
    case hz1000 = 1000
    case hz2000 = 2000
    case hz4000 = 4000
    case hz8000 = 8000
    case hz16000 = 16000

    /// Human-readable label for the frequency
    var label: String {
        if rawValue >= 1000 {
            return "\(Int(rawValue / 1000))K"
        } else {
            return "\(Int(rawValue))"
        }
    }

    /// Get all frequencies as an array of Float values
    static var allFrequencies: [Float] {
        allCases.map { $0.rawValue }
    }
}
