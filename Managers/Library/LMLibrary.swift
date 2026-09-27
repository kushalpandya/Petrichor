//
// LibraryManager class extension
//
// This extension contains methods for loading music files in the library,
// the methods internally also use DatabaseManager methods to work with database.
//

import Foundation

extension LibraryManager {
    func loadMusicLibrary() {
        Logger.info("Loading music library from database...")
        invalidatePendingEntityLoad()

        // Clear caches
        folderTrackCounts.removeAll()

        // Load folders and resolve their bookmarks
        let dbFolders = databaseManager.getAllFolders()
        var resolvedFolders: [Folder] = []
        var bookmarkUpdates: [(folderId: Int64, path: String, data: Data)] = []
        var relocatedFolderNames: [String] = []

        for folder in dbFolders {
            var folderAccessible = false
            var effectiveFolder = folder

            // Try to resolve bookmark if available
            if let bookmarkData = folder.bookmarkData {
                do {
                    let resolvedBookmark = try resolveBookmark(for: folder)
                    let resolvedURL = resolvedBookmark.url

                    // Start accessing the security scoped resource
                    if retainSecurityScopedAccess(to: resolvedURL, for: folder) {
                        let storedPath = folder.url.standardizedFileURL.path
                        let resolvedPath = resolvedURL.standardizedFileURL.path

                        if storedPath != resolvedPath {
                            do {
                                try validateFolderForScanning(resolvedURL, name: folder.name)
                                let refreshedBookmark = (try? resolvedURL.bookmarkData(
                                    options: [.withSecurityScope],
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil
                                )) ?? bookmarkData
                                effectiveFolder = try databaseManager.relocateFolder(
                                    folder,
                                    to: resolvedURL,
                                    bookmarkData: refreshedBookmark
                                )
                                relocatedFolderNames.append(effectiveFolder.name)
                                Logger.info("Relocated watched folder from \(storedPath) to \(resolvedPath)")
                            } catch {
                                releaseSecurityScopedAccess(for: folder)
                                resolvedFolders.append(folder)
                                Logger.error(
                                    "Failed to relocate watched folder from \(storedPath) " +
                                    "to \(resolvedPath): \(error)"
                                )
                                NotificationManager.shared.addMessage(
                                    .error,
                                    String(localized: "Could not update the location of '\(folder.name)'")
                                )
                                continue
                            }
                        } else if resolvedBookmark.isStale, let folderId = folder.id {
                            do {
                                let refreshedBookmark = try resolvedURL.bookmarkData(
                                    options: [.withSecurityScope],
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil
                                )
                                effectiveFolder.bookmarkData = refreshedBookmark
                                bookmarkUpdates.append((folderId, effectiveFolder.url.path, refreshedBookmark))
                            } catch {
                                Logger.warning("Failed to refresh stale bookmark for \(folder.name): \(error)")
                            }
                        }

                        folderAccessible = true
                        resolvedFolders.append(effectiveFolder)
                        Logger.info("Successfully resolved bookmark for \(effectiveFolder.name)")
                    } else {
                        Logger.error("Failed to start accessing security scoped resource for \(folder.name)")
                    }
                } catch {
                    Logger.error("Failed to resolve bookmark for \(folder.name): \(error)")
                }
            } else {
                Logger.error("No bookmark data for \(folder.name)")
            }

            // If bookmark resolution failed but folder exists, try to create new bookmark
            if !folderAccessible && FileManager.default.fileExists(atPath: folder.url.path) {
                Logger.info("Attempting to create new bookmark for accessible folder \(folder.name)")

                // Check if we already have permission to access this path
                if retainSecurityScopedAccess(to: folder.url, for: folder) {
                    // We have access! Create a new bookmark
                    do {
                        let newBookmarkData = try folder.url.bookmarkData(
                            options: [.withSecurityScope],
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )

                        var updatedFolder = folder
                        updatedFolder.bookmarkData = newBookmarkData
                        resolvedFolders.append(updatedFolder)
                        if let folderId = updatedFolder.id {
                            bookmarkUpdates.append((folderId, updatedFolder.url.path, newBookmarkData))
                        }

                        Logger.info("Created new bookmark for \(folder.name)")
                    } catch {
                        Logger.error("Failed to create new bookmark for \(folder.name): \(error)")
                        resolvedFolders.append(folder) // Add anyway
                    }
                } else {
                    // No access - add to list anyway
                    resolvedFolders.append(folder)
                }
            } else if !folderAccessible {
                // Folder doesn't exist or isn't accessible
                resolvedFolders.append(folder)
            }
        }

        if !relocatedFolderNames.isEmpty {
            pinnedItems = databaseManager.getPinnedItemsSync()
            AppCoordinator.shared?.playlistManager.reconcileRelocatedTracks()
            let message = relocatedFolderNames.count == 1
                ? String(localized: "Updated the location of '\(relocatedFolderNames[0])'")
                : String(localized: "Updated the locations of \(relocatedFolderNames.count) music folders")
            NotificationManager.shared.addMessage(.info, message)
        }

        folders = resolvedFolders
        releaseSecurityScopedAccess(except: Set(resolvedFolders.compactMap(\.id)))
        tracks = []
        
        loadLibraryCategories()
        updateSearchResults()
        updateTotalCounts()

        Logger.info("Loaded \(folders.count) folders and \(totalTrackCount) tracks from database")

        if !bookmarkUpdates.isEmpty {
            let pendingBookmarkUpdates = bookmarkUpdates
            Task {
                for update in pendingBookmarkUpdates {
                    do {
                        try await databaseManager.updateFolderBookmark(
                            update.folderId,
                            expectedPath: update.path,
                            bookmarkData: update.data
                        )
                    } catch {
                        Logger.error("Failed to persist refreshed bookmark for folder ID \(update.folderId): \(error)")
                    }
                }
            }
        }

        // Notify playlist manager to update smart playlists
        if let coordinator = AppCoordinator.shared {
            coordinator.playlistManager.updateSmartPlaylists()
        }

        if entitiesLoaded {
            Task { await refreshEntitiesAsync(updateCounts: false) }
        } else {
            refreshArtistNameLookup()
        }

        // Post notification that library is loaded
        NotificationCenter.default.post(name: NSNotification.Name("LibraryDidLoad"), object: nil)
    }
    
    /// Load all tracks into memory
    func loadAllTracks() async {
        if tracks.isEmpty {
            Logger.info("Loading all tracks into memory...")
            
            let loadedTracks = await Task.detached {
                self.databaseManager.getAllTracks()
            }.value
            
            await MainActor.run {
                self.tracks = loadedTracks
                self.updateSearchResults()
            }
        }
    }

    func updateArtistEntityArtwork(name: String, artworkData: Data?) {
        if let index = cachedArtistEntities.firstIndex(where: { $0.name == name }) {
            let old = cachedArtistEntities[index]
            cachedArtistEntities[index] = ArtistEntity(
                name: old.name,
                trackCount: old.trackCount,
                artworkData: artworkData
            )
        }

        updateDiscoverArtistArtwork(name: name, artworkData: artworkData)
    }

    func refreshEntities(updateCounts: Bool = true) {
        invalidatePendingEntityLoad()
        entitiesLoaded = false
        cachedArtistEntities = databaseManager.getArtistEntities()
        cachedAlbumEntities = databaseManager.getAlbumEntities()
        entitiesLoaded = true
        refreshArtistNameLookup()
        if updateCounts {
            updateTotalCounts()
        }
        Logger.info("Refreshed entities: \(cachedArtistEntities.count) artists and \(cachedAlbumEntities.count) albums")
        objectWillChange.send()
    }

    @MainActor
    func refreshEntitiesAsync(updateCounts: Bool = true) async {
        invalidatePendingEntityLoad()
        entitiesLoaded = false
        await loadEntitiesAsync()
        if updateCounts { updateTotalCounts() }
        objectWillChange.send()
    }

    /// Refresh in-memory state affected by the hide-duplicates setting (category cache,
    /// totals, the All Tracks cache), then notify views to re-fetch. The cached lists are
    /// load-once, so they must be invalidated rather than re-requested.
    func reloadForDuplicateVisibilityChange() {
        invalidatePendingEntityLoad()
        refreshLibraryCategories()
        updateTotalCounts()
        if entitiesLoaded {
            Task { await refreshEntitiesAsync(updateCounts: false) }
        }
        Task {
            let loaded = await Task.detached { self.databaseManager.getAllTracks() }.value
            await MainActor.run {
                self.tracks = loaded
                self.updateSearchResults()
                NotificationCenter.default.post(name: .libraryDataDidChange, object: nil)
            }
            // Tile counts change, but the sticky Featured selection must not reshuffle.
            await self.reresolveStickyDiscoverSections()
            await self.reloadDiscoverRecentlyPlayed()
        }
    }

    func refreshLibrary(hardRefresh: Bool = false) {
        Logger.info("Refreshing library...")
        
        actor ErrorTracker {
            private var hasErrors = false
            private var errorFolders: [String] = []
            private var successFolders: [String] = []
            
            func setError(folder: String) {
                hasErrors = true
                errorFolders.append(folder)
            }
            
            func setSuccess(folder: String) {
                successFolders.append(folder)
            }
            
            func getHasErrors() -> Bool { hasErrors }
            func getErrorFolders() -> [String] { errorFolders }
            func getSuccessFolders() -> [String] { successFolders }
        }
        
        let errorTracker = ErrorTracker()
        let group = DispatchGroup()

        Task {
            // Filter folders that need refreshing
            let refreshPlan = await determineFoldersToRefresh(hardRefresh: hardRefresh)
            let foldersToRefresh = refreshPlan.folders
            for folderName in refreshPlan.unavailableFolderNames {
                await errorTracker.setError(folder: folderName)
            }

            // Only proceed if there are folders to refresh
            if foldersToRefresh.isEmpty {
                Logger.info("No folders need refreshing")
                if !refreshPlan.unavailableFolderNames.isEmpty {
                    await MainActor.run {
                        let message = refreshPlan.unavailableFolderNames.count == 1
                            ? String(localized: "Failed to refresh folder '\(refreshPlan.unavailableFolderNames[0])'")
                            : String(localized: "Failed to refresh \(refreshPlan.unavailableFolderNames.count) folders")
                        NotificationManager.shared.addMessage(.error, message)
                    }
                }
                // Still retry missing artist info: it's independent of track changes,
                // and this is the manual-refresh resume path for the offline breaker.
                await MainActor.run { [weak self] in
                    if let self { ArtistBioManager.shared.fetchMissingArtistImages(using: self) }
                }
                return
            }

            Logger.info("Will refresh \(foldersToRefresh.count) of \(folders.count) folders")

            // Start activity before processing
            await MainActor.run {
                NotificationManager.shared.startActivity(String(localized: "Refreshing \(foldersToRefresh.count) folders..."))
            }

            let isSlowFS = foldersToRefresh.first.map { FilesystemUtils.isSlowFilesystem(url: $0.url) } ?? false
            let totalFiles: Int
            if isSlowFS {
                totalFiles = 0
            } else {
                var countedFiles = 0
                for folder in foldersToRefresh {
                    countedFiles += await databaseManager.countFilesInFolder(
                        folder,
                        supportedExtensions: AudioFormat.supportedExtensions
                    )
                }
                totalFiles = countedFiles
            }
            let globalScanState = GlobalScanState(totalFiles: totalFiles)

            await MainActor.run {
                NotificationManager.shared.updateActivityProgress(
                    current: 0,
                    total: totalFiles,
                    detail: totalFiles > 0 ? String(localized: "0 of \(totalFiles) files") : String(localized: "Preparing files...")
                )
            }

            // Process folders
            for folder in foldersToRefresh {
                group.enter()
                
                await MainActor.run { [weak self] in
                    self?.databaseManager.refreshFolder(
                        folder,
                        hardRefresh: hardRefresh,
                        manageActivityIndicator: false,
                        globalScanState: globalScanState
                    ) { result in
                        Task {
                            switch result {
                            case .success:
                                Logger.info("Successfully refreshed folder \(folder.name)")
                                await errorTracker.setSuccess(folder: folder.name)
                            case .failure(let error):
                                Logger.error("Failed to refresh folder \(folder.name): \(error)")
                                await errorTracker.setError(folder: folder.name)
                            }
                            group.leave()
                        }
                    }
                }
            }

            // Wait for all folders to complete
            await withCheckedContinuation { continuation in
                group.notify(queue: .main) {
                    continuation.resume()
                }
            }

            // Now that all folders are done, process results
            if !foldersToRefresh.isEmpty {
                Logger.info("Detecting and marking duplicate tracks")
                await databaseManager.detectAndMarkDuplicates()
            }
            
            // Reload the library
            await MainActor.run { [weak self] in
                self?.refreshLibraryCategories()
                self?.loadMusicLibrary()
                self?.updateSearchResults()
                self?.updateTotalCounts()

                // Stop activity after everything is done
                NotificationManager.shared.stopActivity()

                // Retry missing artist info now the library is current; also how the
                // breaker resumes while the app stays open (each refresh re-attempts
                // unstamped artists). No-op when nothing's missing or the feature's off.
                if let self { ArtistBioManager.shared.fetchMissingArtistImages(using: self) }
            }

            // Add notifications based on results
            let hasErrors = await errorTracker.getHasErrors()
            let errorFolders = await errorTracker.getErrorFolders()
            let refreshedFolders = await errorTracker.getSuccessFolders()
            
            await MainActor.run {
                if !refreshedFolders.isEmpty {
                    let message: String
                    if refreshedFolders.count == 1 {
                        message = String(localized: "Folder '\(refreshedFolders[0])' was refreshed for changes")
                    } else if refreshedFolders.count <= 3 {
                        message = String(localized: "Folders \(refreshedFolders.joined(separator: ", ")) were refreshed for changes")
                    } else {
                        message = String(localized: "\(refreshedFolders.count) folders were refreshed for changes")
                    }
                    NotificationManager.shared.addMessage(.info, message)
                }
                
                if !errorFolders.isEmpty {
                    let message = errorFolders.count == 1
                        ? String(localized: "Failed to refresh folder '\(errorFolders[0])'")
                        : String(localized: "Failed to refresh \(errorFolders.count) folders")
                    NotificationManager.shared.addMessage(.error, message)
                }
            }
            
            if hasErrors {
                Logger.warning("Library refresh completed with some errors")
            } else {
                Logger.info("Library refresh completed successfully")
            }
        }
    }

    private func determineFoldersToRefresh(
        hardRefresh: Bool = false
    ) async -> (folders: [Folder], unavailableFolderNames: [String]) {
        var foldersToRefresh: [Folder] = []
        var unavailableFolderNames: [String] = []
        
        Logger.info("Starting folder refresh check (hardRefresh: \(hardRefresh))")
            
        for folder in folders {
            let scanFolder: Folder
            do {
                scanFolder = try await prepareFolderForScanning(folder)
            } catch {
                Logger.warning("Folder '\(folder.name)' is unavailable, skipping refresh: \(error)")
                unavailableFolderNames.append(folder.name)
                continue
            }

            if hardRefresh {
                Logger.info("Folder \(scanFolder.name): Hard refresh requested, marking for refresh")
                foldersToRefresh.append(scanFolder)
                continue
            }

            // Step 1: Check modification timestamp
            let timestampChanged = FilesystemUtils.modificationTimestampChanged(
                for: scanFolder.url,
                comparedTo: scanFolder.dateUpdated
            )

            if timestampChanged {
                Logger.info("Folder \(scanFolder.name): Timestamp changed, marking for refresh")
                foldersToRefresh.append(scanFolder)
                continue
            }
            
            // Step 2: If timestamp hasn't changed, check content hash
            Logger.info("Folder \(scanFolder.name): Timestamp unchanged, checking content hash...")

            // If no hash stored yet, we need to scan
            guard let storedHash = scanFolder.shasumHash else {
                Logger.info("Folder \(scanFolder.name): No hash stored, marking for refresh")
                foldersToRefresh.append(scanFolder)
                continue
            }

            // Calculate current hash
            if let currentHash = await FilesystemUtils.computeFolderHash(for: scanFolder.url) {
                if currentHash != storedHash {
                    Logger.info("Folder \(scanFolder.name): Content changed (hash mismatch), marking for refresh")
                    foldersToRefresh.append(scanFolder)
                } else {
                    Logger.info("Folder \(scanFolder.name): No changes detected, skipping")
                }
            } else {
                // If hash calculation fails, scan to be safe
                Logger.warning("Folder \(scanFolder.name): Hash calculation failed, marking for refresh")
                foldersToRefresh.append(scanFolder)
            }
        }

        if hardRefresh {
            Logger.info("Hard refresh: All \(foldersToRefresh.count) accessible folders marked for refresh")
        }
        Logger.info("Refresh check complete: \(foldersToRefresh.count)/\(folders.count) folders need refresh")
        return (foldersToRefresh, unavailableFolderNames)
    }

    @MainActor
    internal func loadEntitiesAsync() async {
        while !entitiesLoaded {
            guard !Task.isCancelled else { return }
            if let entityLoadTask {
                await entityLoadTask.value
                if !entitiesLoaded, entityLoadTaskGeneration != entityLoadGeneration {
                    self.entityLoadTask = nil
                }
                continue
            }

            entityLoadGeneration += 1
            let generation = entityLoadGeneration
            let databaseManager = databaseManager
            let task = Task {
                let loaded = await Task.detached(priority: .userInitiated) {
                    (
                        databaseManager.getArtistEntities(),
                        databaseManager.getAlbumEntities(),
                        databaseManager.getArtistNamesByRole()
                    )
                }.value

                guard !Task.isCancelled, generation == self.entityLoadGeneration else { return }
                self.cachedArtistEntities = loaded.0
                self.cachedAlbumEntities = loaded.1
                self.entitiesLoaded = true
                if let namesByRole = loaded.2 {
                    ArtistParser.setLibraryArtists(namesByRole)
                }
                Logger.info("Loaded \(loaded.0.count) artists and \(loaded.1.count) albums")
            }
            entityLoadTaskGeneration = generation
            entityLoadTask = task
            await task.value
            guard !Task.isCancelled else { return }
            if generation == entityLoadGeneration {
                entityLoadTask = nil
            }
        }
    }

    internal func invalidatePendingEntityLoad() {
        entityLoadGeneration += 1
        entityLoadTask?.cancel()
    }

    /// Hand `ArtistParser` the names this library already resolved, so views parsing a raw artist
    /// tag on demand don't re-split "Hunters & Collectors" once the bundled file is unloaded.
    internal func refreshArtistNameLookup() {
        // A failed read keeps the last good lookup rather than wiping it.
        guard let namesByRole = databaseManager.getArtistNamesByRole() else { return }
        ArtistParser.setLibraryArtists(namesByRole)
    }
}
