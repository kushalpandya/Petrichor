//
// PlaybackManager class
//
// This class handles track playback coordination with PAudioPlayer,
// including database updates, state persistence, and integration with
// PlaylistManager and NowPlayingManager.
//

import AVFoundation
import Foundation

class PlaybackManager: NSObject, ObservableObject {
    let playbackProgressState = PlaybackProgressState()

    // MARK: - Published Properties

    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false {
        didSet {
            NotificationCenter.default.post(
                name: NSNotification.Name("PlaybackStateChanged"), object: nil)
        }
    }
    var currentTime: Double {
        get { playbackProgressState.currentTime }
        set { playbackProgressState.currentTime = newValue }
    }
    @Published var volume: Float = 0.7 {
        didSet {
            audioPlayer.volume = volume
        }
    }
    @Published var restoredUITrack: Track?
    
    // MARK: - Configuration

    var gaplessPlayback: Bool = false
    
    // MARK: - Computed Properties
    
    /// Alias for currentTime for backwards compatibility
    var actualCurrentTime: Double {
        currentTime
    }
    
    var effectiveCurrentTime: Double {
        if currentTime > 0 {
            return currentTime
        }
        return restoredPosition
    }
    
    // MARK: - Private Properties
    
    private let audioPlayer: PAudioPlayer
    private var currentFullTrack: FullTrack?
    private var progressUpdateTimer: DispatchSourceTimer?
    private var stateSaveTimer: Timer?
    private var restoredPosition: Double = 0
    
    // MARK: - Dependencies
    
    private let libraryManager: LibraryManager
    private let playlistManager: PlaylistManager
    private let nowPlayingManager: NowPlayingManager
    
    // MARK: - Initialization
    
    init(libraryManager: LibraryManager, playlistManager: PlaylistManager) {
        self.libraryManager = libraryManager
        self.playlistManager = playlistManager
        self.nowPlayingManager = NowPlayingManager()
        self.audioPlayer = PAudioPlayer()
        
        super.init()
        
        self.audioPlayer.delegate = self
        self.audioPlayer.volume = volume
        
        // Start a simple timer that updates currentTime from audioPlayer
        startProgressUpdateTimer()
    }
    
    deinit {
        stop()
        stopProgressUpdateTimer()
        stopStateSaveTimer()
    }
    
    // MARK: - Player State Management
    
    func restoreUIState(_ uiState: PlaybackUIState) {
        var tempTrack = Track(url: URL(fileURLWithPath: "/restored"))
        tempTrack.title = uiState.trackTitle
        tempTrack.artist = uiState.trackArtist
        tempTrack.album = uiState.trackAlbum
        tempTrack.albumArtworkMedium = uiState.artworkData
        tempTrack.duration = uiState.trackDuration
        tempTrack.isMetadataLoaded = true
        
        restoredUITrack = tempTrack
        currentTrack = tempTrack
        restoredPosition = uiState.playbackPosition
        volume = uiState.volume
        
        nowPlayingManager.updateNowPlayingInfo(
            track: tempTrack,
            currentTime: uiState.playbackPosition,
            isPlaying: false
        )
    }
    
    func prepareTrackForRestoration(_ track: Track, at position: Double) {
        restoredUITrack = nil
        
        Task {
            do {
                guard let fullTrack = try await track.fullTrack(using: libraryManager.databaseManager.dbQueue) else {
                    await MainActor.run {
                        Logger.error("Failed to fetch track data for restoration")
                    }
                    return
                }
                
                await MainActor.run {
                    self.currentTrack = track
                    self.currentFullTrack = fullTrack
                    self.restoredPosition = position
                    self.currentTime = position
                    self.isPlaying = false
                    
                    self.nowPlayingManager.updateNowPlayingInfo(
                        track: track,
                        currentTime: position,
                        isPlaying: false
                    )
                    
                    Logger.info("Prepared track for restoration at position: \(position)")
                }
            } catch {
                await MainActor.run {
                    Logger.error("Failed to prepare track for restoration: \(error)")
                }
            }
        }
    }
    
    // MARK: - Playback Controls
    
    func playTrack(_ track: Track) {
        restoredUITrack = nil
        restoredPosition = 0
        
        guard FileManager.default.fileExists(atPath: track.url.path) else {
            Logger.warning("Track file does not exist: \(track.url.path)")
            NotificationManager.shared.addMessage(.error, "Cannot play '\(track.title)': File not found")
            
            // Auto-skip to next track if in queue
            if playlistManager.currentQueue.count > 1 {
                Logger.info("File not found, skipping to next track in queue")
                playlistManager.playNextTrack()
            }
            return
        }
                
        Task {
            do {
                guard let fullTrack = try await track.fullTrack(using: libraryManager.databaseManager.dbQueue) else {
                    await MainActor.run {
                        Logger.error("Failed to fetch full track data for: \(track.title)")
                        NotificationManager.shared.addMessage(.error, "Cannot play track - missing data")
                    }
                    return
                }
                
                await MainActor.run {
                    self.startPlayback(of: fullTrack, lightweightTrack: track)
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
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.togglePlayPause()
            }
            return
        }
        
        if isPlaying {
            audioPlayer.pause()
            isPlaying = false
            stopStateSaveTimer()
        } else {
            if let fullTrack = currentFullTrack, let track = currentTrack, audioPlayer.state != .paused {
                startPlayback(of: fullTrack, lightweightTrack: track)
                isPlaying = true
            } else {
                audioPlayer.resume()
                isPlaying = true
                startStateSaveTimer()
            }
        }
        
        updateNowPlayingInfo()
    }
    
    func stop() {
        audioPlayer.stop()
        currentTrack = nil
        currentFullTrack = nil
        currentTime = 0
        isPlaying = false
        restoredPosition = 0
        stopStateSaveTimer()
        Logger.info("Playback stopped")
    }
    
    func stopGracefully() {
        audioPlayer.stop()
        currentTrack = nil
        currentFullTrack = nil
        currentTime = 0
        isPlaying = false
        stopStateSaveTimer()
        Logger.info("Playback stopped gracefully")
    }
    
    func seekTo(time: Double) {
        audioPlayer.seek(to: time)
        currentTime = time
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
    }
    
    func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        nowPlayingManager.updateNowPlayingInfo(
            track: track,
            currentTime: currentTime,
            isPlaying: isPlaying
        )
    }
    
    // MARK: - Audio Effects (Placeholders for future implementation)

    func setStereoWidening(enabled: Bool) {
        // TODO: Implement when EQ features are added to PAudioPlayer
        Logger.info("Stereo widening not yet implemented in PAudioPlayer")
    }

    func applyEQ(preset: String) {
        // TODO: Implement when EQ features are added to PAudioPlayer
        Logger.info("EQ preset not yet implemented in PAudioPlayer")
    }

    func applyEQ(gains: [Float]) {
        // TODO: Implement when EQ features are added to PAudioPlayer
        Logger.info("EQ gains not yet implemented in PAudioPlayer")
    }
    
    // MARK: - Private Methods
    
    private func startPlayback(of fullTrack: FullTrack, lightweightTrack: Track) {
        currentTrack = lightweightTrack
        currentFullTrack = fullTrack
        
        let seekToPosition = restoredPosition
        restoredPosition = 0
        
        if seekToPosition > 0 {
            audioPlayer.play(url: fullTrack.url, startPaused: true)
            currentTime = seekToPosition
            
            // Wait for decoder to be ready before resuming playback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                if self.audioPlayer.seek(to: seekToPosition) {
                    self.audioPlayer.resume()
                    Logger.info("Resumed playback: \(lightweightTrack.title) from \(seekToPosition)s")
                } else {
                    Logger.warning("Seek failed, starting from beginning")
                    self.currentTime = 0
                    self.audioPlayer.play(url: fullTrack.url, startPaused: false)
                }
            }
        } else {
            currentTime = 0
            audioPlayer.play(url: fullTrack.url, startPaused: false)
            Logger.info("Started playback: \(lightweightTrack.title)")
        }
        
        startStateSaveTimer()
        updateNowPlayingInfo()
        playlistManager.incrementPlayCount(for: lightweightTrack)
    }
    
    private func startProgressUpdateTimer() {
        progressUpdateTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isPlaying else { return }
            self.currentTime = self.audioPlayer.currentPlaybackProgress
            self.updateNowPlayingInfo()
        }
        
        timer.resume()
        progressUpdateTimer = timer
    }
    
    private func stopProgressUpdateTimer() {
        progressUpdateTimer?.cancel()
        progressUpdateTimer = nil
    }
    
    private func startStateSaveTimer() {
        stateSaveTimer?.invalidate()
        stateSaveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isPlaying {
                NotificationCenter.default.post(
                    name: NSNotification.Name("SavePlaybackState"),
                    object: nil
                )
            }
        }
    }
    
    private func stopStateSaveTimer() {
        stateSaveTimer?.invalidate()
        stateSaveTimer = nil
    }
}

// MARK: - AudioPlayerDelegate

extension PlaybackManager: AudioPlayerDelegate {
    func audioPlayerDidStartPlaying(player: PAudioPlayer, with entryId: AudioEntryId) {
        DispatchQueue.main.async {
            self.isPlaying = true
            Logger.info("Track started playing: \(entryId.id)")
        }
    }
    
    func audioPlayerStateChanged(player: PAudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState) {
        DispatchQueue.main.async {
            let oldIsPlaying = self.isPlaying

            switch newState {
            case .playing:
                self.isPlaying = true
            case .paused:
                self.isPlaying = false
            case .stopped:
                self.isPlaying = false
            case .ready:
                break
            }
            
            if oldIsPlaying != self.isPlaying {
                self.updateNowPlayingInfo()
            }
            Logger.info("Player state changed: \(previous) → \(newState)")
        }
    }
    
    func audioPlayerDidFinishPlaying(
        player: PAudioPlayer,
        entryId: AudioEntryId,
        stopReason: AudioPlayerStopReason,
        progress: Double,
        duration: Double
    ) {
        DispatchQueue.main.async {
            guard self.currentTrack != nil else {
                Logger.info("Ignoring finish - no current track")
                return
            }
            
            Logger.info("Track finished (reason: \(stopReason))")
            
            self.currentTime = 0
            
            switch stopReason {
            case .eof:
                self.restoredPosition = 0
                if self.gaplessPlayback {
                    self.playlistManager.playNextTrack()
                } else {
                    self.playlistManager.handleTrackCompletion()
                    if !self.isPlaying {
                        self.stopStateSaveTimer()
                        
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SavePlaybackState"),
                            object: nil
                        )
                    }
                }
                
            case .userAction:
                self.stopStateSaveTimer()
                
            case .error:
                self.isPlaying = false
                Logger.error("Playback finished with error")
                NotificationManager.shared.addMessage(.error, "Playback error occurred")
            }
        }
    }
    
    func audioPlayerUnexpectedError(player: PAudioPlayer, error: AudioPlayerError) {
        DispatchQueue.main.async {
            Logger.error("Audio player error: \(error.localizedDescription)")
            NotificationManager.shared.addMessage(.error, "Playback error: \(error.localizedDescription)")
        }
    }
}
