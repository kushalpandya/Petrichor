import AVFoundation
import Foundation
import SFBAudioEngine

// MARK: - Track Metadata

struct TrackMetadata {
    let url: URL
    var title: String?
    var artist: String?
    var album: String?
    var composer: String?
    var genre: String?
    var year: String?
    var duration: Double = 0
    var artworkData: Data?
    var albumArtist: String?
    var trackNumber: Int?
    var totalTracks: Int?
    var discNumber: Int?
    var totalDiscs: Int?
    var rating: Int?
    var compilation: Bool = false
    var releaseDate: String?
    var originalReleaseDate: String?
    var bpm: Int?
    var mediaType: String?
    var bitrate: Int?
    var sampleRate: Int?
    var channels: Int?
    var codec: String?
    var bitDepth: Int?
    var lossless: Bool?

    var sortTitle: String?
    var sortArtist: String?
    var sortAlbum: String?
    var sortAlbumArtist: String?

    var extended: ExtendedMetadata

    init(url: URL) {
        self.url = url
        self.extended = ExtendedMetadata()
    }
}

// MARK: - Metadata Extractor

class MetadataExtractor {

    // MARK: - Public Methods

    /// Extract metadata from an audio file using SFBAudioEngine
    /// - Parameters:
    ///   - url: The URL of the audio file
    ///   - externalArtwork: Optional external artwork to use if file has none
    /// - Returns: TrackMetadata containing all extracted information
    static func extractMetadataSync(from url: URL, externalArtwork: Data? = nil)
        -> TrackMetadata
    {
        var metadata = TrackMetadata(url: url)

        // Try to create AudioFile
        guard
            let audioFile = try? AudioFile(
                readingPropertiesAndMetadataFrom: url
            )
        else {
            Logger.error(
                "Failed to create AudioFile for \(url.lastPathComponent)"
            )
            return metadata
        }

        // Extract audio properties
        extractAudioProperties(from: audioFile.properties, into: &metadata)

        // Extract metadata
        extractMetadata(from: audioFile.metadata, into: &metadata)

        // Extract artwork
        extractArtwork(from: audioFile.metadata, into: &metadata)

        // Use external artwork if no artwork found
        if metadata.artworkData == nil, let externalArtwork = externalArtwork {
            metadata.artworkData = externalArtwork
        }

        return metadata
    }

    // MARK: - Folder-level Artwork Scanning

    /// Scans a folder and returns a map of directory URLs to their artwork data
    static func scanFolderForArtwork(at folderURL: URL) -> [URL: Data] {
        var artworkMap: [URL: Data] = [:]
        let fileManager = FileManager.default

        if let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            var foundArtworkInCurrentDir = false
            var lastDirectory: URL?

            for case let url as URL in enumerator {
                let isDirectory =
                    (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false

                if isDirectory {
                    continue
                }

                // Get the directory containing this file
                let directory = url.deletingLastPathComponent()

                // Reset the flag when we move to a new directory
                if directory != lastDirectory {
                    foundArtworkInCurrentDir = false
                    lastDirectory = directory
                }

                // Skip if we already found artwork in this directory
                if foundArtworkInCurrentDir {
                    continue
                }

                // Check if this is an artwork file
                let filename = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension

                if AlbumArtFormat.knownFilenames.contains(filename)
                    && AlbumArtFormat.isSupported(ext)
                {
                    if let data = try? Data(contentsOf: url) {
                        artworkMap[directory] = data
                        foundArtworkInCurrentDir = true
                    }
                }
            }
        }

        return artworkMap
    }

    // MARK: - Private Extraction Methods

    private static func extractAudioProperties(
        from properties: AudioProperties,
        into metadata: inout TrackMetadata
    ) {
        // Duration (TimeInterval is a typealias for Double)
        if let duration = properties.duration {
            metadata.duration = duration
        }

        // Sample rate
        if let sampleRate = properties.sampleRate {
            metadata.sampleRate = Int(sampleRate)
        }

        // Channels (AVAudioChannelCount, which is UInt32)
        if let channelCount = properties.channelCount {
            metadata.channels = Int(channelCount)
        }

        // Bit depth
        if let bitDepth = properties.bitDepth {
            metadata.bitDepth = bitDepth
        }

        // Bitrate
        if let bitrate = properties.bitrate {
            metadata.bitrate = Int(bitrate)
        }

        // Format/Codec
        if let formatName = properties.formatName {
            metadata.codec = formatName
        }

        // Extract lossless flag from decoder
        metadata.lossless = isTrackLossless(for: metadata.url) ?? false
    }

    /// Safely detect lossless status with multiple fallback strategies
    private static func isTrackLossless(for url: URL) -> Bool? {
        // Try reading file header to determine format reliably
        if let formatBasedResult = detectLosslessFromFileHeader(url: url) {
            return formatBasedResult
        }
        
        return detectLosslessFromExtension(url: url)
    }

    /// Detect lossless format by reading file header magic bytes
    private static func detectLosslessFromFileHeader(url: URL) -> Bool? {
        guard let bytes = FilesystemUtils.readFileHeader(from: url, byteCount: 12) else {
            return nil
        }
        
        // FLAC: "fLaC"
        if bytes.count >= 4 && bytes[0] == 0x66 && bytes[1] == 0x4C &&
           bytes[2] == 0x61 && bytes[3] == 0x43 {
            return true
        }
        
        // AIFF: "FORM" followed by "AIFF" or "AIFC"
        if bytes.count >= 12 && bytes[0] == 0x46 && bytes[1] == 0x4F &&
           bytes[2] == 0x52 && bytes[3] == 0x4D {
            if bytes[8] == 0x41 && bytes[9] == 0x49 && bytes[10] == 0x46 && bytes[11] == 0x46 {
                return true // AIFF
            }
            if bytes[8] == 0x41 && bytes[9] == 0x49 && bytes[10] == 0x46 && bytes[11] == 0x43 {
                return true // AIFC
            }
        }
        
        // WAV/WAVE: "RIFF" followed by "WAVE"
        if bytes.count >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 &&
           bytes[2] == 0x46 && bytes[3] == 0x46 &&
           bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45 {
            return true // Usually lossless PCM
        }
        
        // APE (Monkey's Audio): "MAC "
        if bytes.count >= 4 && bytes[0] == 0x4D && bytes[1] == 0x41 &&
           bytes[2] == 0x43 && bytes[3] == 0x20 {
            return true
        }
        
        // WavPack: "wvpk"
        if bytes.count >= 4 && bytes[0] == 0x77 && bytes[1] == 0x76 &&
           bytes[2] == 0x70 && bytes[3] == 0x6B {
            return true
        }
        
        // TTA (True Audio): "TTA1"
        if bytes.count >= 4 && bytes[0] == 0x54 && bytes[1] == 0x54 &&
           bytes[2] == 0x41 && bytes[3] == 0x31 {
            return true
        }
        
        // MP3 detection - various sync patterns, all lossy
        // ID3v2 tag: "ID3"
        if bytes.count >= 3 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33 {
            return false
        }
        // MP3 frame sync: 0xFF 0xFB, 0xFF 0xFA, 0xFF 0xF3, 0xFF 0xF2
        if bytes.count >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0 {
            return false
        }
        
        // M4A/AAC: "ftyp" at offset 4
        if bytes.count >= 8 && bytes[4] == 0x66 && bytes[5] == 0x74 &&
           bytes[6] == 0x79 && bytes[7] == 0x70 {
            // Could be ALAC (lossless) or AAC (lossy), inconclusive
            return nil
        }
        
        // Ogg container
        if bytes.count >= 4 && bytes[0] == 0x4F && bytes[1] == 0x67 &&
           bytes[2] == 0x67 && bytes[3] == 0x53 {
            // Need more analysis, return nil to try decoder
            return false
        }
        
        // Unknown format, let decoder handle it
        return nil
    }

    /// Fallback: detect lossless from file extension
    private static func detectLosslessFromExtension(url: URL) -> Bool? {
        let ext = url.pathExtension.lowercased()
        
        let losslessExtensions = ["flac", "ape", "wv", "tta", "wav", "wave", "aiff", "aif", "aifc", "alac"]
        let lossyExtensions = ["mp3", "aac", "m4a", "ogg", "opus", "mpc", "wma"]
        
        if losslessExtensions.contains(ext) {
            return true
        }
        if lossyExtensions.contains(ext) {
            return false
        }
        
        return nil
    }

    private static func extractMetadata(
        from audioMetadata: AudioMetadata,
        into metadata: inout TrackMetadata
    ) {
        // Core metadata
        metadata.title = audioMetadata.title
        metadata.artist = audioMetadata.artist
        metadata.album = audioMetadata.albumTitle
        metadata.composer = audioMetadata.composer
        metadata.genre = audioMetadata.genre
        metadata.albumArtist = audioMetadata.albumArtist

        // Track/Disc numbers (Int, not NSNumber)
        if let trackNumber = audioMetadata.trackNumber {
            metadata.trackNumber = trackNumber
        }
        if let trackTotal = audioMetadata.trackTotal {
            metadata.totalTracks = trackTotal
        }
        if let discNumber = audioMetadata.discNumber {
            metadata.discNumber = discNumber
        }
        if let discTotal = audioMetadata.discTotal {
            metadata.totalDiscs = discTotal
        }

        // Additional metadata
        if let bpm = audioMetadata.bpm {
            metadata.bpm = bpm
        }

        // Rating
        metadata.rating = extractRating(from: audioMetadata.rating)

        // Compilation (Bool, not NSNumber)
        metadata.compilation = audioMetadata.isCompilation ?? false

        // Dates and year
        if let releaseDate = audioMetadata.releaseDate {
            metadata.releaseDate = releaseDate

            // Extract year from release date if year not set
            if metadata.year == nil {
                metadata.year = extractYear(from: releaseDate)
            }
        }

        // Sorting fields
        metadata.sortTitle = audioMetadata.titleSortOrder
        metadata.sortArtist = audioMetadata.artistSortOrder
        metadata.sortAlbum = audioMetadata.albumTitleSortOrder
        metadata.sortAlbumArtist = audioMetadata.albumArtistSortOrder

        // Extended metadata - standard fields
        metadata.extended.isrc = audioMetadata.isrc
        metadata.extended.lyrics = audioMetadata.lyrics
        metadata.extended.comment = audioMetadata.comment
        metadata.extended.grouping = audioMetadata.grouping

        // MusicBrainz IDs
        metadata.extended.musicBrainzAlbumId =
            audioMetadata.musicBrainzReleaseID
        metadata.extended.musicBrainzTrackId =
            audioMetadata.musicBrainzRecordingID

        // ReplayGain
        if let replayGainTrackGain = audioMetadata.replayGainTrackGain {
            metadata.extended.replayGainTrack = String(
                format: "%+.2f dB",
                replayGainTrackGain
            )
        }
        if let replayGainAlbumGain = audioMetadata.replayGainAlbumGain {
            metadata.extended.replayGainAlbum = String(
                format: "%+.2f dB",
                replayGainAlbumGain
            )
        }

        // Extract extended fields from additionalMetadata dictionary
        if let additionalMetadata = audioMetadata.additionalMetadata {
            extractExtendedFields(from: additionalMetadata, into: &metadata)
        }
    }

    private static func extractExtendedFields(
        from additionalMetadata: [AnyHashable: Any],
        into metadata: inout TrackMetadata
    ) {
        for (key, value) in additionalMetadata {
            guard let keyString = key as? String,
                let stringValue = value as? String
            else { continue }

            let lowercaseKey = keyString.lowercased()

            // Label/Publisher
            if metadata.extended.label == nil
                && (lowercaseKey.contains("label") || lowercaseKey == "tpub")
            {
                metadata.extended.label = stringValue
            }

            // Publisher
            if metadata.extended.publisher == nil
                && lowercaseKey.contains("publisher")
            {
                metadata.extended.publisher = stringValue
            }

            // Copyright
            if metadata.extended.copyright == nil
                && lowercaseKey.contains("copyright")
            {
                metadata.extended.copyright = stringValue
            }

            // Personnel
            if metadata.extended.conductor == nil
                && (lowercaseKey == "tpe3"
                    || lowercaseKey.contains("conductor"))
            {
                metadata.extended.conductor = stringValue
            }
            if metadata.extended.remixer == nil
                && (lowercaseKey == "tpe4" || lowercaseKey.contains("remixer"))
            {
                metadata.extended.remixer = stringValue
            }
            if metadata.extended.producer == nil
                && (lowercaseKey == "tpro" || lowercaseKey.contains("producer"))
            {
                metadata.extended.producer = stringValue
            }
            if metadata.extended.engineer == nil
                && lowercaseKey.contains("engineer")
            {
                metadata.extended.engineer = stringValue
            }
            if metadata.extended.lyricist == nil
                && (lowercaseKey == "text" || lowercaseKey.contains("lyricist"))
            {
                metadata.extended.lyricist = stringValue
            }

            // Original artist
            if metadata.extended.originalArtist == nil
                && (lowercaseKey == "tope"
                    || lowercaseKey.contains("originalartist"))
            {
                metadata.extended.originalArtist = stringValue
            }

            // Descriptive fields
            if metadata.extended.subtitle == nil
                && (lowercaseKey.contains("subtitle") || lowercaseKey == "tit3")
            {
                metadata.extended.subtitle = stringValue
            }
            if metadata.extended.movement == nil
                && lowercaseKey.contains("movement")
            {
                metadata.extended.movement = stringValue
            }
            if metadata.extended.key == nil
                && (lowercaseKey == "tkey"
                    || lowercaseKey.contains("initialkey")
                    || lowercaseKey.contains("musicalkey"))
            {
                metadata.extended.key = stringValue
            }
            if metadata.extended.mood == nil && lowercaseKey.contains("mood") {
                metadata.extended.mood = stringValue
            }
            if metadata.extended.language == nil
                && (lowercaseKey == "tlan" || lowercaseKey.contains("language"))
            {
                metadata.extended.language = stringValue
            }

            // Identifiers
            if metadata.extended.barcode == nil
                && (lowercaseKey.contains("barcode")
                    || lowercaseKey.contains("upc"))
            {
                metadata.extended.barcode = stringValue
            }
            if metadata.extended.catalogNumber == nil
                && lowercaseKey.contains("catalog")
            {
                metadata.extended.catalogNumber = stringValue
            }

            // Encoding
            if metadata.extended.encodedBy == nil
                && (lowercaseKey == "tenc"
                    || lowercaseKey.contains("encodedby"))
            {
                metadata.extended.encodedBy = stringValue
            }
            if metadata.extended.encoderSettings == nil
                && (lowercaseKey == "tsse"
                    || lowercaseKey.contains("encodersettings"))
            {
                metadata.extended.encoderSettings = stringValue
            }

            // Recording date
            if metadata.extended.recordingDate == nil
                && lowercaseKey.contains("recordingdate")
            {
                metadata.extended.recordingDate = stringValue
            }

            // Original release date
            if metadata.originalReleaseDate == nil
                && (lowercaseKey.contains("originaldate")
                    || lowercaseKey == "tdor")
            {
                metadata.originalReleaseDate = stringValue
                // Also try to extract year if not set
                if metadata.year == nil {
                    let extractedYear = extractYear(from: stringValue)
                    if !extractedYear.isEmpty {
                        metadata.year = extractedYear
                    }
                }
            }

            // MusicBrainz IDs (additional ones not in standard fields)
            if metadata.extended.musicBrainzArtistId == nil
                && lowercaseKey.contains("musicbrainz")
                && lowercaseKey.contains("artist")
                && lowercaseKey.contains("id")
            {
                metadata.extended.musicBrainzArtistId = stringValue
            }
            if metadata.extended.musicBrainzAlbumArtistId == nil
                && lowercaseKey.contains("musicbrainz")
                && lowercaseKey.contains("albumartist")
                && lowercaseKey.contains("id")
            {
                metadata.extended.musicBrainzAlbumArtistId = stringValue
            }
            if metadata.extended.musicBrainzReleaseGroupId == nil
                && lowercaseKey.contains("musicbrainz")
                && lowercaseKey.contains("releasegroup")
            {
                metadata.extended.musicBrainzReleaseGroupId = stringValue
            }
            if metadata.extended.musicBrainzWorkId == nil
                && lowercaseKey.contains("musicbrainz")
                && lowercaseKey.contains("work") && lowercaseKey.contains("id")
            {
                metadata.extended.musicBrainzWorkId = stringValue
            }

            // AcoustID
            if metadata.extended.acoustId == nil
                && lowercaseKey.contains("acoustid")
                && !lowercaseKey.contains("fingerprint")
            {
                metadata.extended.acoustId = stringValue
            }
            if metadata.extended.acoustIdFingerprint == nil
                && lowercaseKey.contains("acoustid")
                && lowercaseKey.contains("fingerprint")
            {
                metadata.extended.acoustIdFingerprint = stringValue
            }

            // Composer sort order (not in standard AudioMetadata)
            if metadata.extended.sortComposer == nil
                && lowercaseKey.contains("composersort")
            {
                metadata.extended.sortComposer = stringValue
            }
        }
    }

    private static func extractArtwork(
        from audioMetadata: AudioMetadata,
        into metadata: inout TrackMetadata
    ) {
        // Get the first attached picture
        if let firstPicture = audioMetadata.attachedPictures.first {
            metadata.artworkData = firstPicture.imageData
        }
    }

    // MARK: - Helper Methods

    /// Extract a 4-digit year from a date string
    private static func extractYear(from dateString: String) -> String {
        // Try to find a 4-digit year (e.g., 2024, 1999)
        let yearPattern = #"\b(19|20)\d{2}\b"#

        if let regex = try? NSRegularExpression(pattern: yearPattern),
            let match = regex.firstMatch(
                in: dateString,
                range: NSRange(dateString.startIndex..., in: dateString)
            )
        {
            if let range = Range(match.range, in: dateString) {
                return String(dateString[range])
            }
        }

        return ""
    }
    
    /// Extract normalized rating value on a 0-5 scale
    private static func extractRating(from rawRating: Int?) -> Int? {
        guard let raw = rawRating, raw > 0 else { return nil }
        
        // Default rating range
        if raw <= 5 {
            return raw
        }
        
        // ID3v2 POPM rating range
        if raw <= 31 { return 1 }
        if raw <= 95 { return 2 }
        if raw <= 159 { return 3 }
        if raw <= 223 { return 4 }
        return 5
    }
}
