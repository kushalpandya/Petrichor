//
// LibraryManager class
//
// This class handles all the Library operations done by the app, note that this file only
// contains core methods, the domain-specific logic is spread across extension files within this
// directory where each file is prefixed with `LM`.
//

import Foundation
import AppKit

class LibraryManager: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var folders: [Folder] = []
    @Published var isScanning: Bool = false
    @Published var isInitialOnboardingScan: Bool = false
    @Published var hasReachedInitialScanThreshold: Bool = false
    @Published var scanStatusMessage: String = ""
    @Published var globalSearchText: String = "" {
        didSet {
            updateSearchResults()
        }
    }
    @Published var searchResults: [Track] = []
    @Published var discoverTracks: [Track] = []
    // Discover carousels. @Published can't live in an extension; the logic is in LMDiscover.
    @Published var featuredSection: DiscoverSection = .loading
    @Published var recentlyPlayedSection: DiscoverSection = .loading
    @Published var mostLovedSection: DiscoverSection = .loading
    @Published var isDiscoverRecentlyPlayedUnlocked = false
    @Published var isDiscoverMostLovedUnlocked = false
    /// Starts true: Discover is the default sidebar selection, so it loads from the moment
    /// the window appears, and the track list would otherwise flash its empty state.
    @Published var isLoadingDiscoverTracks: Bool = true
    @Published var pinnedItems: [PinnedItem] = []
    @Published var pendingMergeRequest: MergeRequest?
    @Published internal var cachedArtistEntities: [ArtistEntity] = []
    @Published internal var cachedAlbumEntities: [AlbumEntity] = []
    @Published internal var entitiesLoaded = false
    @Published private(set) var totalTrackCount: Int = 0
    @Published private(set) var artistCount: Int = 0
    @Published private(set) var albumCount: Int = 0
    
    static let initialScanTrackThreshold = 100

    // MARK: - Entity Properties
    var albumEntities: [AlbumEntity] { cachedAlbumEntities }
    
    var isLocalLibraryReady: Bool {
        guard !folders.isEmpty else { return false }
        if isInitialOnboardingScan {
            return hasReachedInitialScanThreshold
        }
        return true
    }

    var hasLocalMusic: Bool { totalTrackCount > 0 }

    var isInitialLibraryScanBlocking: Bool {
        isInitialOnboardingScan && !hasReachedInitialScanThreshold
    }

    // MARK: - Private/Internal Properties
    private var fileWatcherTimer: Timer?
    internal var discoverExpiryTimer: Timer?

    /// A Discover load that stood down rather than publish against a mid-rewrite smart
    /// playlist, replayed once that rewrite finishes.
    internal var discoverPendingRequest: (forceFeatured: Bool, forceTracks: Bool)?
    internal var discoverLoadTask: Task<Void, Never>?
    /// Bumped by whichever Discover path writes the matching sections. Each captures its
    /// token before awaiting and drops its result if another writer has since published:
    /// detached work can't be cancelled, so a stale finisher would overwrite newer rows.
    /// Split per section group, or a Recently Played refresh would invalidate an in-flight
    /// full load and leave the other rows on skeletons.
    internal var discoverStickyGeneration: Int = 0
    internal var discoverRecentGeneration: Int = 0
    internal var discoverTracksGeneration: Int = 0
    /// Warming runs from both the full load and Recently Played reloads, so it needs a
    /// token neither owns; otherwise a slow pass overwrites a newer collage.
    internal var discoverArtworkGeneration: Int = 0
    /// Bumped on reset. Queued work captures it and refuses to run against a library that
    /// was replaced while it waited its turn.
    internal var discoverResetEpoch: Int = 0
    /// Signature of the last collage attempt per playlist, successful or not. Keyed by
    /// signature rather than id so an edit re-renders the cover, while a playlist with no
    /// usable artwork still isn't re-hydrated every load.
    internal var discoverWarmedPlaylistSignatures: [UUID: String] = [:]
    /// Collages rendered this session. A cold smart playlist recomputes `artworkData` from
    /// an empty track list, so the tile would fall back to a placeholder on every reload.
    internal var discoverPlaylistArtwork: [UUID: Data] = [:]
    private var hasPerformedInitialScan = false
    private var lastThresholdCheckTime: Date = .distantPast
    private let thresholdCheckInterval: TimeInterval = 1.0
    internal var cachedLibraryCategories: [LibraryFilterType: [LibraryFilterItem]] = [:]
    internal var libraryCategoriesLoaded = false
    internal var entityLoadGeneration = 0
    internal var entityLoadTaskGeneration = 0
    internal var entityLoadTask: Task<Void, Never>?
    internal let userDefaults = UserDefaults.standard
    internal let fileManager = FileManager.default
    internal var folderTrackCounts: [Int64: Int] = [:]
    private var pendingLibraryReload: DispatchWorkItem?

    // Database manager
    let databaseManager: DatabaseManager

    // Keys for UserDefaults
    internal enum UserDefaultsKeys {
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
            
            await MainActor.run {
                startFileWatcher()
                startDiscoverExpiryTimer()
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: TimeConstants.fiftyMilliseconds)
            let didRunMigration = await databaseManager.runPendingBackgroundMigrations()
            await MainActor.run {
                // A migration that ran (e.g. the v12 album-artist backfill) can change
                // entities and category membership; refresh both so the changes show
                // without requiring a relaunch. Otherwise entities stay lazy at launch.
                if didRunMigration {
                    invalidatePendingEntityLoad()
                    if entitiesLoaded {
                        Task { await refreshEntitiesAsync() }
                    } else {
                        refreshArtistNameLookup()
                        updateTotalCounts()
                    }
                    refreshLibraryCategories()
                    NotificationCenter.default.post(name: .libraryDataDidChange, object: nil)
                }
            }
            ArtistBioManager.shared.fetchMissingArtistImages(using: self)
        }

        // Observe auto-scan interval changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(autoScanIntervalDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        
        // Observe initial scan events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInitialScanStarted),
            name: .initialScanStarted,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCheckInitialScanThreshold),
            name: .checkInitialScanThreshold,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInitialScanCompleted),
            name: .initialScanCompleted,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFoldersAddedToDatabase),
            name: .foldersAddedToDatabase,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSmartPlaylistPersistenceDidFinish),
            name: .smartPlaylistPersistenceDidFinish,
            object: nil
        )

        // Most Loved & Played is driven by these two rather than by the Discover interval.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDiscoverLovedSignalChanged),
            name: .trackFavoriteStatusChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDiscoverLovedSignalChanged),
            name: .trackPlayCountUpdated,
            object: nil
        )
    }

    deinit {
        fileWatcherTimer?.invalidate()
        stopDiscoverExpiryTimer()
        discoverLoadTask?.cancel()
        // Stop accessing all security scoped resources
        for folder in folders where folder.bookmarkData != nil {
            folder.url.stopAccessingSecurityScopedResource()
        }
    }
    
    internal func updateTotalCounts(notify: Bool = true) {
        totalTrackCount = databaseManager.getTotalTrackCount()
        artistCount = databaseManager.getArtistCount()
        albumCount = databaseManager.getAlbumCount()

        if notify {
            NotificationCenter.default.post(name: .libraryDataDidChange, object: nil)
        }
    }
    
    /// Debounced library reload to coalesce rapid completion events
    func scheduleLibraryReload(delay: TimeInterval = 0.3) {
        pendingLibraryReload?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.refreshLibraryCategories()
            self.loadMusicLibrary()
            self.updateTotalCounts()
        }
        pendingLibraryReload = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Check if we've reached the track threshold during initial onboarding scan
    func checkInitialScanThreshold() {
        guard isInitialOnboardingScan else { return }
        
        // Check threshold only if not already reached
        if !hasReachedInitialScanThreshold {
            updateTotalCounts(notify: false)

            let currentCount = totalTrackCount
            if currentCount >= Self.initialScanTrackThreshold {
                Logger.info("Initial scan threshold reached: \(currentCount) tracks")
                hasReachedInitialScanThreshold = true
                
                // Refresh library data so UI can populate (debounced to coalesce with scan completion)
                scheduleLibraryReload()
                refreshDiscoverTracks()
            }
        }
    }

    /// Reset initial scan state (called when scan completes or is cancelled)
    func resetInitialScanState() {
        isInitialOnboardingScan = false
        hasReachedInitialScanThreshold = false
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
                let itemCounts = self.cachedLibraryCategories.values.map { $0.count }
                Logger.info(
                    "Loaded library categories in \(String(format: "%.2f", elapsed))s: \(itemCounts) items total"
                )
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
        invalidatePendingEntityLoad()
        // Use the existing resetDatabase method
        try databaseManager.resetDatabase()

        // Ensure UI updates happen on main thread
        await MainActor.run {
            // Clear in-memory data
            folders.removeAll()
            tracks.removeAll()
            totalTrackCount = 0
            artistCount = 0
            albumCount = 0
            cachedArtistEntities.removeAll()
            cachedAlbumEntities.removeAll()
            entitiesLoaded = false
            // Static parser state outlives the database, so drop the deleted library's names
            ArtistParser.setLibraryArtists([:])

            // Clear UserDefaults (remove the security bookmarks reference)
            UserDefaults.standard.removeObject(forKey: "LastScanDate")

            // Discover's caches hold entity references and raw track IDs from the deleted
            // database; against a new one they resolve to unrelated rows.
            clearDiscoverCaches()
        }
    }

    @objc
    private func autoScanIntervalDidChange() {
        let newInterval = autoScanInterval

        enum LastInterval {
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
    
    @objc
    private func handleInitialScanStarted() {
        DispatchQueue.main.async {
            self.isInitialOnboardingScan = true
            self.hasReachedInitialScanThreshold = false
            Logger.info("Initial onboarding scan started")
        }
    }

    @objc
    private func handleCheckInitialScanThreshold() {
        DispatchQueue.main.async {
            let now = Date()
            
            guard now.timeIntervalSince(self.lastThresholdCheckTime) >= self.thresholdCheckInterval else {
                return
            }
            self.lastThresholdCheckTime = now
            
            self.checkInitialScanThreshold()
        }
    }
    
    @objc
    private func handleInitialScanCompleted() {
        DispatchQueue.main.async {
            // Only process if we were actually in an initial scan
            guard self.isInitialOnboardingScan else { return }
            
            // Reset initial scan state
            self.resetInitialScanState()
            
            // Debounced final refresh of all data
            self.scheduleLibraryReload()

            Logger.info("Initial scan completed, library fully loaded")

            // Fetch artist images after scan
            ArtistBioManager.shared.fetchMissingArtistImages(using: self)
        }
    }
    
    @objc
    private func handleFoldersAddedToDatabase() {
        DispatchQueue.main.async {
            // Immediately load folders so UI knows folders exist
            self.folders = self.databaseManager.getAllFolders()
            Logger.info("Folders loaded immediately after database insert: \(self.folders.count) folders")
        }
    }
}
