//
// DatabaseManager class extension
//
// This extension contains methods for track processing as found from folders added.
//

import Foundation
import GRDB

extension DatabaseManager {
    /// Process a batch of music files with normalized data support
    func processBatch(_ batch: [(url: URL, folderId: Int64)], artworkMap: [URL: Data] = [:]) async throws {
        // Determine optimal concurrency based on system resources
        let processorCount = ProcessInfo.processInfo.processorCount
        let optimalConcurrency = max(4, min(processorCount * 2, 16))
        
        Logger.info("Processing batch of \(batch.count) files with concurrency: \(optimalConcurrency)")
        
        // Process files concurrently with controlled concurrency
        try await withThrowingTaskGroup(of: (URL, TrackProcessResult).self) { group in
            var pendingURLs = batch
            var activeTasks = 0
            
            // Fill initial task pool
            while activeTasks < optimalConcurrency && !pendingURLs.isEmpty {
                let item = pendingURLs.removeFirst()
                addProcessingTask(to: &group, item: item, artworkMap: artworkMap)
                activeTasks += 1
            }
            
            // Process results and add new tasks as they complete
            var processResults = (
                new: [(FullTrack, TrackMetadata)](),
                update: [(FullTrack, TrackMetadata)](),
                skipped: 0
            )
            
            while let result = try await group.next() {
                activeTasks -= 1
                
                // Collect result
                let (_, trackResult) = result
                switch trackResult {
                case .new(let track, let metadata):
                    processResults.new.append((track, metadata))
                case .update(let track, let metadata):
                    processResults.update.append((track, metadata))
                case .skipped:
                    processResults.skipped += 1
                }
                
                // Add next task if available
                if !pendingURLs.isEmpty {
                    let item = pendingURLs.removeFirst()
                    addProcessingTask(to: &group, item: item, artworkMap: artworkMap)
                    activeTasks += 1
                }
            }
            
            // Process in database transaction
            try await dbQueue.write { [processResults] db in
                // Process new tracks
                for (track, metadata) in processResults.new {
                    do {
                        try self.processNewTrack(track, metadata: metadata, in: db)
                    } catch {
                        Logger.error("Failed to add new track \(track.title): \(error)")
                    }
                }
                
                // Process updated tracks
                for (track, metadata) in processResults.update {
                    do {
                        try self.processUpdatedTrack(track, metadata: metadata, in: db)
                    } catch {
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
        }
    }

    // MARK: - Track Processing
    
    private func addProcessingTask(
        to group: inout ThrowingTaskGroup<(URL, TrackProcessResult), Error>,
        item: (url: URL, folderId: Int64),
        artworkMap: [URL: Data]
    ) {
        let (fileURL, folderId) = item
        
        group.addTask { [weak self] in
            guard let self = self else { return (fileURL, TrackProcessResult.skipped) }
            
            // Get artwork for this file's directory
            let directory = fileURL.deletingLastPathComponent()
            let externalArtwork = artworkMap[directory]
            
            do {
                // Check if track already exists
                if let existingTrack = try await self.dbQueue.read({ db in
                    try Track.filter(Track.Columns.path == fileURL.path).fetchOne(db)
                }) {
                    // Fetch the full track for comparison and update
                    guard let existingFullTrack = try await existingTrack.fullTrack(using: self.dbQueue) else {
                        // If we can't get full track, treat as new
                        let metadata = MetadataExtractor.extractMetadataSync(
                            from: fileURL,
                            externalArtwork: externalArtwork
                        )
                        var fullTrack = FullTrack(url: fileURL)
                        fullTrack.folderId = folderId
                        self.applyMetadataToTrack(&fullTrack, from: metadata, at: fileURL)
                        
                        return (fileURL, TrackProcessResult.new(fullTrack, metadata))
                    }
                    
                    // Check if file has been modified
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                       let modDate = attributes[.modificationDate] as? Date,
                       let storedModDate = existingFullTrack.dateModified,
                       modDate > storedModDate {
                        // File has been modified, re-extract metadata
                        let metadata = MetadataExtractor.extractMetadataSync(
                            from: fileURL,
                            externalArtwork: externalArtwork
                        )
                        
                        var updatedTrack = existingFullTrack
                        if self.updateTrackIfNeeded(&updatedTrack, with: metadata, at: fileURL) {
                            return (fileURL, TrackProcessResult.update(updatedTrack, metadata))
                        }
                    }
                    
                    // No changes needed
                    return (fileURL, TrackProcessResult.skipped)
                } else {
                    // New track
                    let metadata = MetadataExtractor.extractMetadataSync(
                        from: fileURL,
                        externalArtwork: externalArtwork
                    )
                    var fullTrack = FullTrack(url: fileURL)
                    fullTrack.folderId = folderId
                    self.applyMetadataToTrack(&fullTrack, from: metadata, at: fileURL)
                    
                    return (fileURL, TrackProcessResult.new(fullTrack, metadata))
                }
            } catch {
                Logger.error("Failed to process track \(fileURL.lastPathComponent): \(error)")
                return (fileURL, TrackProcessResult.skipped)
            }
        }
    }
    
    /// Process a new track with normalized data
    private func processNewTrack(_ track: FullTrack, metadata: TrackMetadata, in db: Database) throws {
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
    private func processUpdatedTrack(_ track: FullTrack, metadata: TrackMetadata, in db: Database) throws {
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
        
        // Update album artwork with updated external artwork
        if let artworkData = metadata.artworkData,
           !artworkData.isEmpty,
           let albumId = mutableTrack.albumId {
            try updateAlbumArtwork(albumId, artworkData: artworkData, in: db)
            Logger.info("Updated album artwork for album ID: \(albumId)")
        }
    }
    
    // MARK: - Metadata Logging
    
    private func logTrackMetadata(_ track: FullTrack) {
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
                // First, reset all duplicate flags using FullTrack
                try FullTrack.updateAll(db,
                    FullTrack.Columns.isDuplicate.set(to: false),
                    FullTrack.Columns.primaryTrackId.set(to: nil),
                    FullTrack.Columns.duplicateGroupId.set(to: nil)
                )
                
                // Get all tracks (use lightweight Track for efficiency)
                let allTracks = try Track
                    .select(Track.lightweightSelection)
                    .fetchAll(db)
                
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
                    // Fetch full tracks for quality scoring
                    let fullTracks = try tracks.compactMap { track -> FullTrack? in
                        guard let trackId = track.trackId else { return nil }
                        return try FullTrack
                            .filter(FullTrack.Columns.trackId == trackId)
                            .fetchOne(db)
                    }
                    
                    // Sort by quality score (highest first)
                    let sortedTracks = fullTracks.sorted { $0.qualityScore > $1.qualityScore }
                    
                    // The first track is the primary (highest quality)
                    guard let primaryTrack = sortedTracks.first,
                          let primaryId = primaryTrack.trackId else { continue }
                    
                    // Generate a unique group ID
                    let groupId = UUID().uuidString
                    
                    // Update all tracks in the group
                    for fullTrack in sortedTracks {
                        guard let trackId = fullTrack.trackId else { continue }
                        
                        if trackId == primaryId {
                            // This is the primary track
                            try FullTrack
                                .filter(FullTrack.Columns.trackId == trackId)
                                .updateAll(db,
                                    FullTrack.Columns.isDuplicate.set(to: false),
                                    FullTrack.Columns.primaryTrackId.set(to: nil),
                                    FullTrack.Columns.duplicateGroupId.set(to: groupId)
                                )
                        } else {
                            // This is a duplicate
                            try FullTrack
                                .filter(FullTrack.Columns.trackId == trackId)
                                .updateAll(db,
                                    FullTrack.Columns.isDuplicate.set(to: true),
                                    FullTrack.Columns.primaryTrackId.set(to: primaryId),
                                    FullTrack.Columns.duplicateGroupId.set(to: groupId)
                                )
                        }
                    }
                }
                
                // Log results
                let duplicateCount = try Track.filter(Track.Columns.isDuplicate == true).fetchCount(db)
                let groupCount = try Track
                    .select(Column("duplicate_group_id"), as: String?.self)
                    .distinct()
                    .filter(Column("duplicate_group_id") != nil)
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
