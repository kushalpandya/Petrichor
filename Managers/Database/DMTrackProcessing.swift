//
// DatabaseManager class extension
//
// This extension contains methods for track processing as found from folders added.
//

import Foundation
import GRDB

extension DatabaseManager {
    /// Process a batch of music files with normalized data support
    func processBatch(_ batch: [(url: URL, folderId: Int64)]) async throws {
        await MainActor.run {
            self.isScanning = true
            self.scanStatusMessage = "Processing \(batch.count) files..."
        }
        
        // Process files concurrently but collect results
        try await withThrowingTaskGroup(of: (URL, TrackProcessResult).self) { group in
            for (fileURL, folderId) in batch {
                group.addTask { [weak self] in
                    guard let self = self else { return (fileURL, TrackProcessResult.skipped) }
                    
                    await MainActor.run {
                        self.scanStatusMessage = "Processing: \(fileURL.lastPathComponent)"
                    }
                    
                    do {
                        // Check if track already exists
                        if let existingTrack = try await self.dbQueue.read({ db in
                            try Track.filter(Track.Columns.path == fileURL.path).fetchOne(db)
                        }) {
                            // Check if file has been modified
                            if let attributes = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                               let modificationDate = attributes.contentModificationDate,
                               let trackModifiedDate = existingTrack.dateModified,
                               modificationDate <= trackModifiedDate {
                                return (fileURL, TrackProcessResult.skipped)
                            }
                            
                            // File has changed, extract metadata
                            let metadata = MetadataExtractor.extractMetadataSync(from: fileURL)
                            var updatedTrack = existingTrack
                            
                            let hasChanges = self.updateTrackIfNeeded(&updatedTrack, with: metadata, at: fileURL)
                            
                            if hasChanges {
                                return (fileURL, TrackProcessResult.update(updatedTrack, metadata))
                            } else {
                                return (fileURL, TrackProcessResult.skipped)
                            }
                        } else {
                            // New track
                            let metadata = MetadataExtractor.extractMetadataSync(from: fileURL)
                            var track = Track(url: fileURL)
                            track.folderId = folderId
                            self.applyMetadataToTrack(&track, from: metadata, at: fileURL)
                            
                            return (fileURL, TrackProcessResult.new(track, metadata))
                        }
                    } catch {
                        // Log the error and skip this track
                        Logger.error("Failed to process track \(fileURL.lastPathComponent): \(error)")
                        return (fileURL, TrackProcessResult.skipped)
                    }
                }
            }
            
            // Collect results into a single structure to avoid concurrent mutations
            let processResults = try await group.reduce(into: (new: [(Track, TrackMetadata)](), update: [(Track, TrackMetadata)](), skipped: 0)) { result, item in
                let (_, trackResult) = item
                switch trackResult {
                case .new(let track, let metadata):
                    result.new.append((track, metadata))
                case .update(let track, let metadata):
                    result.update.append((track, metadata))
                case .skipped:
                    result.skipped += 1
                }
            }
            
            // Process in database transaction
            try await dbQueue.write { [processResults] db in
                // Process new tracks
                for (track, metadata) in processResults.new {
                    do {
                        try self.processNewTrack(track, metadata: metadata, in: db)
                    } catch {
                        // Report error and continue with other tracks
                        Logger.error("Failed to add new track \(track.title): \(error)")
                    }
                }
                
                // Process updated tracks
                for (track, metadata) in processResults.update {
                    do {
                        try self.processUpdatedTrack(track, metadata: metadata, in: db)
                    } catch {
                        // Report error and continue with other tracks
                        Logger.error("Failed to update track \(track.title): \(error)")
                    }
                }
                
                // Update statistics after batch
                if !processResults.new.isEmpty || !processResults.update.isEmpty {
                    try self.updateEntityStats(in: db)
                }
            }
            
            let r = processResults
            Logger.info("Batch processing complete: \(r.new.count) new, \(r.update.count) updated, \(r.skipped) skipped")
            
            // After batch processing is complete, detect duplicates
            await detectAndMarkDuplicates()
        }
        
        await MainActor.run {
            self.isScanning = false
            self.scanStatusMessage = "Scan complete"
        }
    }
    
    // MARK: - Track Processing
    
    /// Process a new track with normalized data
    private func processNewTrack(_ track: Track, metadata: TrackMetadata, in db: Database) throws {
        var mutableTrack = track
        
        // Process album first (so we can link the track to it)
        try processTrackAlbum(&mutableTrack, in: db)
        
        // Insert the track
        try mutableTrack.insert(db)
        
        // Ensure we have a valid track ID (fallback to lastInsertedRowID if needed)
        if mutableTrack.trackId == nil {
            mutableTrack.trackId = db.lastInsertedRowID
        }
        
        guard let trackId = mutableTrack.trackId else {
            throw DatabaseError.invalidTrackId
        }
        
        Logger.info("Added new track: \(mutableTrack.title) (ID: \(trackId))")
        
        // Process normalized relationships
        try processTrackArtists(mutableTrack, metadata: metadata, in: db)
        try processTrackGenres(mutableTrack, in: db)
        
        // Update artwork for artists and album if this track has artwork
        if let artworkData = metadata.artworkData, !artworkData.isEmpty {
            // Update artist artwork
            let artistIds = try TrackArtist
                .filter(TrackArtist.Columns.trackId == trackId)
                .select(TrackArtist.Columns.artistId, as: Int64.self)
                .distinct()
                .fetchAll(db)
            
            for artistId in artistIds {
                try updateArtistArtwork(artistId, artworkData: artworkData, in: db)
            }
            
            // Update album artwork
            if let albumId = mutableTrack.albumId {
                try updateAlbumArtwork(albumId, artworkData: artworkData, in: db)
            }
        }
        
        // Log interesting metadata
        #if DEBUG
        logTrackMetadata(mutableTrack)
        #endif
    }
    
    /// Process an updated track with normalized data
    private func processUpdatedTrack(_ track: Track, metadata: TrackMetadata, in db: Database) throws {
        var mutableTrack = track
        
        // Update album association
        try processTrackAlbum(&mutableTrack, in: db)
        
        // Update the track
        try mutableTrack.update(db)
        
        guard let trackId = mutableTrack.trackId else {
            throw DatabaseError.invalidTrackId
        }
        
        Logger.info("Updated track: \(mutableTrack.title) (ID: \(trackId))")
        
        // Clear existing relationships
        try TrackArtist
            .filter(TrackArtist.Columns.trackId == trackId)
            .deleteAll(db)
        
        try TrackGenre
            .filter(TrackGenre.Columns.trackId == trackId)
            .deleteAll(db)
        
        // Re-process normalized relationships
        try processTrackArtists(mutableTrack, metadata: metadata, in: db)
        try processTrackGenres(mutableTrack, in: db)
    }
    
    // MARK: - Single File Processing (for legacy compatibility)
    
    /// Process a single music file
    func processMusicFile(at fileURL: URL, folderId: Int64) async throws {
        try await processBatch([(url: fileURL, folderId: folderId)])
    }
    
    // MARK: - Metadata Logging
    
    private func logTrackMetadata(_ track: Track) {
        // Log interesting metadata for debugging
        if let extendedMetadata = track.extendedMetadata {
            var interestingFields: [String] = []
            
            if let isrc = extendedMetadata.isrc { interestingFields.append("ISRC: \(isrc)") }
            if let label = extendedMetadata.label { interestingFields.append("Label: \(label)") }
            if let conductor = extendedMetadata.conductor { interestingFields.append("Conductor: \(conductor)") }
            if let producer = extendedMetadata.producer { interestingFields.append("Producer: \(producer)") }
            
            if !interestingFields.isEmpty {
                Logger.info("Extended metadata: \(interestingFields.joined(separator: ", "))")
            }
        }
        
        // Log multi-artist info
        if track.artist.contains(";") || track.artist.contains(",") || track.artist.contains("&") {
            Logger.info("Multi-artist track: \(track.artist)")
        }
        
        // Log album artist if different from artist
        if let albumArtist = track.albumArtist, albumArtist != track.artist {
            Logger.info("Album artist differs: \(albumArtist)")
        }
    }
    
    // MARK: - Duplicates Matching
    /// Detect and mark duplicate tracks in the library
    func detectAndMarkDuplicates() async {
        do {
            try await dbQueue.write { db in
                // First, reset all duplicate flags
                try Track.updateAll(db,
                                    Track.Columns.isDuplicate.set(to: false),
                                    Track.Columns.primaryTrackId.set(to: nil),
                                    Track.Columns.duplicateGroupId.set(to: nil)
                )
                
                // Get all tracks
                let allTracks = try Track.fetchAll(db)
                
                // Group tracks by duplicate key
                var duplicateGroups: [String: [Track]] = [:]
                
                for track in allTracks {
                    let key = track.duplicateKey
                    if duplicateGroups[key] == nil {
                        duplicateGroups[key] = []
                    }
                    duplicateGroups[key]?.append(track)
                }
                
                // Process each group that has duplicates
                for (_, tracks) in duplicateGroups where tracks.count > 1 {
                    // Sort by quality score (highest first)
                    let sortedTracks = tracks.sorted { $0.qualityScore > $1.qualityScore }
                    
                    // The first track is the primary (highest quality)
                    guard let primaryTrack = sortedTracks.first,
                          let primaryId = primaryTrack.trackId else { continue }
                    
                    // Generate a unique group ID
                    let groupId = UUID().uuidString
                    
                    // Update all tracks in the group
                    for track in sortedTracks {
                        guard let trackId = track.trackId else { continue }
                        
                        if trackId == primaryId {
                            // This is the primary track
                            try Track
                                .filter(Track.Columns.trackId == trackId)
                                .updateAll(db,
                                           Track.Columns.isDuplicate.set(to: false),
                                           Track.Columns.primaryTrackId.set(to: nil),
                                           Track.Columns.duplicateGroupId.set(to: groupId)
                                )
                        } else {
                            // This is a duplicate
                            try Track
                                .filter(Track.Columns.trackId == trackId)
                                .updateAll(db,
                                           Track.Columns.isDuplicate.set(to: true),
                                           Track.Columns.primaryTrackId.set(to: primaryId),
                                           Track.Columns.duplicateGroupId.set(to: groupId)
                                )
                        }
                    }
                }
                
                // Log results
                let duplicateCount = try Track.filter(Track.Columns.isDuplicate == true).fetchCount(db)
                let groupCount = try Track
                    .select(Track.Columns.duplicateGroupId, as: String?.self)
                    .distinct()
                    .filter(Track.Columns.duplicateGroupId != nil)
                    .fetchCount(db)
                
                Logger.info("Duplicate detection complete: \(duplicateCount) duplicates found in \(groupCount) groups")
            }
        } catch {
            Logger.error("Failed to detect duplicates: \(error)")
        }
    }
    
    /// Get tracks respecting the hide duplicates setting
    func getTracksRespectingDuplicates(hideDuplicates: Bool) -> [Track] {
        do {
            return try dbQueue.read { db in
                if hideDuplicates {
                    return try Track
                        .filter(Track.Columns.isDuplicate == false)
                        .fetchAll(db)
                } else {
                    return try Track.fetchAll(db)
                }
            }
        } catch {
            Logger.error("Failed to fetch tracks: \(error)")
            return []
        }
    }
    
    /// Get tracks for a folder (always shows all tracks regardless of duplicate setting)
    func getTracksForFolderIgnoringDuplicates(_ folderId: Int64) -> [Track] {
        do {
            return try dbQueue.read { db in
                try Track
                    .filter(Track.Columns.folderId == folderId)
                    .fetchAll(db)
            }
        } catch {
            Logger.error("Failed to fetch tracks for folder: \(error)")
            return []
        }
    }
}
