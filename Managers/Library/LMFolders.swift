//
// LibraryManager class extension
//
// This extension contains methods for folder management in the library,
// the methods internally also use DatabaseManager methods to work with database.
//

import Foundation
import AppKit

private enum FolderAccessError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let name):
            return "Folder '\(name)' is unavailable or cannot be read"
        }
    }
}

extension LibraryManager {
    func addFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.prompt = String(localized: "Add Music Folder")
        openPanel.message = String(localized: "Select folders containing your music files")

        guard let keyWindow = NSApp.keyWindow else {
            Logger.error("Cannot add folder: no key window available")
            return
        }

        openPanel.beginSheetModal(for: keyWindow) { [weak self] response in
            guard let self = self, response == .OK else { return }

            var urlsToAdd: [URL] = []
            var bookmarkDataMap: [URL: Data] = [:]

            for url in openPanel.urls {
                // Create security bookmark
                do {
                    let bookmarkData = try url.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    urlsToAdd.append(url)
                    bookmarkDataMap[url] = bookmarkData
                    Logger.info("Created bookmark for folder - \(url.lastPathComponent) at \(url.path)")
                } catch {
                    Logger.error("Failed to create security bookmark for \(url.path): \(error)")
                }
            }

            // Add folders to database with their bookmarks
            if !urlsToAdd.isEmpty {
                self.databaseManager.addFolders(urlsToAdd, bookmarkDataMap: bookmarkDataMap) { result in
                    switch result {
                    case .success(let dbFolders):
                        Logger.info("Successfully added \(dbFolders.count) folders to database")
                        self.scheduleLibraryReload()
                    case .failure(let error):
                        Logger.error("Failed to add folders to database: \(error)")
                    }
                }
            }
        }
    }

    func removeFolder(_ folder: Folder) {
        Logger.info("Removing folder: \(folder.name)")
        
        databaseManager.removeFolder(folder) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                Logger.info("Successfully removed folder: \(folder.name)")
                self.releaseSecurityScopedAccess(for: folder)
                // Remove from local array
                self.folders.removeAll { $0.id == folder.id }
                // Reload library immediately
                self.refreshLibraryCategories()
                self.loadMusicLibrary()
                // Stop the activity indicator
                NotificationManager.shared.stopActivity()
                
            case .failure(let error):
                Logger.error("Failed to remove folder: \(error)")
                // Stop the activity indicator on failure too
                NotificationManager.shared.stopActivity()
                // Show error message
                NotificationManager.shared.addMessage(.error, String(localized: "Failed to remove folder '\(folder.name)'"))
            }
        }
    }

    func refreshFolder(_ folder: Folder, hardRefresh: Bool = false) {
        Task { [weak self] in
            guard let self = self else { return }

            let scanFolder: Folder
            do {
                scanFolder = try await self.prepareFolderForScanning(folder)
            } catch {
                Logger.error("Cannot refresh folder \(folder.name): \(error)")
                await MainActor.run {
                    NotificationManager.shared.addMessage(
                        .error,
                        String(localized: "Folder '\(folder.name)' is currently unavailable")
                    )
                }
                return
            }

            // Show the indicator before counting: enumerating a large folder can take
            // a moment, and refreshLibrary() starts activity before counting too.
            await MainActor.run {
                NotificationManager.shared.startActivity(String(localized: "Refreshing \(scanFolder.name)..."))
            }

            // Pre-count files so the progress bar can advance (needs a
            // GlobalScanState); skip on slow filesystems, like refreshLibrary().
            let isSlowFS = FilesystemUtils.isSlowFilesystem(url: scanFolder.url)
            let totalFiles = isSlowFS
                ? 0
                : await self.databaseManager.countFilesInFolder(
                    scanFolder,
                    supportedExtensions: AudioFormat.supportedExtensions
                )
            let globalScanState = GlobalScanState(totalFiles: totalFiles)

            // startActivity() above cleared progress; set the initial total now that
            // we know it (the first update always passes the throttle after a start).
            await MainActor.run {
                NotificationManager.shared.updateActivityProgress(
                    current: 0,
                    total: totalFiles,
                    detail: totalFiles > 0 ? String(localized: "0 of \(totalFiles) files") : String(localized: "Preparing files...")
                )
            }

            // completion runs on the main actor (see DMFolders.refreshFolder)
            self.databaseManager.refreshFolder(
                scanFolder,
                hardRefresh: hardRefresh,
                manageActivityIndicator: false,
                globalScanState: globalScanState
            ) { result in
                NotificationManager.shared.stopActivity()
                switch result {
                case .success:
                    Logger.info("Successfully refreshed folder \(scanFolder.name)")
                    // Reload the library to reflect changes
                    self.refreshLibraryCategories()
                    self.loadMusicLibrary()
                case .failure(let error):
                    Logger.error("Failed to refresh folder \(scanFolder.name): \(error)")
                }
            }
        }
    }

    func optimizeDatabase() {
        let sizeBefore = databaseManager.getDatabaseSize() ?? 0
        performDatabaseOptimization(sizeBefore: sizeBefore, context: "optimization")
    }

    internal func resolveBookmark(for folder: Folder) throws -> (url: URL, isStale: Bool) {
        guard let bookmarkData = folder.bookmarkData else { throw CocoaError(.fileReadNoPermission) }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url.standardizedFileURL, isStale)
    }

    internal func retainSecurityScopedAccess(
        to url: URL,
        for folder: Folder,
        restartExisting: Bool = false
    ) -> Bool {
        guard let folderId = folder.id else { return false }
        let standardizedURL = url.standardizedFileURL
        securityScopedFolderURLsLock.lock()
        defer { securityScopedFolderURLsLock.unlock() }
        if !restartExisting, securityScopedFolderURLs[folderId]?.path == standardizedURL.path { return true }
        guard standardizedURL.startAccessingSecurityScopedResource() else { return false }
        let previousURL = securityScopedFolderURLs.updateValue(standardizedURL, forKey: folderId)
        previousURL?.stopAccessingSecurityScopedResource()
        return true
    }

    internal func prepareFolderForScanning(_ folder: Folder) async throws -> Folder {
        var effectiveFolder = folder

        if let bookmarkData = folder.bookmarkData {
            let resolvedBookmark = try resolveBookmark(for: folder)
            let resolvedURL = resolvedBookmark.url
            guard retainSecurityScopedAccess(to: resolvedURL, for: folder, restartExisting: true) else {
                throw FolderAccessError.unavailable(folder.name)
            }
            try validateFolderForScanning(resolvedURL, name: folder.name)

            let refreshedBookmark: Data
            if resolvedBookmark.isStale || resolvedURL.path != folder.url.standardizedFileURL.path {
                refreshedBookmark = try resolvedURL.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } else {
                refreshedBookmark = bookmarkData
            }

            if resolvedURL.path != folder.url.standardizedFileURL.path {
                effectiveFolder = try databaseManager.relocateFolder(
                    folder,
                    to: resolvedURL,
                    bookmarkData: refreshedBookmark
                )
                let relocatedFolder = effectiveFolder
                let refreshedPinnedItems = (try? await databaseManager.getPinnedItems()) ?? []
                await MainActor.run {
                    if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                        folders[index] = relocatedFolder
                    }
                    pinnedItems = refreshedPinnedItems
                    AppCoordinator.shared?.playlistManager.reconcileRelocatedTracks()
                    NotificationManager.shared.addMessage(
                        .info,
                        String(localized: "Updated the location of '\(relocatedFolder.name)'")
                    )
                }
            } else if resolvedBookmark.isStale, let folderId = folder.id {
                try await databaseManager.updateFolderBookmark(
                    folderId,
                    expectedPath: folder.url.path,
                    bookmarkData: refreshedBookmark
                )
                effectiveFolder.bookmarkData = refreshedBookmark
                let refreshedFolder = effectiveFolder
                await MainActor.run {
                    if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                        folders[index] = refreshedFolder
                    }
                }
            }
        }

        try validateFolderForScanning(effectiveFolder.url, name: effectiveFolder.name)
        return effectiveFolder
    }

    internal func validateFolderForScanning(_ url: URL, name: String) throws {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        } catch {
            throw FolderAccessError.unavailable(name)
        }
        guard values.isDirectory == true, values.isReadable == true else {
            throw FolderAccessError.unavailable(name)
        }
    }

    internal func releaseSecurityScopedAccess(for folder: Folder) {
        guard let folderId = folder.id else { return }
        securityScopedFolderURLsLock.lock()
        let url = securityScopedFolderURLs.removeValue(forKey: folderId)
        securityScopedFolderURLsLock.unlock()
        guard let url else { return }
        url.stopAccessingSecurityScopedResource()
    }

    internal func releaseSecurityScopedFolderAccess() {
        securityScopedFolderURLsLock.lock()
        let urls = Array(securityScopedFolderURLs.values)
        securityScopedFolderURLs.removeAll()
        securityScopedFolderURLsLock.unlock()
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }

    internal func releaseSecurityScopedAccess(except folderIDs: Set<Int64>) {
        securityScopedFolderURLsLock.lock()
        let removedURLs = securityScopedFolderURLs.compactMap { folderId, url in
            folderIDs.contains(folderId) ? nil : url
        }
        securityScopedFolderURLs = securityScopedFolderURLs.filter { folderIDs.contains($0.key) }
        securityScopedFolderURLsLock.unlock()
        for url in removedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    // MARK: - Private Helpers
    
    private func performDatabaseOptimization(sizeBefore: Int64, context: String) {
        Task {
            do {
                try await databaseManager.cleanupOrphanedData()
                try await databaseManager.vacuumDatabase()
                try await databaseManager.analyzeDatabase()
                
                // Get database size after optimization and calculate savings
                let sizeAfter = databaseManager.getDatabaseSize() ?? 0
                let spaceSaved = max(0, sizeBefore - sizeAfter)
                
                Logger.info("Database \(context) completed")
                
                await MainActor.run {
                    Task { await refreshEntitiesAsync() }
                    updateTotalCounts()
                    
                    if spaceSaved > 0 {
                        let savedMB = Double(spaceSaved) / (1024.0 * 1024.0)
                        NotificationManager.shared.addMessage(
                            .info,
                            String(localized: "Database optimization completed - reclaimed \(String(format: "%.1f", savedMB)) MB")
                        )
                    } else {
                        NotificationManager.shared.addMessage(.info, String(localized: "Database optimization completed"))
                    }
                }
            } catch {
                Logger.error("Database \(context) failed: \(error)")
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, String(localized: "Database optimization failed"))
                }
            }
        }
    }
}
