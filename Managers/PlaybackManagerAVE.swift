//
// PlaybackManager.swift
//
// This class handles the track playback, including progression update,
// seeking, and playback state management using AudioPlayer (AVAudioEngine).
//

import AVFoundation
import Foundation

class PlaybackManager: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false {
        didSet {
            NotificationCenter.default.post(
                name: NSNotification.Name("PlaybackStateChanged"), object: nil)
        }
    }
    @Published var currentTime: Double = 0
    @Published var volume: Float = 0.7 {
        didSet {
            audioPlayer.volume = volume
        }
    }
    @Published var restoredUITrack: Track?
    
    // MARK: - Configuration

    var gaplessPlayback: Bool = false
    
    // MARK: - Computed Properties

    var actualCurrentTime: Double {
        // While seeking, return the target time to keep UI consistent
        if isSeeking && seekTargetTime > 0 {
            return seekTargetTime
        }
        // When we have a restored position but player hasn't started yet
        if restoredPosition > 0 && audioPlayer.state == .ready {
            return restoredPosition
        }
        // During normal playback, return actual progress
        return audioPlayer.progress
    }
    
    var effectiveCurrentTime: Double {
        if audioPlayer.progress > 0 {
            return audioPlayer.progress
        }
        return restoredPosition
    }
    
    // MARK: - Private Properties
    
    private let audioPlayer: AudioPlayer
    private var currentFullTrack: FullTrack?
    private var playbackProgressTimer: Timer?
    private var stateSaveTimer: Timer?
    private var restoredPosition: Double = 0
    private var isSeeking = false
    private var seekTargetTime: Double = 0
    
    private var currentPlaybackSessionID = UUID()
    private var pendingTrack: (track: Track, fullTrack: FullTrack)?
    private var isTransitioningTracks = false
        
    // MARK: - Dependencies
    
    private let libraryManager: LibraryManager
    private let playlistManager: PlaylistManager
    private let nowPlayingManager: NowPlayingManager
    
    // MARK: - Initialization
    
    init(libraryManager: LibraryManager, playlistManager: PlaylistManager) {
        self.libraryManager = libraryManager
        self.playlistManager = playlistManager
        self.nowPlayingManager = NowPlayingManager()
        self.audioPlayer = AudioPlayer()
        
        super.init()
        
        self.audioPlayer.delegate = self
        self.audioPlayer.volume = volume
    }
    
    deinit {
        stop()
        stopPlaybackProgressTimer()
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
        currentTime = uiState.playbackPosition
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
                    
                    Logger.info("Prepared track for restoration at position: \(position) (not playing)")
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
                
        Task {
            do {
                guard let fullTrack = try await track.fullTrack(using: libraryManager.databaseManager.dbQueue) else {
                    await MainActor.run {
                        Logger.error("""
                                Failed to fetch full track data - \
                                Title: \(track.title), \
                                Artist: \(track.artist), \
                                Album: \(track.album), \
                                Path: \(track.url.path), \
                                Format: \(track.url.pathExtension.uppercased()), \
                                Duration: \(track.duration)s
                                """)
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
        if isPlaying {
            audioPlayer.pause()
            stopPlaybackProgressTimer()
            stopStateSaveTimer()
        } else {
            if currentFullTrack != nil && (audioPlayer.state == .ready || audioPlayer.state == .stopped) {
                if let fullTrack = currentFullTrack {
                    restartPlayback(from: fullTrack)
                }
            } else {
                audioPlayer.resume()
            }
            startPlaybackProgressTimer()
            startStateSaveTimer()
        }
    }
    
    func stop() {
        currentPlaybackSessionID = UUID()

        audioPlayer.stop()
        currentTrack = nil
        currentFullTrack = nil
        pendingTrack = nil
        currentTime = 0
        restoredPosition = 0
        isTransitioningTracks = false
        stopPlaybackProgressTimer()
        stopStateSaveTimer()
        Logger.info("Playback stopped")
    }
    
    func stopGracefully() {
        currentPlaybackSessionID = UUID()
        
        if audioPlayer.state == .playing || audioPlayer.state == .paused {
            audioPlayer.stop()
        }
        
        currentTrack = nil
        currentFullTrack = nil
        pendingTrack = nil
        isPlaying = false
        currentTime = 0
        isTransitioningTracks = false
        stopPlaybackProgressTimer()
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
    
    // MARK: - Audio Effects

    func setStereoWidening(enabled: Bool) {
        audioPlayer.setStereoWidening(enabled: enabled)
    }

    func applyEQ(preset: String) {
        audioPlayer.applyEQ(preset: preset)
    }

    func applyEQ(gains: [Float]) {
        audioPlayer.applyEQ(gains: gains)
    }
    
    // MARK: - Private Methods
    
    private func startPlayback(of fullTrack: FullTrack, lightweightTrack: Track) {
        let sessionID = UUID()
        currentPlaybackSessionID = sessionID
        
        isTransitioningTracks = true
        pendingTrack = (track: lightweightTrack, fullTrack: fullTrack)
        
        if audioPlayer.state != .stopped && audioPlayer.state != .ready {
            audioPlayer.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                guard self.currentPlaybackSessionID == sessionID else {
                    Logger.info("Session invalidated, skipping playback")
                    return
                }
                self.performPlayback()
            }
        } else {
            performPlayback()
        }
    }
    
    private func performPlayback() {
        guard let pending = pendingTrack else { return }
        
        currentTrack = pending.track
        currentFullTrack = pending.fullTrack
        pendingTrack = nil
        
        currentTime = 0
        restoredPosition = 0
        
        isTransitioningTracks = false
        
        audioPlayer.play(url: pending.fullTrack.url)
        
        isPlaying = true
        
        startPlaybackProgressTimer()
        startStateSaveTimer()
        
        nowPlayingManager.updateNowPlayingInfo(
            track: pending.track,
            currentTime: 0,
            isPlaying: true
        )
        
        Logger.info("Started playing: \(pending.track.title)")
    }
    
    // MARK: - Private Helpers
    
    private func startPlaybackProgressTimer() {
        stopPlaybackProgressTimer()
        
        playbackProgressTimer = Timer.scheduledTimer(withTimeInterval: TimeConstants.playbackProgressTimerDuration, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.isPlaying else { return }
            
            // Don't update time while seeking
            if !self.isSeeking {
                let newTime = self.audioPlayer.progress
                self.currentTime = newTime
                
                if let track = self.currentTrack {
                    self.nowPlayingManager.updateNowPlayingInfo(
                        track: track,
                        currentTime: newTime,
                        isPlaying: true
                    )
                }
            }
        }
        
        playbackProgressTimer?.tolerance = 1.0
    }
    
    private func stopPlaybackProgressTimer() {
        playbackProgressTimer?.invalidate()
        playbackProgressTimer = nil
    }
    
    private func startStateSaveTimer() {
        stopStateSaveTimer()
        
        stateSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.isPlaying && self.currentTrack != nil {
                NotificationCenter.default.post(
                    name: NSNotification.Name("SavePlaybackState"),
                    object: nil,
                    userInfo: ["calledFromStateTimer": true]
                )
            }
        }
        
        stateSaveTimer?.tolerance = 5.0
    }
    
    private func stopStateSaveTimer() {
        stateSaveTimer?.invalidate()
        stateSaveTimer = nil
    }
    
    private func restartPlayback(from fullTrack: FullTrack) {
        let targetPosition = restoredPosition > 0 ? restoredPosition : currentTime
        
        audioPlayer.play(url: fullTrack.url, startPaused: true)
        
        if targetPosition > 0 {
            audioPlayer.seek(to: targetPosition)
        }
        
        audioPlayer.resume()
        
        restoredPosition = 0
    }
}

// MARK: - AudioPlayerDelegate

extension PlaybackManager: AudioPlayerDelegate {
    func audioPlayerDidStartPlaying(player: AudioPlayer, with entryId: AudioEntryId) {
        DispatchQueue.main.async {
            self.isTransitioningTracks = false
            
            if !self.isPlaying {
                self.isPlaying = true
            }
            
            Logger.info("Track started playing: \(entryId.id)")
        }
    }
    
    func audioPlayerStateChanged(player: AudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState) {
        DispatchQueue.main.async {
            if self.isTransitioningTracks && newState != .playing {
                return
            }
            
            switch newState {
            case .playing:
                self.isTransitioningTracks = false
                if !self.isPlaying {
                    self.isPlaying = true
                }
            case .paused:
                if self.isPlaying {
                    self.isPlaying = false
                }
            case .stopped:
                if self.pendingTrack == nil && self.isPlaying {
                    self.isPlaying = false
                }
            case .bufferring, .ready, .running:
                break
            case .error:
                self.isPlaying = false
                self.isTransitioningTracks = false
                Logger.error("AudioPlayer entered error state")
            case .disposed:
                self.isPlaying = false
                self.isTransitioningTracks = false
            }
            
            if newState == .playing || newState == .paused || newState == .stopped || newState == .error {
                Logger.info("Player state transition: \(previous) → \(newState)")
            }
        }
    }
    
    func audioPlayerDidFinishPlaying(
        player: AudioPlayer,
        entryId: AudioEntryId,
        stopReason: AudioPlayerStopReason,
        progress: Double,
        duration: Double
    ) {
        DispatchQueue.main.async {
            if self.isTransitioningTracks || self.pendingTrack != nil {
                Logger.info("Ignoring finish - transitioning or pending track exists")
                return
            }
            
            guard self.currentTrack != nil else {
                Logger.info("Ignoring finish - no current track")
                return
            }
            
            if stopReason == .eof || stopReason == .error {
                Logger.info("Track finished (reason: \(stopReason))")
            }
            
            switch stopReason {
            case .eof:
                if self.gaplessPlayback {
                    self.playlistManager.playNextTrack()
                } else {
                    self.playlistManager.handleTrackCompletion()
                }
            case .error:
                NotificationManager.shared.addMessage(.error, "Playback error occurred")
                self.isPlaying = false
                self.stopPlaybackProgressTimer()
                self.stopStateSaveTimer()
            case .userAction, .disposed, .none:
                if !self.isTransitioningTracks {
                    self.isPlaying = false
                    self.stopPlaybackProgressTimer()
                    self.stopStateSaveTimer()
                }
            }
        }
    }
    
    func audioPlayerUnexpectedError(player: AudioPlayer, error: AudioPlayerError) {
        DispatchQueue.main.async {
            Logger.error("AudioPlayer unexpected error: \(error)")
            NotificationManager.shared.addMessage(.error, "Playback error: \(error.localizedDescription)")
            self.isPlaying = false
            self.isTransitioningTracks = false
            self.pendingTrack = nil
        }
    }
}
