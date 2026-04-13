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

// MARK: - Artwork Compression Cache

/// Thread-safe cache for compressed artwork data within a processing chunk.
/// Avoids re-compressing identical album artwork across tracks in the same batch.
actor ArtworkCompressionCache {
    private var cache: [Int: Data] = [:]

    func get(for data: Data) -> Data? {
        cache[data.hashValue]
    }

    func store(original: Data, compressed: Data) {
        cache[original.hashValue] = compressed
    }
}

// MARK: - Metadata Extractor

class MetadataExtractor {

    // MARK: - Public Methods

    /// Extract metadata from an audio file using SFBAudioEngine
    /// - Parameters:
    ///   - url: The URL of the audio file
    ///   - externalArtwork: Optional external artwork to use if file has none
    ///   - artworkCache: Optional shared cache to avoid re-compressing identical artwork
    /// - Returns: TrackMetadata containing all extracted information
    static func extractMetadata(
        from url: URL,
        externalArtwork: Data? = nil,
        artworkCache: ArtworkCompressionCache? = nil
    ) async -> TrackMetadata {
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
        await extractAudioProperties(from: audioFile.properties, into: &metadata)

        // Extract metadata
        extractMetadata(from: audioFile.metadata, into: &metadata)

        // Extract artwork
        await extractArtwork(
            from: audioFile.metadata,
            into: &metadata,
            source: url.lastPathComponent,
            artworkCache: artworkCache
        )

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
                        artworkMap[directory] = ImageUtils.compressImage(from: data, source: url.path) ?? data
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
    ) async {
        // Format/Codec
        if let formatName = properties.formatName {
            metadata.codec = formatName
        }
        
        // Duration (TimeInterval is a typealias for Double)
        if let duration = properties.duration {
            metadata.duration = duration
        }

        // For MPEG audio (MP3/MP2/MP1), TagLib falls back to bitrate estimation
        // when no Xing/Info/VBRI header is present, which can be inaccurate.
        // Only use AVFoundation validation when SFBAudioEngine reports a suspicious duration,
        // since creating AVURLAsset for every MP3 is expensive.
        let isMPEG = metadata.codec == "MP3" || metadata.codec?.hasPrefix("MPEG") == true
        if isMPEG {
            let suspicious = metadata.duration <= 0
                || metadata.duration.isNaN
                || metadata.duration.isInfinite
                || metadata.duration < 1.0

            if suspicious {
                let asset = AVURLAsset(url: metadata.url)
                let avDuration: Double
                do {
                    let duration = try await asset.load(.duration)
                    avDuration = duration.seconds
                } catch {
                    avDuration = 0
                }
                if avDuration.isFinite && avDuration > 0
                    && abs(avDuration - metadata.duration) > 1.0 {
                    Logger.warning(
                        "MPEG duration mismatch for \(metadata.url.lastPathComponent) - " +
                        "SFBAudioEngine: \(metadata.duration)s, AVAsset: \(avDuration)s. Using AVAsset value."
                    )
                    metadata.duration = avDuration
                }
            }
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

        // Extract lossless flag using codec name from SFBAudioEngine (avoids redundant file I/O)
        metadata.lossless = isTrackLossless(codec: metadata.codec, url: metadata.url)
    }

    /// Detect lossless status using codec name from SFBAudioEngine, falling back to file extension
    private static func isTrackLossless(codec: String?, url: URL) -> Bool {
        if let codec = codec {
            let upper = codec.uppercased()

            let losslessCodecs: Set<String> = [
                "FLAC", "ALAC", "AIFF", "WAV", "WAVE", "PCM",
                "APE", "WAVPACK", "TTA"
            ]
            if losslessCodecs.contains(upper)
                || upper.hasPrefix("AIFF") || upper.hasPrefix("PCM") {
                return true
            }

            let lossyCodecs: Set<String> = [
                "MP3", "AAC", "OGG VORBIS", "OPUS", "MUSEPACK"
            ]
            if lossyCodecs.contains(upper) || upper.hasPrefix("MPEG") {
                return false
            }
        }

        return detectLosslessFromExtension(url: url) ?? false
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
        into metadata: inout TrackMetadata,
        source: String? = nil,
        artworkCache: ArtworkCompressionCache? = nil
    ) async {
        guard let firstPicture = audioMetadata.attachedPictures.first else { return }

        let rawData = firstPicture.imageData

        // Check cache for previously compressed identical artwork
        if let cache = artworkCache, let cached = await cache.get(for: rawData) {
            metadata.artworkData = cached
            return
        }

        let compressed = ImageUtils.compressImage(from: rawData, source: source) ?? rawData
        metadata.artworkData = compressed

        // Store in cache for subsequent tracks with identical artwork
        if let cache = artworkCache {
            await cache.store(original: rawData, compressed: compressed)
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
}
