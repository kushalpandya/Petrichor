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

        map(source, into: &metadata)

        if let firstPicture = source.pictures.first {
            metadata.artworkData = await MetadataMapping.compressedArtwork(
                from: firstPicture.data,
                source: url.lastPathComponent,
                cache: artworkCache
            )
        }

        if metadata.artworkData == nil, let externalArtwork = externalArtwork {
            metadata.artworkData = externalArtwork
        }

        return metadata
    }

    private func map(_ source: CrescendoMetadata, into metadata: inout TrackMetadata) {
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
            metadata.duration = source.duration
        }
        if source.sampleRate > 0 { metadata.sampleRate = source.sampleRate }
        if source.channelCount > 0 { metadata.channels = source.channelCount }
        if let bitrate = source.bitrate, bitrate > 0 { metadata.bitrate = bitrate }
        if let bitDepth = source.bitDepth, bitDepth > 0 { metadata.bitDepth = bitDepth }
        metadata.codec = source.codec
        // Crescendo reports a typed lossless flag, so use it directly rather than
        // re-deriving from the codec string.
        metadata.lossless = source.lossless

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
                let extractedYear = MetadataMapping.year(fromDateString: originalReleaseDate)
                if !extractedYear.isEmpty { metadata.year = extractedYear }
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
