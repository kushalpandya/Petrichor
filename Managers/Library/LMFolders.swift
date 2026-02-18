//
// LibraryManager class extension
//
// This extension contains methods for folder management in the library,
// the methods internally also use DatabaseManager methods to work with database.
//

import Foundation
import AppKit

extension LibraryManager {
    func addFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.prompt = "Add Music Folder"
        openPanel.message = "Select folders containing your music files"

        openPanel.beginSheetModal(for: NSApp.keyWindow!) { [weak self] response in
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
                        self.refreshLibraryCategories()
                        self.loadMusicLibrary()
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
                NotificationManager.shared.addMessage(.error, "Failed to remove folder '\(folder.name)'")
            }
        }
    }

    func refreshFolder(_ folder: Folder, hardRefresh: Bool = false) {
        // First, ensure we have a valid bookmark
        Task {
            // Refresh bookmark if needed
            if folder.bookmarkData == nil || !folder.url.startAccessingSecurityScopedResource() {
                await refreshBookmarkForFolder(folder)
            }

            // Then proceed with scanning
            await MainActor.run { [weak self] in
                guard let self = self else { return }

                // Delegate to database manager for refresh
                self.databaseManager.refreshFolder(folder, hardRefresh: hardRefresh) { result in
                    switch result {
                    case .success:
                        Logger.info("Successfully refreshed folder \(folder.name)")
                        // Reload the library to reflect changes
                        self.refreshLibraryCategories()
                        self.loadMusicLibrary()
                    case .failure(let error):
                        Logger.error("Failed to refresh folder \(folder.name): \(error)")
                    }
                }
            }
        }
    }

    func optimizeDatabase(notifyUser: Bool = false) {
        let sizeBefore = databaseManager.getDatabaseSize() ?? 0
        var foldersToRemove: [Folder] = []
            
        for folder in folders {
            if !fileManager.fileExists(atPath: folder.url.path) {
                foldersToRemove.append(folder)
            }
        }
        
        if foldersToRemove.isEmpty {
            Logger.info("No missing folders found during optimization")
            
            if notifyUser {
                performDatabaseOptimization(sizeBefore: sizeBefore, context: "optimization")
            }
            return
        }
        
        Logger.info("Found \(foldersToRemove.count) missing folders to optimize")
        NotificationManager.shared.startActivity("Optimizing database...")
        
        let group = DispatchGroup()
        var removedFolders: [String] = []
        var failedRemovals: [String] = []
        
        for folder in foldersToRemove {
            group.enter()
            databaseManager.removeFolder(folder) { result in
                switch result {
                case .success:
                    Logger.info("Successfully removed missing folder: \(folder.name)")
                    removedFolders.append(folder.name)
                case .failure(let error):
                    Logger.error("Failed to remove missing folder \(folder.name): \(error)")
                    failedRemovals.append(folder.name)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            NotificationManager.shared.stopActivity()
            
            if !removedFolders.isEmpty {
                let message = removedFolders.count == 1
                    ? "Folder '\(removedFolders[0])' was removed as it no longer exists"
                    : "\(removedFolders.count) folders were removed as they no longer exist"
                NotificationManager.shared.addMessage(.info, message)
            }
            
            if !failedRemovals.isEmpty {
                let message = "Failed to remove \(failedRemovals.count) missing folder\(failedRemovals.count == 1 ? "" : "s")"
                NotificationManager.shared.addMessage(.error, message)
            }
            
            self.performDatabaseOptimization(sizeBefore: sizeBefore, context: "optimization after folder cleanup")
            self.refreshLibraryCategories()
            self.loadMusicLibrary()
        }
    }

    func refreshBookmarkForFolder(_ folder: Folder) async {
        // Only refresh if we can access the folder
        guard FileManager.default.fileExists(atPath: folder.url.path) else {
            Logger.warning("Folder no longer exists at \(folder.url.path)")
            return
        }

        do {
            // Create a fresh bookmark
            let newBookmarkData = try folder.url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            // Update the folder with new bookmark
            var updatedFolder = folder
            updatedFolder.bookmarkData = newBookmarkData

            // Save to database
            try await databaseManager.updateFolderBookmark(folder.id!, bookmarkData: newBookmarkData)

            Logger.info("Successfully refreshed bookmark for \(folder.name)")
        } catch {
            Logger.error("Failed to refresh bookmark for \(folder.name): \(error)")
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
                    refreshEntities()
                    updateTotalCounts()
                    
                    if spaceSaved > 0 {
                        let savedMB = Double(spaceSaved) / (1024.0 * 1024.0)
                        NotificationManager.shared.addMessage(
                            .info,
                            "Database optimization completed - reclaimed \(String(format: "%.1f", savedMB)) MB"
                        )
                    } else {
                        NotificationManager.shared.addMessage(.info, "Database optimization completed")
                    }
                }
            } catch {
                Logger.error("Database \(context) failed: \(error)")
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Database optimization failed")
                }
            }
        }
    }
}
