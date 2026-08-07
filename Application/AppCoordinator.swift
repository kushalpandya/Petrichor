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
    let menuBarManager: MenuBarManager
    let scrobbleManager: ScrobbleManager
    
    private var hadFoldersAtStartup: Bool = false
    private let playbackStateKey = "SavedPlaybackState"
    private let playbackUIStateKey = "SavedPlaybackUIState"
    private let savedStationKey = "SavedRadioStationId"

    /// The source identity launch restoration was scheduled under; see
    /// `prepareTrackForRestoration(_:at:expecting:)`.
    private var restorationGeneration: UInt64 = 0
    
    // Track restoration state to prevent race conditions
    private var isRestoringPlayback = false
    private var libraryObserver: NSObjectProtocol?
    
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
        
        // Setup now playing - PlaybackManager owns the single Now Playing path
        playbackManager.connectRemoteCommandCenter()
        
        // Setup menubar
        menuBarManager = MenuBarManager(playbackManager: playbackManager, playlistManager: playlistManager)
        
        // Setup Scrobbling
        scrobbleManager = ScrobbleManager()
        
        hadFoldersAtStartup = !libraryManager.folders.isEmpty

        Self.shared = self

        // Set after `shared`: the manager reads the database through it.
        InternetRadioManager.shared.loadStations()
        restoreStationIfNeeded()

        // Check if library is empty at startup - if so, clear any saved state
        if !hadFoldersAtStartup {
            clearAllSavedState()
        } else {
            // Only restore if we have folders
            restoreUIStateImmediately()
            
            // Claimed before the delay, so anything the user starts in the meantime
            // supersedes the restore rather than being overwritten by it.
            restorationGeneration = playbackManager.sourceGeneration

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

    // MARK: - Internet Radio Restoration

    private func saveCurrentStation() {
        if let stationId = playbackManager.currentStation?.id {
            UserDefaults.standard.set(stationId, forKey: savedStationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: savedStationKey)
        }
    }

    /// Restored stopped: no network reach-out on launch. Reads its one row directly
    /// rather than waiting on the published list, which loads asynchronously, so
    /// `restoreUIStateImmediately` sees the station.
    private func restoreStationIfNeeded() {
        guard UserDefaults.standard.object(forKey: savedStationKey) != nil else { return }

        let stationId = Int64(UserDefaults.standard.integer(forKey: savedStationKey))
        guard let station = libraryManager.databaseManager.loadStation(id: stationId) else {
            // Station was deleted since the last run.
            UserDefaults.standard.removeObject(forKey: savedStationKey)
            return
        }

        playbackManager.restoreStation(station)
        Logger.info("Restored radio station in player: \(station.name)")
    }
    
    func savePlaybackState() {
        // Own key, so the library-emptiness checks can't clear it.
        saveCurrentStation()

        let currentTrack = playbackManager.currentTrack

        guard currentTrack != nil || playbackManager.currentStation != nil else {
            clearAllSavedState()
            return
        }

        // Determine source identifier
        var sourceIdentifier: String?
        switch playlistManager.currentQueueSource {
        case .folder:
            if let folderId = currentTrack?.folderId,
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
            playbackPosition: currentTrack != nil ? playbackManager.actualCurrentTime : 0,
            queue: playlistManager.currentQueue,
            currentQueueIndex: playlistManager.currentQueueIndex,
            queueSource: playlistManager.currentQueueSource,
            sourceIdentifier: sourceIdentifier,
            volume: playbackManager.volume,
            isMuted: playbackManager.volume < 0.01,
            shuffleEnabled: playlistManager.isShuffleEnabled,
            repeatMode: playlistManager.repeatMode
        )

        if let currentTrack, let uiState = state.createUIState(from: currentTrack),
           let uiData = try? JSONEncoder().encode(uiState) {
            UserDefaults.standard.set(uiData, forKey: playbackUIStateKey)
        } else {
            // Radio is showing: drop the stale track tile.
            UserDefaults.standard.removeObject(forKey: playbackUIStateKey)
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: playbackStateKey)
            Logger.info("Playback state saved")
        } catch {
            Logger.warning("Failed to save playback state: \(error)")
        }
    }
    
    func restoreUIStateImmediately() {
        // A restored station already owns the player bar.
        guard playbackManager.currentStation == nil else { return }

        // Try to restore UI state immediately
        guard let uiData = UserDefaults.standard.data(forKey: playbackUIStateKey),
              let uiState = try? JSONDecoder().decode(PlaybackUIState.self, from: uiData) else {
            return
        }
        
        // Restore UI immediately
        playbackManager.restoreUIState(uiState)
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
        // Before anything is written, not just before the track is installed: this also
        // replaces the queue, cursor and source, which a later track-only rejection leaves
        // behind describing the saved session.
        guard restorationGeneration == playbackManager.sourceGeneration else {
            Logger.info("Skipped playback restoration: a source was selected before it ran")
            return
        }

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
        
        // Ahead of the queue guards below: a radio-only session saves no queue entries, and
        // bailing out early would leave volume, shuffle and repeat at their defaults.
        playlistManager.isShuffleEnabled = state.shuffleEnabled
        playlistManager.repeatMode = state.repeatModeEnum
        playbackManager.setVolume(state.isMuted ? 0 : state.volume)

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
            playbackManager.prepareTrackForRestoration(
                currentTrack,
                at: state.playbackPosition,
                expecting: restorationGeneration
            )
            Logger.info("Playback state restored")
        }
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
