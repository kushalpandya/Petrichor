//
// SFBMetadataReader
//
// The SFBAudioEngine-backed metadata reader. It owns all the SFBAudioEngine tag,
// audio-property, and artwork parsing, so MetadataEngine stays backend-agnostic.
// A Crescendo reader sits alongside this behind the same MetadataReader protocol,
// selected by MediaBackend.
//

import Foundation
import SFBAudioEngine

struct SFBMetadataReader: MetadataReader {
    func extractMetadata(
        from url: URL,
        externalArtwork: Data?,
        artworkCache: ArtworkCompressionCache?
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
        await Self.extractAudioProperties(from: audioFile.properties, into: &metadata)

        // Extract metadata
        Self.extractMetadata(from: audioFile.metadata, into: &metadata)

        // Extract artwork
        await Self.extractArtwork(
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
        if let duration = properties.duration, duration.isFinite, duration >= 0 {
            metadata.duration = duration
        }

        // For MPEG audio (MP3/MP2/MP1), TagLib falls back to bitrate estimation
        // when no Xing/Info/VBRI header is present, which can be inaccurate.
        // Only use AVFoundation validation when SFBAudioEngine reports a suspicious duration,
        // since creating AVURLAsset for every MP3 is expensive.
        metadata.duration = await MetadataMapping.validatedDuration(
            metadata.duration,
            codec: metadata.codec,
            url: metadata.url,
            sourceName: "SFBAudioEngine"
        )

        // Sample rate
        if let sampleRate = properties.sampleRate, sampleRate > 0 {
            metadata.sampleRate = Int(sampleRate)
        }

        // Channels (AVAudioChannelCount, which is UInt32)
        if let channelCount = properties.channelCount, channelCount > 0 {
            metadata.channels = Int(channelCount)
        }

        // Bit depth
        if let bitDepth = properties.bitDepth, bitDepth > 0 {
            metadata.bitDepth = bitDepth
        }

        // Bitrate
        if let bitrate = properties.bitrate, bitrate > 0 {
            metadata.bitrate = Int(bitrate)
        }

        // Extract lossless flag using codec name from SFBAudioEngine (avoids redundant file I/O).
        metadata.lossless = MetadataMapping.isTrackLossless(codec: metadata.codec, url: metadata.url) ?? false
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
        metadata.rating = MetadataMapping.normalizedRating(fromRaw: audioMetadata.rating)

        // Compilation (Bool, not NSNumber)
        metadata.compilation = audioMetadata.isCompilation ?? false

        // Dates and year
        if let releaseDate = audioMetadata.releaseDate {
            metadata.releaseDate = releaseDate

            // Extract year from release date if year not set
            if metadata.year == nil {
                metadata.year = MetadataMapping.year(fromDateString: releaseDate)
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

    // swiftlint:disable:next cyclomatic_complexity
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
                && (lowercaseKey.contains("label") || lowercaseKey == "tpub") {
                metadata.extended.label = stringValue
            }

            // Publisher
            if metadata.extended.publisher == nil
                && lowercaseKey.contains("publisher") {
                metadata.extended.publisher = stringValue
            }

            // Copyright
            if metadata.extended.copyright == nil
                && lowercaseKey.contains("copyright") {
                metadata.extended.copyright = stringValue
            }

            // Personnel
            if metadata.extended.conductor == nil
                && (lowercaseKey == "tpe3"
                    || lowercaseKey.contains("conductor")) {
                metadata.extended.conductor = stringValue
            }
            if metadata.extended.remixer == nil
                && (lowercaseKey == "tpe4" || lowercaseKey.contains("remixer")) {
                metadata.extended.remixer = stringValue
            }
            if metadata.extended.producer == nil
                && (lowercaseKey == "tpro" || lowercaseKey.contains("producer")) {
                metadata.extended.producer = stringValue
            }
            if metadata.extended.engineer == nil
                && lowercaseKey.contains("engineer") {
                metadata.extended.engineer = stringValue
            }
            if metadata.extended.lyricist == nil
                && (lowercaseKey == "text" || lowercaseKey.contains("lyricist")) {
                metadata.extended.lyricist = stringValue
            }

            // Original artist
            if metadata.extended.originalArtist == nil
                && (lowercaseKey == "tope"
                    || lowercaseKey.contains("originalartist")) {
                metadata.extended.originalArtist = stringValue
            }

            // Descriptive fields
            if metadata.extended.subtitle == nil
                && (lowercaseKey.contains("subtitle") || lowercaseKey == "tit3") {
                metadata.extended.subtitle = stringValue
            }
            if metadata.extended.movement == nil
                && lowercaseKey.contains("movement") {
                metadata.extended.movement = stringValue
            }
            if metadata.extended.key == nil
                && (lowercaseKey == "tkey"
                    || lowercaseKey.contains("initialkey")
                    || lowercaseKey.contains("musicalkey")) {
                metadata.extended.key = stringValue
            }
            if metadata.extended.mood == nil && lowercaseKey.contains("mood") {
                metadata.extended.mood = stringValue
            }
            if metadata.extended.language == nil
                && (lowercaseKey == "tlan" || lowercaseKey.contains("language")) {
                metadata.extended.language = stringValue
            }

            // Identifiers
            if metadata.extended.barcode == nil
                && (lowercaseKey.contains("barcode")
                    || lowercaseKey.contains("upc")) {
                metadata.extended.barcode = stringValue
            }
            if metadata.extended.catalogNumber == nil
                && lowercaseKey.contains("catalog") {
                metadata.extended.catalogNumber = stringValue
            }

            // Encoding
            if metadata.extended.encodedBy == nil
                && (lowercaseKey == "tenc"
                    || lowercaseKey.contains("encodedby")) {
                metadata.extended.encodedBy = stringValue
            }
            if metadata.extended.encoderSettings == nil
                && (lowercaseKey == "tsse"
                    || lowercaseKey.contains("encodersettings")) {
                metadata.extended.encoderSettings = stringValue
            }

            // Recording date
            if metadata.extended.recordingDate == nil
                && lowercaseKey.contains("recordingdate") {
                metadata.extended.recordingDate = stringValue
            }

            // Original release date
            if metadata.originalReleaseDate == nil
                && (lowercaseKey.contains("originaldate")
                    || lowercaseKey == "tdor") {
                metadata.originalReleaseDate = stringValue
                // Also try to extract year if not set
                if metadata.year == nil {
                    metadata.year = MetadataMapping.year(fromDateString: stringValue)
                }
            }

            // MusicBrainz IDs (additional ones not in standard fields)
            if metadata.extended.musicBrainzArtistId == nil
                && lowercaseKey.contains("musicbrainz")
                && lowercaseKey.contains("artist")
                && lowercaseKey.contains("id") {
                metadata.extended.musicBrainzArtistId = stringValue
            }
            if metadata.extended.musicBrainzAlbumArtistId == nil
                && lowercaseKey.contains("musicbrainz")
                && lowercaseKey.contains("albumartist")
                && lowercaseKey.contains("id") {
                metadata.extended.musicBrainzAlbumArtistId = stringValue
            }
            if metadata.extended.musicBrainzReleaseGroupId == nil
                && lowercaseKey.contains("musicbrainz")
                && lowercaseKey.contains("releasegroup") {
                metadata.extended.musicBrainzReleaseGroupId = stringValue
            }
            if metadata.extended.musicBrainzWorkId == nil
                && lowercaseKey.contains("musicbrainz")
                && lowercaseKey.contains("work") && lowercaseKey.contains("id") {
                metadata.extended.musicBrainzWorkId = stringValue
            }

            // AcoustID
            if metadata.extended.acoustId == nil
                && lowercaseKey.contains("acoustid")
                && !lowercaseKey.contains("fingerprint") {
                metadata.extended.acoustId = stringValue
            }
            if metadata.extended.acoustIdFingerprint == nil
                && lowercaseKey.contains("acoustid")
                && lowercaseKey.contains("fingerprint") {
                metadata.extended.acoustIdFingerprint = stringValue
            }

            // Composer sort order (not in standard AudioMetadata)
            if metadata.extended.sortComposer == nil
                && lowercaseKey.contains("composersort") {
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
        // Prefer the tagged front cover, mirroring the Crescendo reader
        let pictures = audioMetadata.attachedPictures
        guard let cover = pictures.first(where: { $0.type == .frontCover }) ?? pictures.first else { return }

        metadata.artworkData = await MetadataMapping.compressedArtwork(
            from: cover.imageData,
            source: source,
            cache: artworkCache
        )
    }
}
