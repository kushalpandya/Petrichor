//
// PlaybackManager class
//
// This class handles the track playback, including progression update,
// seeking, and playback state management.
//

import AVFoundation
import Foundation

class PlaybackManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false {
        didSet {
            // Post notification when playback state changes
            NotificationCenter.default.post(
                name: NSNotification.Name("PlaybackStateChanged"), object: nil)
        }
    }
    @Published var currentTime: Double = 0
    @Published var volume: Float = 0.7
    @Published var restoredUITrack: Track?

    var player: AVAudioPlayer?
    
    var actualCurrentTime: Double {
        player?.currentTime ?? currentTime
    }

    // MARK: - Private Properties
    private var currentFullTrack: FullTrack?
    private var playbackProgressTimer: Timer?
    private var stateSaveTimer: Timer?
    private var restoredPosition: Double = 0
    private var lastReportedTime: Double = 0  // Track last reported time to reduce updates

    // MARK: - Dependencies
    private let libraryManager: LibraryManager
    private let playlistManager: PlaylistManager
    private let nowPlayingManager: NowPlayingManager

    // MARK: - Initialization
    init(libraryManager: LibraryManager, playlistManager: PlaylistManager) {
        self.libraryManager = libraryManager
        self.playlistManager = playlistManager
        self.nowPlayingManager = NowPlayingManager()

        super.init()

        // Configure audio session for better performance
        configureAudioSession()
    }

    deinit {
        stop()
        stopPlaybackProgressTimer()
        stopStateSaveTimer()
    }

    // MARK: - Audio Session Configuration
    private func configureAudioSession() {
        // For macOS, we can optimize the audio player settings
        // This helps prevent audio overload issues
    }

    func restoreUIState(_ uiState: PlaybackUIState) {
        var tempTrack = Track(url: URL(fileURLWithPath: "/restored"))
        tempTrack.title = uiState.trackTitle
        tempTrack.artist = uiState.trackArtist
        tempTrack.album = uiState.trackAlbum
        tempTrack.albumArtworkData = uiState.artworkData
        tempTrack.duration = uiState.trackDuration
        tempTrack.isMetadataLoaded = true

        // Set UI state
        restoredUITrack = tempTrack
        currentTrack = tempTrack
        restoredPosition = uiState.playbackPosition
        currentTime = uiState.playbackPosition
        lastReportedTime = uiState.playbackPosition
        volume = uiState.volume

        // Update Now Playing with restored info
        nowPlayingManager.updateNowPlayingInfo(
            track: tempTrack, currentTime: uiState.playbackPosition, isPlaying: false)
    }

    // MARK: - Playback Controls
    func playTrack(_ track: Track) {
        // Clear any restored UI state
        restoredUITrack = nil

        Task {
            do {
                // Fetch full track data for playback
                guard let fullTrack = try await track.fullTrack(using: libraryManager.databaseManager.dbQueue) else {
                    await MainActor.run {
                        Logger.error("Failed to fetch full track data for: \(track.title)")
                        NotificationManager.shared.addMessage(.error, "Cannot play track - missing data")
                    }
                    return
                }
                
                // Continue with playback on main thread
                await MainActor.run {
                    self.playFullTrack(fullTrack, lightweightTrack: track)
                }
            } catch {
                await MainActor.run {
                    Logger.error("Failed to fetch track data: \(error)")
                    NotificationManager.shared.addMessage(.error, "Failed to load track for playback")
                }
            }
        }
    }

    func togglePlayPause() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            stopPlaybackProgressTimer()
            stopStateSaveTimer()
        } else {
            player.play()
            startPlaybackProgressTimer()
            startStateSaveTimer()
        }
        
        isPlaying.toggle()
        
        if let track = currentTrack {
            nowPlayingManager.updateNowPlayingInfo(
                track: track, currentTime: currentTime, isPlaying: isPlaying)
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            // Reset time tracking
            lastReportedTime = 0
            currentTime = 0
            
            // First, mark as not playing since the track has ended
            isPlaying = false
            
            // Update Now Playing to show paused state
            if let track = currentTrack {
                nowPlayingManager.updateNowPlayingInfo(
                    track: track, currentTime: 0, isPlaying: false)
            }
            
            // Stop the timer since playback has ended
            stopPlaybackProgressTimer()
            
            // Add a small delay to prevent clicks between tracks
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.playlistManager.handleTrackCompletion()
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        currentFullTrack = nil
        isPlaying = false
        currentTime = 0
        lastReportedTime = 0
        stopPlaybackProgressTimer()
        stopStateSaveTimer()
        
        if let track = currentTrack {
            nowPlayingManager.updateNowPlayingInfo(track: track, currentTime: 0, isPlaying: false)
        }
        Logger.info("Playback stopped")
    }

    // Graceful stop with fade out for app termination
    func stopGracefully() {
        guard let player = player, player.isPlaying else {
            isPlaying = false
            currentTime = 0
            lastReportedTime = 0
            stopPlaybackProgressTimer()
            stopStateSaveTimer()
            Logger.info("Playback stopped")
            return
        }
        
        // For app termination, just stop immediately
        player.stop()
        self.player = nil
        
        isPlaying = false
        currentTime = 0
        lastReportedTime = 0
        stopPlaybackProgressTimer()
        stopStateSaveTimer()
        Logger.info("Playback stopped")
    }

    func seekTo(time: Double) {
        player?.currentTime = time
        currentTime = time
        lastReportedTime = time
        restoredPosition = time
    
        NotificationCenter.default.post(
            name: NSNotification.Name("PlayerDidSeek"),
            object: nil,
            userInfo: ["time": time]
        )
        
        if let track = currentTrack {
            nowPlayingManager.updateNowPlayingInfo(
                track: track, currentTime: time, isPlaying: isPlaying)
        }
    }

    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        player?.volume = volume
    }

    var effectiveCurrentTime: Double {
        // If we have a player and it's been started, use its current time
        if let player = player, player.currentTime > 0 {
            return player.currentTime
        }
        // Otherwise, use the restored position
        return restoredPosition
    }

    // MARK: - Helpers

    func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        nowPlayingManager.updateNowPlayingInfo(
            track: track,
            currentTime: currentTime,
            isPlaying: isPlaying
        )
    }

    // Prepare track for restoration without immediately playing
    func prepareTrackForRestoration(_ track: Track, at position: Double) {
        // Clear any restored UI state
        restoredUITrack = nil

        Task {
            do {
                // Fetch full track data
                guard let fullTrack = try await track.fullTrack(using: libraryManager.databaseManager.dbQueue) else {
                    await MainActor.run {
                        Logger.error("Failed to fetch full track data for restoration: \(track.title)")
                    }
                    return
                }
                
                await MainActor.run {
                    self.prepareFullTrackForRestoration(fullTrack, lightweightTrack: track, at: position)
                }
            } catch {
                await MainActor.run {
                    Logger.error("Failed to fetch track for restoration: \(error)")
                }
            }
        }
    }
    
    private func playFullTrack(_ fullTrack: FullTrack, lightweightTrack: Track) {
        do {
            // Stop any current playback gracefully first
            if let currentPlayer = player {
                // Disable fade to prevent audio overload
                currentPlayer.stop()
                player = nil
            }

            // Create and prepare player with optimized settings
            player = try AVAudioPlayer(contentsOf: fullTrack.url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.enableRate = false  // Disable rate adjustment as playback is fixed at 1x
            player?.isMeteringEnabled = false  // Disable metering as it is not required

            // Set volume directly without fade to prevent buffer issues
            player?.volume = volume

            // Start playback
            player?.play()

            // Update state - keep lightweight track for UI
            currentTrack = lightweightTrack
            currentFullTrack = fullTrack  // Store full track for metadata access
            isPlaying = true
            restoredPosition = 0
            lastReportedTime = 0
            startStateSaveTimer()
            startPlaybackProgressTimer()
        } catch {
            Logger.error("Failed to play track: \(error)")
            let errorMessage = FolderUtils.getMessageForError(
                error,
                context: "play track",
                path: fullTrack.url.path
            )
            
            NotificationManager.shared.addMessage(.error, errorMessage)
        }
    }
    
    private func prepareFullTrackForRestoration(_ fullTrack: FullTrack, lightweightTrack: Track, at position: Double) {
        do {
            // Stop any current playback
            if let currentPlayer = player {
                currentPlayer.stop()
                player = nil
            }

            // Create player but don't prepare or play yet
            player = try AVAudioPlayer(contentsOf: fullTrack.url)
            player?.delegate = self
            player?.volume = volume
            player?.currentTime = position

            // Update state without playing
            currentTrack = lightweightTrack
            currentFullTrack = fullTrack
            currentTime = position
            lastReportedTime = position
            isPlaying = false

            Logger.info("Prepared track for restoration at position: \(position)")
        } catch {
            Logger.error("Failed to prepare track for restoration: \(error)")
        }
    }

    private func startStateSaveTimer() {
        stateSaveTimer?.invalidate()
        // Save state every 30 seconds during playback (increased from 10)
        stateSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            if self?.isPlaying == true {
                AppCoordinator.shared?.savePlaybackState(for: true)
            }
        }
        stateSaveTimer?.tolerance = 5.0
        Logger.info("State save timer started")
    }
    
    // MARK: - Progress Timer Management

    private func startPlaybackProgressTimer() {
        playbackProgressTimer?.invalidate()
        
        // Efficient timer for state saving and Now Playing updates only
        playbackProgressTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            
            if self.isPlaying && player.isPlaying {
                // Update current time for state saving
                self.currentTime = player.currentTime
                
                // Update Now Playing info
                if let track = self.currentTrack {
                    self.nowPlayingManager.updateNowPlayingInfo(
                        track: track,
                        currentTime: self.currentTime,
                        isPlaying: self.isPlaying
                    )
                }
            }
        }
        playbackProgressTimer?.tolerance = 1.0
    }

    private func stopPlaybackProgressTimer() {
        playbackProgressTimer?.invalidate()
        playbackProgressTimer = nil
        Logger.info("Track playback progress timer stopped")
    }
    
    private func stopStateSaveTimer() {
        stateSaveTimer?.invalidate()
        stateSaveTimer = nil
        Logger.info("State save timer stopped")
    }
}
