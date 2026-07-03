//
// CrescendoMetadataReader
//
// The Crescendo-backed metadata reader. It owns the Crescendo import and maps
// `CrescendoMetadata` onto Petrichor's `TrackMetadata`, so MetadataEngine stays
// backend-agnostic. Note: this Petrichor type intentionally shares its name with
// Crescendo's own `CrescendoMetadataReader` enum; the module's type is referenced
// as `Crescendo.CrescendoMetadataReader` below to disambiguate.
//

import Crescendo
import Foundation

struct CrescendoMetadataReader: MetadataReader {
    func extractMetadata(
        from url: URL,
        externalArtwork: Data?,
        artworkCache: ArtworkCompressionCache?
    ) async -> TrackMetadata {
        var metadata = TrackMetadata(url: url)

        let source: CrescendoMetadata
        do {
            source = try await Crescendo.CrescendoMetadataReader.read(from: url)
        } catch {
            Logger.error("Failed to read metadata for \(url.lastPathComponent): \(error.localizedDescription)")
            return metadata
        }

        await map(source, into: &metadata)

        // Prefer the tagged front cover; multi-picture files can store a back cover first
        let cover = source.pictures.first { $0.pictureType == "Front Cover" } ?? source.pictures.first
        if let cover {
            metadata.artworkData = await MetadataMapping.compressedArtwork(
                from: cover.data,
                source: url.lastPathComponent,
                cache: artworkCache
            )
        }

        if metadata.artworkData == nil, let externalArtwork = externalArtwork {
            metadata.artworkData = externalArtwork
        }

        return metadata
    }

    private func map(_ source: CrescendoMetadata, into metadata: inout TrackMetadata) async {
        // Core metadata
        metadata.title = source.title
        metadata.artist = source.artist
        metadata.album = source.albumTitle
        metadata.composer = source.composer
        metadata.genre = source.genre
        metadata.albumArtist = source.albumArtist
        metadata.trackNumber = source.trackNumber
        metadata.totalTracks = source.trackTotal
        metadata.discNumber = source.discNumber
        metadata.totalDiscs = source.discTotal
        metadata.bpm = source.bpm
        metadata.rating = MetadataMapping.normalizedRating(fromRaw: source.rating)
        metadata.compilation = source.isCompilation ?? false
        metadata.mediaType = source.mediaType

        // Audio properties
        if source.duration.isFinite, source.duration >= 0 {
            metadata.duration = await MetadataMapping.validatedDuration(
                source.duration,
                codec: source.codec,
                url: metadata.url,
                sourceName: "Crescendo"
            )
        }
        if source.sampleRate > 0 { metadata.sampleRate = source.sampleRate }
        if source.channelCount > 0 { metadata.channels = source.channelCount }
        // Crescendo reports bitrate in bits/sec; Petrichor stores and displays
        // kbps (as SFB/TagLib does), so convert.
        if let bitrate = source.bitrate, bitrate > 0 { metadata.bitrate = (bitrate + 500) / 1000 }
        if let bitDepth = source.bitDepth, bitDepth > 0 { metadata.bitDepth = bitDepth }
        metadata.codec = source.codec
        // Prefer Crescendo's typed flag; fall back only if TagLib could not classify it.
        metadata.lossless = MetadataMapping.isTrackLossless(codec: source.codec, url: metadata.url, fallback: source.lossless)

        // Dates and year
        if let releaseDate = source.releaseDate {
            metadata.releaseDate = releaseDate
            if metadata.year == nil {
                metadata.year = MetadataMapping.year(fromDateString: releaseDate)
            }
        }
        if let originalReleaseDate = source.originalReleaseDate {
            metadata.originalReleaseDate = originalReleaseDate
            if metadata.year == nil {
                metadata.year = MetadataMapping.year(fromDateString: originalReleaseDate)
            }
        }

        // Sorting fields
        metadata.sortTitle = source.titleSortOrder
        metadata.sortArtist = source.artistSortOrder
        metadata.sortAlbum = source.albumTitleSortOrder
        metadata.sortAlbumArtist = source.albumArtistSortOrder

        map(extended: source, into: &metadata)
    }

    private func map(extended source: CrescendoMetadata, into metadata: inout TrackMetadata) {
        metadata.extended.isrc = source.isrc
        metadata.extended.barcode = source.barcode
        metadata.extended.catalogNumber = source.catalogNumber

        metadata.extended.musicBrainzArtistId = source.musicBrainzArtistID
        metadata.extended.musicBrainzAlbumId = source.musicBrainzReleaseID
        metadata.extended.musicBrainzAlbumArtistId = source.musicBrainzAlbumArtistID
        metadata.extended.musicBrainzTrackId = source.musicBrainzRecordingID
        metadata.extended.musicBrainzReleaseGroupId = source.musicBrainzReleaseGroupID
        metadata.extended.musicBrainzWorkId = source.musicBrainzWorkID

        metadata.extended.acoustId = source.acoustID
        metadata.extended.acoustIdFingerprint = source.acoustIDFingerprint

        metadata.extended.originalArtist = source.originalArtist
        metadata.extended.producer = source.producer
        metadata.extended.engineer = source.engineer
        metadata.extended.lyricist = source.lyricist
        metadata.extended.conductor = source.conductor
        metadata.extended.remixer = source.remixer

        metadata.extended.label = source.label
        metadata.extended.publisher = source.publisher
        metadata.extended.copyright = source.copyright

        metadata.extended.key = source.initialKey
        metadata.extended.mood = source.mood
        metadata.extended.language = source.language
        metadata.extended.lyrics = source.lyrics
        metadata.extended.comment = source.comment
        metadata.extended.subtitle = source.subtitle
        metadata.extended.grouping = source.grouping
        metadata.extended.movement = source.movement

        metadata.extended.encodedBy = source.encodedBy
        metadata.extended.encoderSettings = source.encoderSettings
        metadata.extended.recordingDate = source.recordingDate
        metadata.extended.sortComposer = source.composerSortOrder

        if let trackGain = source.replayGainTrackGain {
            metadata.extended.replayGainTrack = String(format: "%+.2f dB", trackGain)
        }
        if let albumGain = source.replayGainAlbumGain {
            metadata.extended.replayGainAlbum = String(format: "%+.2f dB", albumGain)
        }
    }
}
