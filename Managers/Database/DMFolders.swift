//
// DatabaseManager class extension
//
// This extension contains all the folder management methods which allow mapping folders in the app
// and create corresponding records in `folders` table in the db, and scanning folders for tracks.
//

import Foundation
import GRDB

actor ScanState {
    var processedCount = 0
    var failedFiles: [(url: URL, error: Error)] = []
    var skippedFiles: [(url: URL, extension: String)] = []
    
    func incrementProcessed(by count: Int) {
        processedCount += count
    }
    
    func addFailedFiles(_ files: [(url: URL, error: Error)]) {
        failedFiles.append(contentsOf: files)
    }
    
    func addSkippedFiles(_ files: [(url: URL, extension: String)]) {
        skippedFiles.append(contentsOf: files)
    }
    
    func getProcessedCount() -> Int { processedCount }
    func getFailedFiles() -> [(url: URL, error: Error)] { failedFiles }
    func getSkippedFiles() -> [(url: URL, extension: String)] { skippedFiles }
}

actor GlobalScanState {
    let totalFiles: Int
    var processedFiles = 0
    
    init(totalFiles: Int) {
        self.totalFiles = totalFiles
    }
    
    func incrementProcessed(by count: Int) {
        processedFiles += count
    }
    
    func getProgress() -> (processed: Int, total: Int) {
        (processedFiles, totalFiles)
    }
}

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
            if let hash = await FilesystemUtils.getHashAsync(for: url) {
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
            self.scanStatusMessage = ""
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
                    NotificationManager.shared.startActivity("Refreshing \(folder.name)...")
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
                    NotificationManager.shared.stopActivity()
                    completion(.success(()))
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.scanStatusMessage = ""
                    NotificationManager.shared.stopActivity()
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
        
        let hash = await FilesystemUtils.getHashAsync(for: folder.url)
        
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
        let totalFolders = folders.count

        if showActivityInTray && totalFolders > 0 {
            await MainActor.run {
                NotificationManager.shared.startActivity("Scanning \(totalFolders) folder\(totalFolders == 1 ? "" : "s")...")
            }
        }

        // Calculate total files across all folders
        var totalFilesAcrossAllFolders = 0
        
        if totalFolders > 1 {
            for folder in folders {
                guard let enumerator = FileManager.default.enumerator(
                    at: folder.url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                
                var fileCount = 0
                while let fileURL = enumerator.nextObject() as? URL {
                    let ext = fileURL.pathExtension.lowercased()
                    if !ext.isEmpty && supportedExtensions.contains(ext) {
                        fileCount += 1
                    }
                }
                
                totalFilesAcrossAllFolders += fileCount
            }
        }
        
        // Create global scan state if scanning multiple folders
        let globalScanState = totalFolders > 1 ? GlobalScanState(totalFiles: totalFilesAcrossAllFolders) : nil
        
        var processedFolders = 0

        for folder in folders {
            do {
                try await scanSingleFolder(
                    folder,
                    supportedExtensions: supportedExtensions,
                    globalScanState: globalScanState
                )
                processedFolders += 1
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

    func scanSingleFolder(
        _ folder: Folder,
        supportedExtensions: [String],
        globalScanState: GlobalScanState? = nil
    ) async throws {
        guard let folderId = folder.id else {
            Logger.error("Folder has no ID")
            throw DatabaseError.invalidFolderId
        }
        
        let scanState = ScanState()
        
        // Collect all music files and identify unsupported files
        let (musicFiles, unsupportedFiles) = try collectMusicFiles(
            from: folder.url,
            supportedExtensions: supportedExtensions
        )
        
        await scanState.addSkippedFiles(unsupportedFiles)
        
        // Remove tracks that no longer exist
        try await removeDeletedTracks(
            folderId: folderId,
            foundPaths: Set(musicFiles),
            folderName: folder.name,
            hasRemainingFiles: !musicFiles.isEmpty
        )
        
        // If no music files found, we're done
        if musicFiles.isEmpty {
            try await updateFolderTrackCount(folder)
            return
        }
        
        // Scan for artwork
        let artworkMap = MetadataExtractor.scanFolderForArtwork(at: folder.url)
        if !artworkMap.isEmpty {
            Logger.info("Found artwork in \(artworkMap.count) directories within \(folder.name)")
        }
        
        // Process music files in batches
        try await processMusicFilesInBatches(
            musicFiles: musicFiles,
            folderId: folderId,
            artworkMap: artworkMap,
            folderName: folder.name,
            scanState: scanState,
            globalScanState: globalScanState
        )
        
        // Update metadata and report results
        try await finalizeScan(
            folderId: folderId,
            folder: folder,
            scanState: scanState
        )
    }
    // MARK: - Private Helpers

    /// Collect all music files from a folder and identify unsupported files
    private func collectMusicFiles(
        from folderURL: URL,
        supportedExtensions: [String]
    ) throws -> (musicFiles: [URL], unsupportedFiles: [(url: URL, extension: String)]) {
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw DatabaseError.scanFailed("Unable to enumerate folder contents")
        }
        
        var musicFiles: [URL] = []
        var unsupportedFiles: [(url: URL, extension: String)] = []
        
        while let fileURL = enumerator.nextObject() as? URL {
            let fileExtension = fileURL.pathExtension.lowercased()
            
            guard !fileExtension.isEmpty else { continue }
            
            if supportedExtensions.contains(fileExtension) {
                musicFiles.append(fileURL)
            } else if AudioFormat.isNotSupported(fileExtension) {
                unsupportedFiles.append((url: fileURL, extension: fileExtension))
                Logger.info("Skipped unsupported audio file: \(fileURL.lastPathComponent) (.\(fileExtension))")
            }
        }
        
        return (musicFiles, unsupportedFiles)
    }

    /// Remove tracks from database that no longer exist in the filesystem
    private func removeDeletedTracks(
        folderId: Int64,
        foundPaths: Set<URL>,
        folderName: String,
        hasRemainingFiles: Bool
    ) async throws {
        let existingTracks = getTracksForFolder(folderId)
        let foundPathStrings = Set(foundPaths.map { $0.path })
        let tracksToRemove = existingTracks.filter { !foundPathStrings.contains($0.url.path) }
        let trackIdsToRemove = tracksToRemove.compactMap { $0.id }
        
        guard !trackIdsToRemove.isEmpty else { return }
        
        let removedCount = trackIdsToRemove.count
        
        // Remove tracks from database
        try await dbQueue.write { db in
            for track in tracksToRemove {
                try track.delete(db)
                Logger.info("Removed track that no longer exists: \(track.url.lastPathComponent)")
            }
        }
        
        // Clean up orphaned metadata
        try await cleanupAfterTrackRemoval(trackIdsToRemove)
        
        // Report results to user
        await MainActor.run {
            if !hasRemainingFiles {
                NotificationManager.shared.addMessage(.info, "Folder '\(folderName)' is now empty, removed \(removedCount) tracks")
            } else {
                let message = removedCount == 1
                    ? "Removed 1 missing track from '\(folderName)'"
                    : "Removed \(removedCount) missing tracks from '\(folderName)'"
                NotificationManager.shared.addMessage(.info, message)
            }
        }
    }

    private func processMusicFilesInBatches(
        musicFiles: [URL],
        folderId: Int64,
        artworkMap: [URL: Data],
        folderName: String,
        scanState: ScanState,
        globalScanState: GlobalScanState? = nil
    ) async throws {
        let totalFiles = musicFiles.count
        let batchSize = 500
        let fileBatches = musicFiles.chunked(into: batchSize)
        
        for batch in fileBatches {
            let batchWithFolderId = batch.map { url in (url: url, folderId: folderId) }
            
            do {
                try await processBatch(
                    batchWithFolderId,
                    artworkMap: artworkMap,
                    scanState: scanState,
                    folderName: folderName,
                    totalFilesInFolder: totalFiles,
                    globalScanState: globalScanState
                )
            } catch {
                let failures = batch.map { (url: $0, error: error) }
                await scanState.addFailedFiles(failures)
                Logger.error("Failed to process batch in folder \(folderName): \(error)")
            }
        }
    }

    /// Finalize the scan - update metadata, detect duplicates, and report results
    private func finalizeScan(
        folderId: Int64,
        folder: Folder,
        scanState: ScanState
    ) async throws {
        // Update folder metadata
        try await updateFolderMetadata(folderId)
        
        // Detect and avoid duplicates
        await detectAndMarkDuplicates()
        
        // Get final counts
        let processedCount = await scanState.getProcessedCount()
        let failedFiles = await scanState.getFailedFiles()
        let skippedFiles = await scanState.getSkippedFiles()
        
        // Report failed files
        if !failedFiles.isEmpty {
            await MainActor.run {
                let message = failedFiles.count == 1
                    ? "Failed to process 1 file in '\(folder.name)'"
                    : "Failed to process \(failedFiles.count) files in '\(folder.name)'"
                NotificationManager.shared.addMessage(.warning, message)
            }
        }
        
        // Report skipped files
        if !skippedFiles.isEmpty {
            let extensionCounts = Dictionary(grouping: skippedFiles) { $0.extension }
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
            
            let topExtensions = extensionCounts.prefix(3)
                .map { ".\($0.key.uppercased()) (\($0.value))" }
                .joined(separator: ", ")
            
            await MainActor.run {
                let message = skippedFiles.count == 1
                    ? "1 file skipped in '\(folder.name)' - unsupported format"
                    : "\(skippedFiles.count) files skipped in '\(folder.name)' - unsupported formats: \(topExtensions)"
                NotificationManager.shared.addMessage(.warning, message)
            }
        }
        
        Logger.info("Completed scanning folder \(folder.name): \(processedCount) processed, \(failedFiles.count) failed, \(skippedFiles.count) skipped")
    }
}
