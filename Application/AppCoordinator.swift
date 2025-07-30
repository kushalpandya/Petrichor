//
// AppCoordinator class
//
// This class handles playback initialization & state saving and restoration based on library updates.
//

import SwiftUI

class AppCoordinator: ObservableObject {
    // MARK: - Managers
    private(set) static var shared: AppCoordinator?
    let libraryManager: LibraryManager
    let playlistManager: PlaylistManager
    let playbackManager: PlaybackManager
    let nowPlayingManager: NowPlayingManager
    let menuBarManager: MenuBarManager
    
    private var hadFoldersAtStartup: Bool = false
    private let playbackStateKey = "SavedPlaybackState"
    private let playbackUIStateKey = "SavedPlaybackUIState"
    
    // Track restoration state to prevent race conditions
    private var isRestoringPlayback = false
    private var libraryObserver: NSObjectProtocol?
    
    @Published var isQueueVisible: Bool = false
    
    // MARK: - Initialization
    
    init() {
        // Initialize managers
        libraryManager = LibraryManager()
        playlistManager = PlaylistManager()
        
        // Create audio player with dependencies
        playbackManager = PlaybackManager(libraryManager: libraryManager, playlistManager: playlistManager)
        
        // Connect managers
        playlistManager.setAudioPlayer(playbackManager)
        playlistManager.setLibraryManager(libraryManager)
        
        // Setup now playing
        nowPlayingManager = NowPlayingManager()
        nowPlayingManager.connectRemoteCommandCenter(audioPlayer: playbackManager, playlistManager: playlistManager)
        
        // Setup menubar
        menuBarManager = MenuBarManager(playbackManager: playbackManager, playlistManager: playlistManager)
        
        hadFoldersAtStartup = !libraryManager.folders.isEmpty
        
        Self.shared = self
        
        // Check if library is empty at startup - if so, clear any saved state
        if !hadFoldersAtStartup {
            clearAllSavedState()
        } else {
            // Only restore if we have folders
            restoreUIStateImmediately()
            
            // Schedule restoration after a minimal delay to ensure UI is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.restorePlaybackState()
            }
        }
    }
    
    deinit {
        // Clean up any remaining observers
        if let observer = libraryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Playback State Persistence
    
    private func clearAllSavedState() {
        UserDefaults.standard.removeObject(forKey: playbackStateKey)
        UserDefaults.standard.removeObject(forKey: playbackUIStateKey)
        playbackManager.restoredUITrack = nil
        playbackManager.currentTrack = nil
    }
    
    func savePlaybackState(for calledFromStateTimer: Bool = false) {
        // Only save if we have a current track
        guard let currentTrack = playbackManager.currentTrack else {
            clearAllSavedState()
            return
        }
        
        // Determine source identifier
        var sourceIdentifier: String?
        switch playlistManager.currentQueueSource {
        case .folder:
            if let folderId = currentTrack.folderId,
               let folder = libraryManager.folders.first(where: { $0.id == folderId }) {
                sourceIdentifier = folder.url.path
            }
        case .playlist:
            sourceIdentifier = playlistManager.currentPlaylist?.id.uuidString
        default:
            break
        }
        
        let state = PlaybackState(
            currentTrack: currentTrack,
            playbackPosition: playbackManager.actualCurrentTime,
            queueVisible: isQueueVisible,
            queue: playlistManager.currentQueue,
            currentQueueIndex: playlistManager.currentQueueIndex,
            queueSource: playlistManager.currentQueueSource,
            sourceIdentifier: sourceIdentifier,
            volume: playbackManager.volume,
            isMuted: playbackManager.volume < 0.01,
            shuffleEnabled: playlistManager.isShuffleEnabled,
            repeatMode: playlistManager.repeatMode
        )
        
        if let uiState = state.createUIState(from: currentTrack) {
            if let uiData = try? JSONEncoder().encode(uiState) {
                UserDefaults.standard.set(uiData, forKey: playbackUIStateKey)
            }
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: playbackStateKey)
            Logger.info(calledFromStateTimer ? "Playback state saved during active playback" : "Playback state saved")
        } catch {
            Logger.warning("Failed to save playback state: \(error)")
        }
    }
    
    func restoreUIStateImmediately() {
        // Try to restore UI state immediately
        guard let uiData = UserDefaults.standard.data(forKey: playbackUIStateKey),
              let uiState = try? JSONDecoder().decode(PlaybackUIState.self, from: uiData) else {
            return
        }
        
        // Restore UI immediately
        playbackManager.restoreUIState(uiState)
        isQueueVisible = uiState.queueVisible
    }
    
    func restorePlaybackState() {
        // Prevent concurrent restorations
        guard !isRestoringPlayback else {
            return
        }
        
        isRestoringPlayback = true
        
        // Don't restore immediately, wait for library to be fully loaded
        if libraryManager.totalTrackCount == 0 {
            if libraryManager.folders.isEmpty {
                clearAllSavedState()
                isRestoringPlayback = false
                return
            }
            
            // Use a stored observer reference to ensure proper cleanup
            libraryObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("LibraryDidLoad"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.libraryDidLoad()
            }
            return
        }
        
        // Proceed with restoration
        performActualRestoration()
    }
    
    @objc
    private func libraryDidLoad() {
        if let observer = libraryObserver {
            NotificationCenter.default.removeObserver(observer)
            libraryObserver = nil
        }
        
        // Don't restore if we didn't have folders at startup
        if !hadFoldersAtStartup {
            isRestoringPlayback = false
            return
        }
        
        // Check if library is loaded with content
        if libraryManager.folders.isEmpty || libraryManager.totalTrackCount == 0 {
            clearAllSavedState()
            isRestoringPlayback = false
            return
        }
        
        // Now perform restoration
        performActualRestoration()
    }
    
    private func performActualRestoration() {
        defer { isRestoringPlayback = false }
        
        guard let data = UserDefaults.standard.data(forKey: playbackStateKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let state = try decoder.decode(PlaybackState.self, from: data)
            let stateAge = Date().timeIntervalSince(state.savedDate)
            
            // Clear saved state if older than 7 days
            if stateAge > 7 * 24 * 60 * 60 {
                clearAllSavedState()
                return
            }
            
            // Perform state restoration
            performStateRestoration(state)
        } catch {
            Logger.warning("Failed to restore playback state: \(error)")
            clearAllSavedState()
        }
    }
    
    private func performStateRestoration(_ state: PlaybackState) {
        // Load only the tracks we need for restoration
        let trackIdsNeeded = Set(state.queueTrackIds + [state.currentTrackId].compactMap { $0 })
        var relevantTracks = libraryManager.databaseManager.getTracks(byIds: Array(trackIdsNeeded))
        libraryManager.databaseManager.populateAlbumArtworkForTracks(&relevantTracks)

        // Create a track ID to track map for efficient lookup
        let trackIdMap: [Int64: Track] = Dictionary(
            relevantTracks.compactMap { track in
                guard let trackId = track.trackId else { return nil }
                return (trackId, track)
            }
        ) { first, _ in first }
        
        // Create a path to track map as fallback
        let trackPathMap: [String: Track] = Dictionary(
            relevantTracks.map { track in
                (track.url.path, track)
            }
        ) { first, _ in first }
        
        // Restore the play queue
        var restoredQueue: [Track] = []
        restoredQueue.reserveCapacity(state.queueTrackIds.count)
        
        for (index, trackId) in state.queueTrackIds.enumerated() {
            if let track = trackIdMap[trackId] {
                restoredQueue.append(track)
            } else if index < state.queueTrackPaths.count {
                // Fallback to path matching
                let path = state.queueTrackPaths[index]
                if let track = trackPathMap[path] {
                    restoredQueue.append(track)
                }
            }
        }
        
        // Check if we restored at least 50% queue (songs may have been removed)
        let restorationRatio = Double(restoredQueue.count) / Double(state.queueTrackPaths.count)
        if restorationRatio < 0.5 {
            clearAllSavedState()
            return
        }
        
        // Only proceed if we found at least some tracks
        guard !restoredQueue.isEmpty else {
            clearAllSavedState()
            return
        }
        
        // Restore playback settings first
        playlistManager.isShuffleEnabled = state.shuffleEnabled
        playlistManager.repeatMode = state.repeatModeEnum
        playbackManager.setVolume(state.isMuted ? 0 : state.volume)
        
        // Set the queue
        playlistManager.currentQueue = restoredQueue
        playlistManager.currentQueueIndex = min(state.currentQueueIndex, restoredQueue.count - 1)
        playlistManager.currentQueueSource = state.queueSourceEnum
        
        // Try to restore the source context
        switch state.queueSourceEnum {
        case .playlist:
            if let playlistId = state.sourceIdentifier,
               let uuid = UUID(uuidString: playlistId),
               let playlist = playlistManager.playlists.first(where: { $0.id == uuid }) {
                playlistManager.currentPlaylist = playlist
            }
        default:
            break
        }
        
        // Restore UI state
        isQueueVisible = state.queueVisible
        
        // Find and prepare the current track
        if let currentTrackId = state.currentTrackId,
           let currentTrack = restoredQueue.first(where: { $0.trackId == currentTrackId }) {
            // Verify the file exists and is accessible
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: currentTrack.url.path) else {
                clearAllSavedState()
                return
            }
            
            // Try to access the file
            guard fileManager.isReadableFile(atPath: currentTrack.url.path) else {
                clearAllSavedState()
                return
            }
            
            // Clear the temporary UI track before setting the real one
            playbackManager.restoredUITrack = nil
            playbackManager.prepareTrackForRestoration(currentTrack, at: state.playbackPosition)
            Logger.info("Playback state restored")
        }
    }
    
    func clearPlaybackStateIfNeeded() {
        let lastVersionKey = "LastLaunchedAppVersion"
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        
        // Get the last launched version
        let lastVersion = UserDefaults.standard.string(forKey: lastVersionKey) ?? ""
        
        // Clear state if version changed significantly
        if lastVersion != currentVersion && !lastVersion.isEmpty {
            clearAllSavedState()
        }
        
        // Update the stored version
        UserDefaults.standard.set(currentVersion, forKey: lastVersionKey)
    }
    
    func handleLibraryChanged() {
        // If the library was significantly changed (e.g., folders removed),
        // the saved state might no longer be valid
        if let savedStateData = UserDefaults.standard.data(forKey: playbackStateKey),
           let state = try? JSONDecoder().decode(PlaybackState.self, from: savedStateData) {
            // Check if the current track still exists
            if let trackId = state.currentTrackId {
                let trackExists = libraryManager.databaseManager.trackExists(withId: trackId)
                if !trackExists {
                    UserDefaults.standard.removeObject(forKey: playbackStateKey)
                }
            }
            
            // Also check UI state validity
            if let uiData = UserDefaults.standard.data(forKey: playbackUIStateKey),
               (try? JSONDecoder().decode(PlaybackUIState.self, from: uiData)) != nil {
                // If the main state is invalid, clear UI state too
                if UserDefaults.standard.data(forKey: playbackStateKey) == nil {
                    UserDefaults.standard.removeObject(forKey: playbackUIStateKey)
                }
            }
        }
    }
}
