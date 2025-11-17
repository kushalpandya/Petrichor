//
// DatabaseManager class extension
//
// This extension contains track metadata management methods which allow for setting up parsed
// track information into track table.
//

import Foundation

extension DatabaseManager {
    func applyMetadataToTrack(_ track: inout FullTrack, from metadata: TrackMetadata, at fileURL: URL) {
        // Core fields
        track.title = metadata.title ?? fileURL.deletingPathExtension().lastPathComponent
        track.artist = metadata.artist ?? "Unknown Artist"
        track.album = metadata.album ?? "Unknown Album"
        track.genre = metadata.genre ?? "Unknown Genre"
        track.composer = metadata.composer ?? "Unknown Composer"
        track.year = metadata.year ?? ""
        track.duration = metadata.duration
        
        // Avoid storing album art in track table for tracks with albums
        // as we'll store it in albums table instead.
        if track.album == "Unknown Album" || track.album.isEmpty {
            track.trackArtworkData = metadata.artworkData
        } else {
            track.trackArtworkData = nil
        }

        track.isMetadataLoaded = true

        // Additional metadata
        track.albumArtist = metadata.albumArtist
        track.trackNumber = metadata.trackNumber
        track.totalTracks = metadata.totalTracks
        track.discNumber = metadata.discNumber
        track.totalDiscs = metadata.totalDiscs
        track.rating = metadata.rating
        track.compilation = metadata.compilation
        track.releaseDate = metadata.releaseDate
        track.originalReleaseDate = metadata.originalReleaseDate
        track.bpm = metadata.bpm
        track.mediaType = metadata.mediaType

        // Sort fields
        track.sortTitle = metadata.sortTitle
        track.sortArtist = metadata.sortArtist
        track.sortAlbum = metadata.sortAlbum
        track.sortAlbumArtist = metadata.sortAlbumArtist

        // Audio properties
        track.bitrate = metadata.bitrate
        track.sampleRate = metadata.sampleRate
        track.channels = metadata.channels
        track.codec = metadata.codec
        track.bitDepth = metadata.bitDepth
        track.lossless = metadata.lossless

        // File properties
        if let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
            track.fileSize = attributes.fileSize.map { Int64($0) }
            track.dateModified = attributes.contentModificationDate
        }

        // Extended metadata
        track.extendedMetadata = metadata.extended
    }

    func updateTrackIfNeeded(_ track: inout FullTrack, with metadata: TrackMetadata, at fileURL: URL) -> Bool {
        var hasChanges = false

        // Update core metadata
        hasChanges = updateCoreMetadata(&track, with: metadata) || hasChanges

        // Update additional metadata
        hasChanges = updateAdditionalMetadata(&track, with: metadata) || hasChanges

        // Update audio properties
        hasChanges = updateAudioProperties(&track, with: metadata) || hasChanges

        // Update file properties
        hasChanges = updateFileProperties(&track, at: fileURL) || hasChanges

        // Always update extended metadata
        track.extendedMetadata = metadata.extended
        hasChanges = true

        return hasChanges
    }

    func updateCoreMetadata(_ track: inout FullTrack, with metadata: TrackMetadata) -> Bool {
        var hasChanges = false

        if let newTitle = metadata.title, !newTitle.isEmpty && newTitle != track.title {
            track.title = newTitle
            hasChanges = true
        }

        if let newArtist = metadata.artist, !newArtist.isEmpty && newArtist != track.artist {
            track.artist = newArtist
            hasChanges = true
        }

        if let newAlbum = metadata.album, !newAlbum.isEmpty && newAlbum != track.album {
            track.album = newAlbum
            hasChanges = true
        }

        if let newGenre = metadata.genre,
           !newGenre.isEmpty,
           track.genre == "Unknown Genre" || track.genre != newGenre {
            track.genre = newGenre
            hasChanges = true
        }

        if let newComposer = metadata.composer,
           !newComposer.isEmpty,
           track.composer == "Unknown Composer" || track.composer.isEmpty || track.composer != newComposer {
            track.composer = newComposer
            hasChanges = true
        }

        if let newYear = metadata.year,
           !newYear.isEmpty,
           track.year.isEmpty || track.year == "Unknown Year" || track.year != newYear {
            track.year = newYear
            hasChanges = true
        }

        if metadata.duration > 0 && abs(metadata.duration - track.duration) > 0.1 {
            track.duration = metadata.duration
            hasChanges = true
        }

        if let newArtworkData = metadata.artworkData {
            let shouldStoreInTrack = (track.album == "Unknown Album" || track.album.isEmpty)
            
            if shouldStoreInTrack && track.trackArtworkData == nil {
                // Store artwork for tracks without albums
                track.trackArtworkData = newArtworkData
                hasChanges = true
            } else if !shouldStoreInTrack && track.trackArtworkData != nil {
                // Clear artwork for tracks with albums
                track.trackArtworkData = nil
                hasChanges = true
            }
        }

        return hasChanges
    }

    func updateAdditionalMetadata(_ track: inout FullTrack, with metadata: TrackMetadata) -> Bool {
        var hasChanges = false

        // Album metadata
        if let newAlbumArtist = metadata.albumArtist, !newAlbumArtist.isEmpty && newAlbumArtist != track.albumArtist {
            track.albumArtist = newAlbumArtist
            hasChanges = true
        }

        // Track/Disc numbers
        if let newTrackNumber = metadata.trackNumber, newTrackNumber != track.trackNumber {
            track.trackNumber = newTrackNumber
            hasChanges = true
        }

        if let newTotalTracks = metadata.totalTracks, newTotalTracks != track.totalTracks {
            track.totalTracks = newTotalTracks
            hasChanges = true
        }

        if let newDiscNumber = metadata.discNumber, newDiscNumber != track.discNumber {
            track.discNumber = newDiscNumber
            hasChanges = true
        }

        if let newTotalDiscs = metadata.totalDiscs, newTotalDiscs != track.totalDiscs {
            track.totalDiscs = newTotalDiscs
            hasChanges = true
        }

        // Other metadata
        if let newRating = metadata.rating, newRating != track.rating {
            track.rating = newRating
            hasChanges = true
        }

        if metadata.compilation != track.compilation {
            track.compilation = metadata.compilation
            hasChanges = true
        }

        if let newReleaseDate = metadata.releaseDate, !newReleaseDate.isEmpty && newReleaseDate != track.releaseDate {
            track.releaseDate = newReleaseDate
            hasChanges = true
        }

        if let newOriginalReleaseDate = metadata.originalReleaseDate,
           !newOriginalReleaseDate.isEmpty,
           newOriginalReleaseDate != track.originalReleaseDate {
            track.originalReleaseDate = newOriginalReleaseDate
            hasChanges = true
        }

        if let newBpm = metadata.bpm, newBpm != track.bpm {
            track.bpm = newBpm
            hasChanges = true
        }

        if let newMediaType = metadata.mediaType, !newMediaType.isEmpty && newMediaType != track.mediaType {
            track.mediaType = newMediaType
            hasChanges = true
        }

        // Sort fields
        if let newSortTitle = metadata.sortTitle, !newSortTitle.isEmpty && newSortTitle != track.sortTitle {
            track.sortTitle = newSortTitle
            hasChanges = true
        }

        if let newSortArtist = metadata.sortArtist, !newSortArtist.isEmpty && newSortArtist != track.sortArtist {
            track.sortArtist = newSortArtist
            hasChanges = true
        }

        if let newSortAlbum = metadata.sortAlbum, !newSortAlbum.isEmpty && newSortAlbum != track.sortAlbum {
            track.sortAlbum = newSortAlbum
            hasChanges = true
        }

        if let newSortAlbumArtist = metadata.sortAlbumArtist, !newSortAlbumArtist.isEmpty && newSortAlbumArtist != track.sortAlbumArtist {
            track.sortAlbumArtist = newSortAlbumArtist
            hasChanges = true
        }

        return hasChanges
    }

    func updateAudioProperties(_ track: inout FullTrack, with metadata: TrackMetadata) -> Bool {
        var hasChanges = false

        if let newBitrate = metadata.bitrate, newBitrate != track.bitrate {
            track.bitrate = newBitrate
            hasChanges = true
        }

        if let newSampleRate = metadata.sampleRate, newSampleRate != track.sampleRate {
            track.sampleRate = newSampleRate
            hasChanges = true
        }

        if let newChannels = metadata.channels, newChannels != track.channels {
            track.channels = newChannels
            hasChanges = true
        }

        if let newCodec = metadata.codec, !newCodec.isEmpty && newCodec != track.codec {
            track.codec = newCodec
            hasChanges = true
        }

        if let newBitDepth = metadata.bitDepth, newBitDepth != track.bitDepth {
            track.bitDepth = newBitDepth
            hasChanges = true
        }
        
        if let newLossless = metadata.lossless, newLossless != track.lossless {
            track.lossless = newLossless
            hasChanges = true
        }

        return hasChanges
    }

    func updateFileProperties(_ track: inout FullTrack, at fileURL: URL) -> Bool {
        var hasChanges = false

        if let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
            if let newFileSize = attributes.fileSize.map({ Int64($0) }), newFileSize != track.fileSize {
                track.fileSize = newFileSize
                hasChanges = true
            }

            if let newDateModified = attributes.contentModificationDate, newDateModified != track.dateModified {
                track.dateModified = newDateModified
                hasChanges = true
            }
        }

        return hasChanges
    }
}
