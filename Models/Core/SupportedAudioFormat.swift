import Foundation

/// One decodable file type reported by the playback engine: the extension the
/// scanner matches on, plus the engine's human name for it. Engine-agnostic, so
/// the UI layer can show the format list without importing the engine module.
struct SupportedAudioFormat: Hashable, Identifiable {
    /// Lowercased, without a leading dot.
    let fileExtension: String

    /// The engine's name for the format, before any display override.
    let name: String

    var id: String { fileExtension }
}

/// A row in the supported-formats list: one format name and every extension
/// that resolves to it.
struct SupportedAudioFormatGroup: Identifiable {
    let name: String
    let fileExtensions: [String]

    var id: String { name }
}

extension Array where Element == SupportedAudioFormat {
    /// Collapses the engine's per-extension list into display rows, applying the
    /// name overrides so extensions a listener thinks of as one format share a row.
    func groupedForDisplay() -> [SupportedAudioFormatGroup] {
        var extensionsByName: [String: [String]] = [:]

        for format in self {
            let name = SupportedAudioFormatNames.displayName(for: format.name)
            extensionsByName[name, default: []].append(format.fileExtension)
        }

        return extensionsByName
            .map { SupportedAudioFormatGroup(name: $0.key, fileExtensions: $0.value.sorted()) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private enum SupportedAudioFormatNames {
    // Overrides for the engine names that read poorly in a user-facing list:
    // AudioToolbox's cryptic type names, and the cases where several engine
    // names describe one format a listener recognizes as a single thing.
    //
    // Anything absent passes through unchanged, so a format a future engine
    // build adds still appears - under its own name - instead of silently
    // vanishing from the list.
    private static let overrides: [String: String] = [
        // AudioToolbox reports the AAC transport syntaxes separately; xHE-AAC
        // arrives under LATM/LOAS too.
        "AAC ADTS": "AAC",
        "LATM/LOAS": "AAC",
        "Apple MPEG-4 Audio": "MPEG-4 Audio",
        // Only Layer 3 is worth naming on its own; the rest are plain MPEG
        // audio to anyone reading this list (and AudioToolbox files .m2a
        // under Layer 1 regardless).
        "MPEG Layer 1": "MPEG Audio",
        "MPEG Layer 2": "MPEG Audio",
        "MPEG Layer 3": "MP3",
        "WAVE": "WAV",
        "CAF": "Core Audio Format",
        "NeXT/Sun": "AU (NeXT/Sun)",
        // The three Ogg extensions are one format to a user, however the
        // engine names each container flavour.
        "Ogg Audio": "Ogg Vorbis",
        "Ogg": "Ogg Vorbis",
        "DSDIFF (DSD)": "DSD",
        "DSF (DSD)": "DSD",
        "DTS Coherent Acoustics": "DTS"
    ]

    static func displayName(for engineName: String) -> String {
        overrides[engineName] ?? engineName
    }
}
