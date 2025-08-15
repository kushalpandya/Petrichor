//
// LibraryManager class
//
// This class handles all the Library operations done by the app, note that this file only
// contains core methods, the domain-specific logic is spread across extension files within this
// directory where each file is prefixed with `LM`.
//

import Foundation
import AppKit

extension Notification.Name {
    static let libraryDataDidChange = Notification.Name("LibraryDataDidChange")
}

class LibraryManager: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var folders: [Folder] = []
    @Published var isScanning: Bool = false
    @Published var scanStatusMessage: String = ""
    @Published var globalSearchText: String = "" {
        didSet {
            updateSearchResults()
        }
    }
    @Published var searchResults: [Track] = []
    @Published var discoverTracks: [Track] = []
    @Published var isLoadingDiscover: Bool = false
    @Published var pinnedItems: [PinnedItem] = []
    @Published internal var cachedArtistEntities: [ArtistEntity] = []
    @Published internal var cachedAlbumEntities: [AlbumEntity] = []
    @Published private(set) var totalTrackCount: Int = 0
    @Published private(set) var artistCount: Int = 0
    @Published private(set) var albumCount: Int = 0

    // MARK: - Entity Properties
    var artistEntities: [ArtistEntity] {
        if !entitiesLoaded {
            loadEntities()
        }
        return cachedArtistEntities
    }

    var albumEntities: [AlbumEntity] {
        if !entitiesLoaded {
            loadEntities()
        }
        return cachedAlbumEntities
    }

    // MARK: - Private/Internal Properties
    private var fileWatcherTimer: Timer?
    private var hasPerformedInitialScan = false
    internal var cachedLibraryCategories: [LibraryFilterType: [LibraryFilterItem]] = [:]
    internal var libraryCategoriesLoaded = false
    internal var entitiesLoaded = false
    internal let userDefaults = UserDefaults.standard
    internal let fileManager = FileManager.default
    internal var folderTrackCounts: [Int64: Int] = [:]

    // Database manager
    let databaseManager: DatabaseManager

    // Keys for UserDefaults
    internal enum UserDefaultsKeys {
        static let lastScanDate = "LastScanDate"
        static let securityBookmarks = "SecurityBookmarks"
        static let autoScanInterval = "autoScanInterval"
    }

    private var autoScanInterval: AutoScanInterval {
        let rawValue = userDefaults.string(forKey: UserDefaultsKeys.autoScanInterval) ?? AutoScanInterval.every60Minutes.rawValue
        return AutoScanInterval(rawValue: rawValue) ?? .every60Minutes
    }

    // MARK: - Initialization
    init() {
        do {
            // Initialize database manager
            databaseManager = try DatabaseManager()
        } catch {
            Logger.critical("Failed to initialize database: \(error)")
            fatalError("Failed to initialize database: \(error)")
        }

        // Observe database manager scanning state
        databaseManager.$isScanning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isScanning)

        databaseManager.$scanStatusMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$scanStatusMessage)

        loadMusicLibrary()
        
        pinnedItems = databaseManager.getPinnedItemsSync()
        
        Task {
            try? await Task.sleep(nanoseconds: TimeConstants.fiftyMilliseconds)
            cleanupMissingFolders()
            
            await MainActor.run {
                startFileWatcher()
            }
        }

        // Observe auto-scan interval changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(autoScanIntervalDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    deinit {
        fileWatcherTimer?.invalidate()
        // Stop accessing all security scoped resources
        for folder in folders {
            if folder.bookmarkData != nil {
                folder.url.stopAccessingSecurityScopedResource()
            }
        }
    }
    
    internal func updateTotalCounts() {
        totalTrackCount = databaseManager.getTotalTrackCount()
        artistCount = databaseManager.getArtistCount()
        albumCount = databaseManager.getAlbumCount()
        NotificationCenter.default.post(name: .libraryDataDidChange, object: nil)
    }
    
    // MARK: - Library Categories Cache Management

    /// Load library categories into cache
    func loadLibraryCategories() {
        guard !libraryCategoriesLoaded else { return }
        
        Logger.info("Loading library categories")
        let startTime = Date()
        
        Task.detached(priority: .userInitiated) {
            let categories = LibraryFilterType.allCases
            let results = await withTaskGroup(
                of: (LibraryFilterType, [LibraryFilterItem]).self,
                returning: [LibraryFilterType: [LibraryFilterItem]].self
            ) { group in
                for category in categories {
                    group.addTask { [weak self] in
                        guard let self = self else { return (category, []) }
                        
                        let items = self.getLibraryFilterItemsFromDatabase(for: category)
                        return (category, items)
                    }
                }
                
                var collectedResults: [LibraryFilterType: [LibraryFilterItem]] = [:]
                for await (category, items) in group {
                    collectedResults[category] = items
                }
                return collectedResults
            }
            
            await MainActor.run {
                for (category, items) in results {
                    self.cachedLibraryCategories[category] = items
                }
                self.libraryCategoriesLoaded = true
                
                let elapsed = Date().timeIntervalSince(startTime)
                Logger.info("Loaded library categories in \(String(format: "%.2f", elapsed))s: \(self.cachedLibraryCategories.values.map { $0.count }) items total")
            }
        }
    }

    /// Refresh library categories cache
    func refreshLibraryCategories() {
        Logger.info("Refreshing library categories cache")
        
        // Clear existing cache
        cachedLibraryCategories.removeAll()
        libraryCategoriesLoaded = false
        
        // Reload categories
        loadLibraryCategories()
        
        // Notify UI of changes
        objectWillChange.send()
    }

    /// Helper method to fetch items from database
    internal func getLibraryFilterItemsFromDatabase(for filterType: LibraryFilterType) -> [LibraryFilterItem] {
        switch filterType {
        case .artists:
            return databaseManager.getArtistFilterItems()
        case .albumArtists:
            return databaseManager.getAlbumArtistFilterItems()
        case .composers:
            return databaseManager.getComposerFilterItems()
        case .albums:
            return databaseManager.getAlbumFilterItems()
        case .genres:
            return databaseManager.getGenreFilterItems()
        case .decades:
            return databaseManager.getDecadeFilterItems()
        case .years:
            return databaseManager.getYearFilterItems()
        }
    }

    // MARK: - File Watching

    private func startFileWatcher() {
        // Cancel any existing timer
        fileWatcherTimer?.invalidate()
        fileWatcherTimer = nil

        // Get current auto-scan interval
        let currentInterval = autoScanInterval

        // Handle "only on launch" setting
        if currentInterval == .onlyOnLaunch {
            Logger.info("Auto-scan set to only on launch, performing initial scan...")
            
            // Skip if we already performed initial scan (within this app session)
            guard !hasPerformedInitialScan else {
                Logger.info("Initial scan already performed in this session, skipping")
                return
            }
            
            hasPerformedInitialScan = true
            
            // Always perform scan on launch when set to "onlyOnLaunch"
            // Perform scan after a short delay to let the UI initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                
                // Only refresh if we're not already scanning
                if !self.isScanning && !NotificationManager.shared.isActivityInProgress {
                    Logger.info("Starting auto-scan on launch")
                    self.refreshLibrary()
                }
            }
            return
        }
        
        if currentInterval == .manually {
            Logger.info("Auto-scan set to manual, no automatic scanning will occur")
            return
        }

        // Only start a timer if auto-scan has a time interval
        guard let interval = currentInterval.timeInterval else {
            Logger.info("No auto-scan timer needed")
            return
        }

        Logger.info("LibraryManager: Starting auto-scan timer with interval: \(interval) seconds (\(currentInterval.displayName))")

        fileWatcherTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // Only refresh if we're not currently scanning
            if !self.isScanning && !NotificationManager.shared.isActivityInProgress {
                Logger.info("Starting periodic refresh...")
                self.refreshLibrary()
            }
        }
    }

    private func handleAutoScanIntervalChange() {
        Logger.info("Auto-scan interval changed to: \(autoScanInterval.displayName)")
        // Restart the file watcher with new interval
        startFileWatcher()
    }

    // MARK: - Database Management

    func resetAllData() async throws {
        // Use the existing resetDatabase method
        try databaseManager.resetDatabase()

        // Ensure UI updates happen on main thread
        await MainActor.run {
            // Clear in-memory data
            folders.removeAll()
            tracks.removeAll()

            // Clear UserDefaults (remove the security bookmarks reference)
            UserDefaults.standard.removeObject(forKey: "LastScanDate")
        }
    }

    @objc
    private func autoScanIntervalDidChange(_ notification: Notification) {
        let newInterval = autoScanInterval

        struct LastInterval {
            static var value: AutoScanInterval?
            static var initialized = false
        }

        if !LastInterval.initialized {
            LastInterval.value = newInterval
            LastInterval.initialized = true
            return
        }

        // Only proceed if the interval actually changed
        guard LastInterval.value != newInterval else { return }
        LastInterval.value = newInterval

        // Check if the auto-scan interval specifically changed
        DispatchQueue.main.async { [weak self] in
            self?.handleAutoScanIntervalChange()
        }
    }
}
