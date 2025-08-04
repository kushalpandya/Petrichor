//
// DatabaseManager class extension
//
// This extension contains all the folder management methods which allow mapping folders in the app
// and create corresponding records in `folders` table in the db, and scanning folders for tracks.
//

import Foundation
import GRDB

extension DatabaseManager {
    func addFolders(_ urls: [URL], bookmarkDataMap: [URL: Data], completion: @escaping (Result<[Folder], Error>) -> Void) {
        Task {
            do {
                let folders = try await addFoldersAsync(urls, bookmarkDataMap: bookmarkDataMap)
                await MainActor.run {
                    completion(.success(folders))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                    Logger.error("Failed to add folders: \(error)")
                    NotificationManager.shared.addMessage(.error, "Failed to add folders")
                }
            }
        }
    }

    func addFoldersAsync(_ urls: [URL], bookmarkDataMap: [URL: Data]) async throws -> [Folder] {
        await MainActor.run {
            self.isScanning = true
            self.scanStatusMessage = "Adding folders..."
        }

        // Calculate hashes for all folders
        var mutableHashMap: [URL: String] = [:]
        for url in urls {
            if let hash = await FolderUtils.getHashAsync(for: url) {
                mutableHashMap[url] = hash
            }
        }
        let hashMap = mutableHashMap

        let addedFolders = try await dbQueue.write { db -> [Folder] in
            var folders: [Folder] = []
            
            for url in urls {
                let bookmarkData = bookmarkDataMap[url]
                var folder = Folder(url: url, bookmarkData: bookmarkData)
                
                // Get the file system modification date
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fsModDate = attributes[.modificationDate] as? Date {
                    folder.dateUpdated = fsModDate
                }
                
                // Set the calculated hash
                folder.shasumHash = hashMap[url]

                // Check if folder already exists
                if let existing = try Folder
                    .filter(Folder.Columns.path == url.path)
                    .fetchOne(db) {
                    // Update bookmark data if folder exists
                    var updatedFolder = existing
                    updatedFolder.bookmarkData = bookmarkData
                    try updatedFolder.update(db)
                    folders.append(updatedFolder)
                    Logger.info("Folder already exists: \(existing.name) with ID: \(existing.id ?? -1), updated bookmark")
                } else {
                    // Insert new folder
                    try folder.insert(db)

                    // Fetch the inserted folder to get the generated ID
                    if let insertedFolder = try Folder
                        .filter(Folder.Columns.path == url.path)
                        .fetchOne(db) {
                        folders.append(insertedFolder)
                        Logger.info("Added new folder: \(insertedFolder.name) with ID: \(insertedFolder.id ?? -1)")
                    }
                }
            }
            
            return folders
        }

        // Now scan the folders for tracks
        if !addedFolders.isEmpty {
            let existingTrackCount = try await dbQueue.read { db in
                try Track.fetchCount(db)
            }
            let isInitialScan = existingTrackCount == 0

            try await scanFoldersForTracks(addedFolders, showActivityInTray: !isInitialScan)
        }

        await MainActor.run {
            self.isScanning = false
        }
        
        // Wait for DB operations to finish before notifying scan completion
        try? await dbQueue.writeWithoutTransaction { _ in }
        await MainActor.run {
            NotificationCenter.default.post(name: .libraryDataDidChange, object: nil)
        }

        return addedFolders
    }

    func getAllFolders() -> [Folder] {
        do {
            return try dbQueue.read { db in
                try Folder
                    .order(Folder.Columns.name)
                    .fetchAll(db)
            }
        } catch {
            Logger.error("Failed to fetch folders: \(error)")
            return []
        }
    }

    func refreshFolder(_ folder: Folder, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                await MainActor.run {
                    self.isScanning = true
                    self.scanStatusMessage = "Refreshing \(folder.name)..."
                }

                // Log the current state
                let trackCountBefore = getTracksForFolder(folder.id ?? -1).count
                Logger.info("Starting refresh for folder \(folder.name) with \(trackCountBefore) tracks")

                // Scan the folder - this will check for metadata updates
                try await scanSingleFolder(folder, supportedExtensions: AudioFormat.supportedExtensions)

                // Update folder's metadata
                if let folderId = folder.id {
                    try await updateFolderMetadata(folderId)
                }

                // Log the result
                let trackCountAfter = getTracksForFolder(folder.id ?? -1).count
                Logger.info("Completed refresh for folder \(folder.name) with \(trackCountAfter) tracks (was \(trackCountBefore))")

                await MainActor.run {
                    self.isScanning = false
                    self.scanStatusMessage = ""
                    completion(.success(()))
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.scanStatusMessage = ""
                    completion(.failure(error))
                    Logger.error("Failed to refresh folder \(folder.name): \(error)")
                    NotificationManager.shared.addMessage(.error, "Failed to refresh folder \(folder.name)")
                }
            }
        }
    }

    func removeFolder(_ folder: Folder, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                _ = try await dbQueue.write { db in
                    // Delete the folder (cascades to tracks and junction tables)
                    try folder.delete(db)
                }
                
                // Now run comprehensive cleanup for any orphaned data
                try await cleanupOrphanedData()
                
                Logger.info("Removed folder '\(folder.name)' and cleaned up orphaned data")
                
                await MainActor.run {
                    completion(.success(()))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                    Logger.error("Failed to remove folder '\(folder.name)': \(error)")
                    NotificationManager.shared.addMessage(.error, "Failed to remove folder '\(folder.name)'")
                }
            }
        }
    }

    func updateFolderBookmark(_ folderId: Int64, bookmarkData: Data) async throws {
        _ = try await dbQueue.write { db in
            try Folder
                .filter(Folder.Columns.id == folderId)
                .updateAll(db, Folder.Columns.bookmarkData.set(to: bookmarkData))
        }
    }
    
    func updateFolderMetadata(_ folderId: Int64) async throws {
        // First, get the folder and calculate hash outside the database transaction
        let folderData = try await dbQueue.read { db in
            try Folder.fetchOne(db, key: folderId)
        }
        
        guard let folder = folderData else { return }
        
        let hash = await FolderUtils.getHashAsync(for: folder.url)
        
        try await dbQueue.write { db in
            guard var folder = try Folder.fetchOne(db, key: folderId) else { return }
            
            // Get and store the file system's modification date
            if let attributes = try? FileManager.default.attributesOfItem(atPath: folder.url.path),
               let fsModDate = attributes[.modificationDate] as? Date {
                folder.dateUpdated = fsModDate
            } else {
                // Fallback to current date if we can't get FS date
                folder.dateUpdated = Date()
            }
            
            // Store the calculated hash
            if let hash = hash {
                folder.shasumHash = hash
                Logger.info("Updated hash for folder \(folder.name)")
            } else {
                Logger.warning("Failed to calculate hash for folder \(folder.name)")
            }
            
            // Update track count
            let trackCount = try Track
                .filter(Track.Columns.folderId == folderId)
                .filter(Track.Columns.isDuplicate == false)
                .fetchCount(db)
            folder.trackCount = trackCount
            
            try folder.update(db)
        }
    }

    func getTracksInFolder(_ folder: Folder) -> [Track] {
        guard let folderId = folder.id else { return [] }
        return getTracksForFolder(folderId)
    }
    
    func scanFoldersForTracks(_ folders: [Folder], showActivityInTray: Bool = true) async throws {
        let supportedExtensions = AudioFormat.supportedExtensions
        var processedFolders = 0
        let totalFolders = folders.count

        if showActivityInTray && totalFolders > 0 {
            await MainActor.run {
                NotificationManager.shared.startActivity("Scanning \(totalFolders) folder\(totalFolders == 1 ? "" : "s")...")
            }
        }

        for folder in folders {
            do {
                try await scanSingleFolder(folder, supportedExtensions: supportedExtensions)
                processedFolders += 1
                
                // Update progress at 25%, 50%, 75%, 100%
                if showActivityInTray && totalFolders > 4 {
                    let progress = Double(processedFolders) / Double(totalFolders)
                    let shouldUpdate = progress >= 0.25 && processedFolders % max(1, totalFolders / 4) == 0
                    
                    if shouldUpdate {
                        let percentage = Int(progress * 100)
                        await MainActor.run {
                            NotificationManager.shared.startActivity("Scanning folders... \(percentage)%")
                        }
                    }
                }
            } catch {
                Logger.error("Failed to scan folder \(folder.name): \(error)")
                Task.detached { @MainActor in
                    NotificationManager.shared.addMessage(.error, "Failed to scan folder '\(folder.name)'")
                }
            }
            
            if processedFolders % 2 == 0 {
                await Task.yield()
            }
        }

        await MainActor.run {
            self.scanStatusMessage = "Scan complete"
            if showActivityInTray {
                NotificationManager.shared.stopActivity()
            }
        }
    }

    func scanSingleFolder(_ folder: Folder, supportedExtensions: [String]) async throws {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: folder.url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            let error = DatabaseError.scanFailed("Unable to enumerate folder contents")
            throw error
        }

        guard let folderId = folder.id else {
            let error = DatabaseError.invalidFolderId
            Logger.error("Folder has no ID")
            throw error
        }

        actor ScanState {
            var processedCount = 0
            var failedFiles: [(url: URL, error: Error)] = []
            
            func incrementProcessed(by count: Int) {
                processedCount += count
            }
            
            func addFailedFiles(_ files: [(url: URL, error: Error)]) {
                failedFiles.append(contentsOf: files)
            }
            
            func getProcessedCount() -> Int { processedCount }
            func getFailedFiles() -> [(url: URL, error: Error)] { failedFiles }
        }
        
        let scanState = ScanState()

        // Get existing tracks for this folder to check for updates
        let existingTracks = getTracksForFolder(folderId)
        _ = Dictionary(uniqueKeysWithValues: existingTracks.map { ($0.url, $0) })

        // Collect all music files first - do this synchronously before async context
        var musicFiles: [URL] = []
        var scannedPaths = Set<URL>()

        // Process enumerator synchronously
        while let fileURL = enumerator.nextObject() as? URL {
            let fileExtension = fileURL.pathExtension.lowercased()
            if supportedExtensions.contains(fileExtension) {
                musicFiles.append(fileURL)
                scannedPaths.insert(fileURL)
            }
        }

        // Now we can safely use these in async context
        let totalFiles = musicFiles.count
        let foundPaths = scannedPaths

        // Identify tracks to remove (files that no longer exist)
        let tracksToRemove = existingTracks.filter { !foundPaths.contains($0.url) }
        let trackIdsToRemove = tracksToRemove.compactMap { $0.id }
        
        // Remove tracks and clean up orphaned metadata
        if !trackIdsToRemove.isEmpty {
            let removedCount = trackIdsToRemove.count
            
            // Delete tracks
            try await dbQueue.write { db in
                for track in tracksToRemove {
                    try track.delete(db)
                    Logger.info("Removed track that no longer exists: \(track.url.lastPathComponent)")
                }
            }
            
            // Clean up orphaned metadata
            try await cleanupAfterTrackRemoval(trackIdsToRemove)
            
            // Notify about the cleanup
            await MainActor.run {
                if totalFiles == 0 {
                    NotificationManager.shared.addMessage(.info, "Folder '\(folder.name)' is now empty, removed \(removedCount) tracks")
                } else {
                    let message = removedCount == 1
                        ? "Removed 1 missing track from '\(folder.name)'"
                        : "Removed \(removedCount) missing tracks from '\(folder.name)'"
                    NotificationManager.shared.addMessage(.info, message)
                }
            }
        }

        // If no music files found and all tracks removed, we're done
        if totalFiles == 0 {
            try await updateFolderTrackCount(folder)
            return
        }
        
        // Scan for artwork files once for the entire folder
        let artworkMap = MetadataExtractor.scanFolderForArtwork(at: folder.url)
        if !artworkMap.isEmpty {
            Logger.info("Found artwork in \(artworkMap.count) directories within \(folder.name)")
        }

        // Process music files in batches
        let batchSize = totalFiles > 1000 ? 100 : 50
        let fileBatches = musicFiles.chunked(into: batchSize)

        for batch in fileBatches {
            let batchWithFolderId = batch.map { url in (url: url, folderId: folderId) }
            
            do {
                try await processBatch(batchWithFolderId, artworkMap: artworkMap)
                await scanState.incrementProcessed(by: batch.count)
                
                let currentProcessed = await scanState.getProcessedCount()
                
                // Update progress
                await MainActor.run {
                    self.scanStatusMessage = "Processing: \(currentProcessed)/\(totalFiles) files in \(folder.name)"
                }
            } catch {
                // Track failed files but continue processing
                let failures = batch.map { (url: $0, error: error) }
                await scanState.addFailedFiles(failures)
                Logger.error("Failed to process batch in folder \(folder.name): \(error)")
            }
        }

        // Update folder metadata
        if let folderId = folder.id {
            try await updateFolderMetadata(folderId)
        }

        // Get final counts
        let processedCount = await scanState.getProcessedCount()
        let failedFiles = await scanState.getFailedFiles()

        // Report results
        if !failedFiles.isEmpty {
            await MainActor.run {
                let message = failedFiles.count == 1
                    ? "Failed to process 1 file in '\(folder.name)'"
                    : "Failed to process \(failedFiles.count) files in '\(folder.name)'"
                NotificationManager.shared.addMessage(.warning, message)
            }
        }
        
        Logger.info("Completed scanning folder \(folder.name): \(processedCount) processed, \(failedFiles.count) failed")
    }

    func updateFolderTrackCount(_ folder: Folder) async throws {
        try await dbQueue.write { db in
            let count = try Track
                .filter(Track.Columns.folderId == folder.id)
                .fetchCount(db)

            var updatedFolder = folder
            updatedFolder.trackCount = count
            updatedFolder.dateUpdated = Date()
            try updatedFolder.update(db)
        }
    }
}
