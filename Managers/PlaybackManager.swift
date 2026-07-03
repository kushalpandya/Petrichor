//
// PlaybackManager class
//
// This class handles track playback coordination with PlaybackEngine,
// including database updates, state persistence, and integration with
// PlaylistManager and NowPlayingManager.
//

import AVFoundation
import Combine
import Foundation

class PlaybackManager: NSObject, ObservableObject {
    let playbackProgressState = PlaybackProgressState()
    
    private var scrobbleManager: ScrobbleManager? {
        AppCoordinator.shared?.scrobbleManager
    }

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
    // The real-time lyrics display need this to get the current time.
    // We can not use the currentTime because it is a computed property
    @Published var volume: Float = 0.7 {
        didSet {
            audioPlayer.volume = volume
        }
    }
    @Published var restoredUITrack: Track?

    // MARK: - Computed Properties
    
    /// Alias for currentTime for backwards compatibility
    var actualCurrentTime: Double {
        currentTime
    }

    // MARK: - Private Properties
    
    private let audioPlayer: PlaybackEngine
    private var currentFullTrack: FullTrack?
    private var progressUpdateTimer: DispatchSourceTimer?
    private var fineProgressSampling = false
    // Reference count of views requesting fine sampling (e.g. main-window and
    // mini-player lyrics can be visible at once); sampling stays fine while > 0.
    private var fineSamplingConsumers = 0
    private var lastNowPlayingUpdate: TimeInterval = 0
    private var stateSaveTimer: Timer?
    private var restoredPosition: Double = 0

    /// Position to seek to and resume from once a restored track settles in
    /// `.paused` (see `audioPlayerStateChanged`). Deferring to that transition
    /// instead of a fixed delay ensures the asset is open before the resume lands,
    /// avoiding the stuck-paused race on the async Crescendo backend. Carries the
    /// entry identity so a normal user-pause never trips the restore.
    private var pendingRestoreResume: (entryId: AudioEntryId, position: Double)?

    /// Play pressed before the restored track finished loading; honored by
    /// `prepareTrackForRestoration` once the track lands.
    private var pendingPlayOnRestore = false

    // MARK: - Gapless lookahead (Crescendo path)

    /// Identity of the track currently loaded in the engine.
    private var currentEntryId: AudioEntryId?
    /// Maps engine entry id -> the track it plays, so a finish can credit the track
    /// that actually ended even after a gapless advance promoted the next one.
    private var trackForEntry: [String: Track] = [:]
    /// The pre-decoded next track (the "+1") primed into a gapless engine, or nil.
    private var pendingNext: PendingNext?
    /// Set when the primed next track was rejected by the engine. On EOF, fall back
    /// to app-driven completion instead of waiting for a gapless start callback.
    private var pendingNextWasSkipped = false
    private var queueObservers: Set<AnyCancellable> = []

    private struct PendingNext {
        let entryId: AudioEntryId
        let track: Track
        let index: Int
        var fullTrack: FullTrack?
    }
    
    // MARK: - Dependencies
    
    private let libraryManager: LibraryManager
    private let playlistManager: PlaylistManager
    // The single Petrichor-side Now Playing owner (info tile + remote commands)
    // for both engines. For 1.6, Crescendo publishes neither (NowPlayingManager
    // owns the tile so the restore-resume anchor stays correct); Crescendo takes
    // over Now Playing in 1.7 when SFB is removed.
    private let nowPlayingManager: NowPlayingManager
    
    // MARK: - Initialization
    
    init(libraryManager: LibraryManager, playlistManager: PlaylistManager) {
        self.libraryManager = libraryManager
        self.playlistManager = playlistManager
        self.nowPlayingManager = NowPlayingManager()
        self.audioPlayer = PlaybackEngine()
        
        super.init()
        
        self.audioPlayer.delegate = self
        self.audioPlayer.volume = volume
        
        startProgressUpdateTimer()
        restoreAudioEffectsSettings()
        observeQueueForGaplessLookahead()
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
        tempTrack.albumArtworkData = uiState.artworkData
        tempTrack.duration = uiState.trackDuration
        
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
                        self.abandonPendingPlayOnRestore()
                    }
                    return
                }

                await MainActor.run {
                    self.currentTrack = track
                    self.currentFullTrack = fullTrack
                    self.restoredPosition = position
                    self.currentTime = position

                    if self.pendingPlayOnRestore {
                        // Play was pressed while this fetch was in flight; honor it now
                        self.pendingPlayOnRestore = false
                        self.startPlayback(of: fullTrack, lightweightTrack: track)
                    } else {
                        self.isPlaying = false
                        self.nowPlayingManager.updateNowPlayingInfo(
                            track: track,
                            currentTime: position,
                            isPlaying: false
                        )
                    }

                    Logger.info("Prepared track for restoration at position: \(position)")
                }
            } catch {
                await MainActor.run {
                    Logger.error("Failed to prepare track for restoration: \(error)")
                    self.abandonPendingPlayOnRestore()
                }
            }
        }
    }

    /// Resets a latched play when the restore it was waiting on failed.
    private func abandonPendingPlayOnRestore() {
        guard pendingPlayOnRestore else { return }
        pendingPlayOnRestore = false
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    // MARK: - Playback Controls
    
    func playTrack(_ track: Track) {
        restoredUITrack = nil
        restoredPosition = 0
        
        guard FileManager.default.fileExists(atPath: track.url.path) else {
            Logger.warning("Track file does not exist: \(track.url.path)")
            NotificationManager.shared.addMessage(.error, String(localized: "Cannot play '\(track.title)': File not found"))
            
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
                        NotificationManager.shared.addMessage(.error, String(localized: "Cannot play track - missing data"))
                    }
                    return
                }
                
                await MainActor.run {
                    self.startPlayback(of: fullTrack, lightweightTrack: track)
                }
            } catch {
                await MainActor.run {
                    Logger.error("Failed to fetch track data: \(error)")
                    NotificationManager.shared.addMessage(.error, String(localized: "Failed to load track for playback"))
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
            // Pausing while a restored track is still loading cancels the latched play.
            pendingPlayOnRestore = false
            audioPlayer.pause()
            isPlaying = false
            stopStateSaveTimer()
        } else {
            if let fullTrack = currentFullTrack, let track = currentTrack, audioPlayer.state != .paused {
                startPlayback(of: fullTrack, lightweightTrack: track)
            } else if currentFullTrack == nil, currentTrack != nil {
                // Restored track still loading; resume() would no-op, so latch the intent
                pendingPlayOnRestore = true
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
        haltPlayback()
        restoredPosition = 0
        Logger.info("Playback stopped")
    }

    /// Quiets the engine for a clean quit. Save state BEFORE calling: audioPlayer.stop()
    /// queues a .userAction finish that zeroes currentTime, so a later save may persist
    /// position 0. Track state is left intact so a stray later save can't wipe it entirely.
    func stopGracefully() {
        audioPlayer.stop()
        isPlaying = false
        pendingPlayOnRestore = false
        stopStateSaveTimer()
        Logger.info("Playback stopped gracefully")
    }

    /// The shared teardown behind both stop flavors.
    private func haltPlayback() {
        audioPlayer.stop()
        currentTrack = nil
        currentFullTrack = nil
        currentEntryId = nil
        pendingNext = nil
        pendingNextWasSkipped = false
        currentTime = 0
        isPlaying = false
        pendingPlayOnRestore = false
        stopStateSaveTimer()
    }
    
    func seekTo(time: Double) {
        // Clamp seek position to the engine's actual duration to prevent seek
        // errors when the DB-stored duration differs from the actual track
        // duration, this happens in edge-cases for MP3, although it is fixed
        // in MetadataEngine so hard refresh on library should resolve this.
        let engineDuration = audioPlayer.duration
        let clampedTime = engineDuration > 0 ? min(time, engineDuration) : time
        audioPlayer.seek(to: clampedTime)
        currentTime = clampedTime
        restoredPosition = clampedTime
        
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

    /// Rebuilds the playback engine for the currently selected backend (used when
    /// the user switches engines in Settings). Playback is halted, but the loaded
    /// track, queue, and position are kept so the progress bar stays put and the
    /// user can resume from the same spot on the new engine by pressing play.
    func reloadPlaybackEngine() {
        let resumePosition = currentTime

        audioPlayer.reload()
        isPlaying = false
        pendingPlayOnRestore = false
        // The freshly built backend has nothing primed; the next play re-primes.
        pendingNext = nil
        pendingNextWasSkipped = false
        currentEntryId = nil
        stopStateSaveTimer()

        // The new backend starts clean, so re-apply volume and audio effects.
        audioPlayer.volume = volume
        restoreAudioEffectsSettings()

        // Keep the current track loaded and the bar where it was; startPlayback
        // reads restoredPosition to continue from here on the next play.
        if currentTrack != nil {
            restoredPosition = resumePosition
            currentTime = resumePosition
            updateNowPlayingInfo()
        }

        Logger.info("Playback engine reloaded for backend: \(MediaBackend.current)")
    }

    /// Wires the system remote command center (lock screen / Control Center) to
    /// this manager. PlaybackManager owns the single Petrichor-side Now Playing
    /// path for both engines in 1.6.
    func connectRemoteCommandCenter() {
        nowPlayingManager.connectRemoteCommandCenter(
            audioPlayer: self,
            playlistManager: playlistManager
        )
    }
    
    // MARK: - Audio Effects

    /// Enable or disable stereo widening effect
    /// - Parameter enabled: true to enable, false to disable
    func setStereoWidening(enabled: Bool) {
        audioPlayer.setStereoWidening(enabled: enabled)
        UserDefaults.standard.set(enabled, forKey: "stereoWideningEnabled")
        Logger.info("Stereo widening \(enabled ? "enabled" : "disabled") via PlaybackManager")
    }

    /// Check if stereo widening is currently enabled
    /// - Returns: true if enabled, false otherwise
    func isStereoWideningEnabled() -> Bool {
        audioPlayer.isStereoWideningEnabled()
    }

    /// Enable or disable the equalizer
    /// - Parameter enabled: true to enable, false to disable
    func setEQEnabled(_ enabled: Bool) {
        audioPlayer.setEQEnabled(enabled)
        UserDefaults.standard.set(enabled, forKey: "eqEnabled")
        Logger.info("EQ \(enabled ? "enabled" : "disabled") via PlaybackManager")
    }

    /// Check if EQ is currently enabled
    /// - Returns: true if enabled, false otherwise
    func isEQEnabled() -> Bool {
        audioPlayer.isEQEnabled()
    }

    /// Apply an EQ preset
    /// - Parameter preset: The EqualizerPreset to apply
    func applyEQPreset(_ preset: EqualizerPreset) {
        audioPlayer.applyEQPreset(preset)
        if preset != .flat && !audioPlayer.isEQEnabled() {
            setEQEnabled(true)
        }
        UserDefaults.standard.set(preset.rawValue, forKey: "eqPreset")
        Logger.info("Applied EQ preset: \(preset.displayName) via PlaybackManager")
    }

    /// Apply custom EQ gains
    /// - Parameter gains: Array of 10 Float values in dB
    func applyEQCustom(gains: [Float]) {
        guard gains.count == 10 else {
            Logger.warning("Invalid EQ gains array size: \(gains.count), expected 10")
            return
        }
        
        audioPlayer.applyEQCustom(gains: gains)
        if !audioPlayer.isEQEnabled() {
            setEQEnabled(true)
        }
        UserDefaults.standard.set(gains, forKey: "customEQGains")
        UserDefaults.standard.set("custom", forKey: "eqPreset")
        Logger.info("Applied custom EQ gains via PlaybackManager")
    }
    
    /// Set the preamp gain
    /// - Parameter gain: Gain value in dB, range -12 to +12
    func setPreamp(_ gain: Float) {
        audioPlayer.setPreamp(gain)
        UserDefaults.standard.set(gain, forKey: "preampGain")
        Logger.info("Preamp set to \(gain) dB via PlaybackManager")
    }

    /// Get the current preamp gain
    /// - Returns: Current preamp gain in dB
    func getPreamp() -> Float {
        audioPlayer.getPreamp()
    }
    
    // MARK: - Private Methods
    
    private func startPlayback(of fullTrack: FullTrack, lightweightTrack: Track) {
        // Any real play supersedes a play latched during the restore window.
        pendingPlayOnRestore = false
        currentTrack = lightweightTrack
        currentFullTrack = fullTrack

        // Fresh identity for this play; play(url:) replaces the engine's queue, so
        // any previously primed gapless next is gone.
        let entryId = AudioEntryId(id: UUID().uuidString)
        currentEntryId = entryId
        // Fresh play replaces the engine queue, so prior entries are gone.
        trackForEntry = [entryId.id: lightweightTrack]
        pendingNext = nil
        pendingNextWasSkipped = false

        let seekToPosition = restoredPosition
        restoredPosition = 0

        if seekToPosition > 0 {
            // Load paused and defer the seek+resume to the `.paused` transition
            // this produces (see audioPlayerStateChanged): that signal fires only
            // once the engine has the asset open, so the resume can't race the
            // engine's async loading. Set the marker before play() because the
            // `.paused` callback can arrive synchronously on some backends.
            pendingRestoreResume = (entryId, seekToPosition)
            currentTime = seekToPosition
            audioPlayer.play(url: fullTrack.url, entryId: entryId, startPaused: true)
        } else {
            currentTime = 0
            audioPlayer.play(url: fullTrack.url, entryId: entryId, startPaused: false)
            Logger.info("Started playback: \(lightweightTrack.title)")
        }

        startStateSaveTimer()
        updateNowPlayingInfo()
        scrobbleManager?.trackStarted(lightweightTrack)
        // The gapless next is primed from `audioPlayerDidStartPlaying`, once the
        // engine confirms this track is actually playing - priming here (before
        // the engine's async play starts) is too early: the successor can't be
        // pre-decoded against a not-yet-established current.
    }

    // MARK: - Gapless lookahead

    /// Subscribes to queue/repeat/shuffle changes so the engine's gapless next
    /// entry is re-derived whenever what plays next could change. The current
    /// track keeps playing; only the lookahead is swapped. `primeNextTrack` is a
    /// no-op on non-gapless engines, so this is safe to wire unconditionally
    /// (the active engine can change at runtime via the toggle).
    private func observeQueueForGaplessLookahead() {
        Publishers.Merge3(
            playlistManager.$currentQueue.map { _ in () },
            playlistManager.$repeatMode.map { _ in () },
            playlistManager.$isShuffleEnabled.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            guard let self, self.currentTrack != nil else { return }
            // Only re-prime while a track is actually loaded in the engine. During
            // the initial start the queue is set before the engine is playing, and
            // priming then inserts into a not-yet-established session.
            let state = self.audioPlayer.state
            guard state == .playing || state == .paused else { return }
            self.primeNextTrack()
        }
        .store(in: &queueObservers)
    }

    /// Primes (or re-primes) the engine's gapless next entry from the queue.
    /// No-op unless the active engine supports a gapless lookahead.
    private func primeNextTrack() {
        guard audioPlayer.supportsGaplessQueue else { return }

        guard let next = playlistManager.peekNextTrack() else {
            audioPlayer.clearNextTrack()
            pendingNext = nil
            pendingNextWasSkipped = false
            return
        }

        // Already primed for this exact upcoming entry - avoid a redundant swap
        // (redundant command-center/engine writes are wasteful).
        if let pending = pendingNext, pending.track.url == next.track.url, pending.index == next.index {
            return
        }

        let entryId = AudioEntryId(id: UUID().uuidString)
        pendingNext = PendingNext(entryId: entryId, track: next.track, index: next.index, fullTrack: nil)
        pendingNextWasSkipped = false
        audioPlayer.setNextTrack(url: next.track.url, entryId: entryId)
        Logger.info("Primed gapless next: \(next.track.title)")

        // Pre-fetch the full track so a gapless advance has it ready immediately.
        Task { [weak self] in
            guard let self else { return }
            let full = try? await next.track.fullTrack(using: self.libraryManager.databaseManager.dbQueue)
            await MainActor.run {
                if self.pendingNext?.entryId == entryId {
                    self.pendingNext?.fullTrack = full
                }
            }
        }
    }

    /// Promotes the primed next track to current after the engine gaplessly
    /// advanced into it. The audio is already playing; this just syncs Petrichor's
    /// queue state, bookkeeping, and re-primes the following track.
    private func handleGaplessAdvance(to pending: PendingNext) {
        restoredUITrack = nil
        currentTrack = pending.track
        currentFullTrack = pending.fullTrack
        currentEntryId = pending.entryId
        // Keep the outgoing entry so its (possibly late) finish can still credit it.
        trackForEntry[pending.entryId.id] = pending.track
        playlistManager.advanceQueueIndex(to: pending.index)
        currentTime = 0
        isPlaying = true
        pendingNext = nil
        pendingNextWasSkipped = false

        scrobbleManager?.trackStarted(pending.track)
        updateNowPlayingInfo()
        Logger.info("Gapless advance to: \(pending.track.title)")

        // If the pre-fetch didn't finish in time, load it now for pause/resume + UI.
        if currentFullTrack == nil {
            let track = pending.track
            Task { [weak self] in
                guard let self else { return }
                let full = try? await track.fullTrack(using: self.libraryManager.databaseManager.dbQueue)
                await MainActor.run {
                    if self.currentTrack?.url == track.url { self.currentFullTrack = full }
                }
            }
        }

        primeNextTrack()
    }
    
    private func startProgressUpdateTimer() {
        progressUpdateTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // 1s by default; 0.5s only while the lyrics view is open (it needs finer
        // line timing). Sampling faster than 1s otherwise just doubles UI
        // re-renders for no benefit, so it's scoped to when lyrics are visible.
        let interval: DispatchTimeInterval = fineProgressSampling ? .milliseconds(500) : .seconds(1)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(50))

        timer.setEventHandler { [weak self] in
            // Gate on the engine's live state, not the cached isPlaying flag, which
            // can be briefly stale and freeze the bar at 0.
            guard let self = self, self.audioPlayer.state == .playing else { return }
            self.currentTime = self.audioPlayer.currentPlaybackProgress
            // Refresh the system Now Playing tile at ~1s regardless of sampling
            // rate - it extrapolates elapsed between updates from the rate anchor,
            // so a higher rate is wasted work (and an artwork re-decode on SFB).
            let now = Date().timeIntervalSinceReferenceDate
            if now - self.lastNowPlayingUpdate >= 1.0 {
                self.lastNowPlayingUpdate = now
                self.updateNowPlayingInfo()
            }
        }
        
        timer.resume()
        progressUpdateTimer = timer
    }

    /// Switches the progress sampler to 0.5s while a lyrics view is visible (for
    /// tight line highlighting) and back to 1s otherwise (minimum CPU during normal
    /// listening). Reference-counted so multiple lyrics views (main window +
    /// mini player) don't disable sampling out from under each other; called by
    /// each lyrics view on appear (`true`) / disappear (`false`).
    func setFineProgressSampling(_ enabled: Bool) {
        if enabled {
            fineSamplingConsumers += 1
        } else {
            fineSamplingConsumers = max(0, fineSamplingConsumers - 1)
        }

        let shouldSampleFine = fineSamplingConsumers > 0
        guard shouldSampleFine != fineProgressSampling else { return }
        fineProgressSampling = shouldSampleFine
        startProgressUpdateTimer()
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
    
    /// Restore audio effects settings from UserDefaults
    private func restoreAudioEffectsSettings() {
        // Restore stereo widening
        let stereoWideningEnabled = UserDefaults.standard.bool(forKey: "stereoWideningEnabled")
        if stereoWideningEnabled {
            audioPlayer.setStereoWidening(enabled: true)
            Logger.info("Restored stereo widening: enabled")
        }
        
        // Restore EQ enabled state
        let eqEnabled = UserDefaults.standard.bool(forKey: "eqEnabled")
        if eqEnabled {
            audioPlayer.setEQEnabled(true)
            Logger.info("Restored EQ: enabled")
        }
        
        // Restore EQ preset or custom gains
        if let presetRawValue = UserDefaults.standard.string(forKey: "eqPreset") {
            if presetRawValue == "custom" {
                // Restore custom gains
                if let customGains = UserDefaults.standard.array(forKey: "customEQGains") as? [Float],
                   customGains.count == 10 {
                    audioPlayer.applyEQCustom(gains: customGains)
                    Logger.info("Restored custom EQ gains")
                }
            } else {
                // Restore preset
                if let preset = EqualizerPreset(rawValue: presetRawValue) {
                    audioPlayer.applyEQPreset(preset)
                    Logger.info("Restored EQ preset: \(preset.displayName)")
                }
            }
        }
        
        // Restore preamp gain
        if UserDefaults.standard.object(forKey: "preampGain") != nil {
            let preampGain = UserDefaults.standard.float(forKey: "preampGain")
            audioPlayer.setPreamp(preampGain)
            Logger.info("Restored preamp: \(preampGain) dB")
        }
    }
}

// MARK: - AudioPlayerDelegate

extension PlaybackManager: AudioPlayerDelegate {
    func audioPlayerDidStartPlaying(player: PlaybackEngine, with entryId: AudioEntryId) {
        DispatchQueue.main.async {
            // A gapless engine fires this for the primed next track when it
            // self-advances; promote it instead of treating it as a fresh start.
            if let pending = self.pendingNext, pending.entryId == entryId {
                self.handleGaplessAdvance(to: pending)
            } else {
                self.isPlaying = true
            }
            Logger.info("Track started playing: \(entryId.id)")
        }
    }
    
    func audioPlayerStateChanged(player: PlaybackEngine, with newState: AudioPlayerState, previous: AudioPlayerState) {
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

            // Finish a deferred restore-resume: the startPaused load has now
            // settled in `.paused`, so the asset is open and the seek+resume is
            // safe. Guarded by entry identity so an unrelated pause never trips it.
            if newState == .paused,
               let pending = self.pendingRestoreResume,
               pending.entryId == self.currentEntryId {
                self.pendingRestoreResume = nil
                if self.audioPlayer.seek(to: pending.position) {
                    self.currentTime = pending.position
                    self.audioPlayer.resume()
                    Logger.info("Resumed restored playback from \(pending.position)s")
                } else if let url = self.currentFullTrack?.url {
                    Logger.warning("Restore seek failed, starting from beginning")
                    self.currentTime = 0
                    self.audioPlayer.play(url: url, entryId: pending.entryId, startPaused: false)
                }
            }

            // Prime the gapless next once the engine is actually playing. This
            // fires for every start path - fresh play, restored resume (which
            // goes startPaused -> seek -> resume), and resume-from-pause - so
            // priming is reliable where `didStartPlaying` alone was not.
            // A gapless advance keeps the state at .playing (no transition here),
            // so it re-primes via handleGaplessAdvance instead.
            if newState == .playing {
                self.primeNextTrack()
            }

            Logger.info("Player state changed: \(previous) → \(newState)")
        }
    }
    
    func audioPlayerDidFinishPlaying(
        player: PlaybackEngine,
        entryId: AudioEntryId,
        stopReason: AudioPlayerStopReason,
        progress: Double,
        duration: Double
    ) {
        DispatchQueue.main.async {
            // Credit the track that actually finished, resolved by entry id: on a
            // gapless advance currentTrack may already be the next track.
            let finishedTrack = self.trackForEntry.removeValue(forKey: entryId.id)

            guard self.currentTrack != nil else {
                Logger.info("Ignoring finish - no current track")
                return
            }

            Logger.info("Track finished (reason: \(stopReason))")

            if stopReason == .eof, let finishedTrack {
                self.playlistManager.incrementPlayCount(for: finishedTrack)
                self.scrobbleManager?.trackFinished(finishedTrack)

                Logger.info("Track completed naturally, updating play count, last played date, and scrobbling it if configured")
            }

            // Only tear down current playback when the finished entry is still
            // current; a stale finish that raced ahead of a gapless advance must not
            // flip isPlaying false under the now-playing track (which freezes its bar).
            let finishedEntryIsCurrent = entryId == self.currentEntryId

            switch stopReason {
            case .eof:
                self.restoredPosition = 0
                if self.audioPlayer.supportsGaplessQueue {
                    // True end of queue only: nothing primed and this finish is for
                    // the current entry (not a stale one that raced the advance).
                    if self.pendingNext == nil && finishedEntryIsCurrent {
                        self.currentTime = 0
                        if self.pendingNextWasSkipped {
                            self.pendingNextWasSkipped = false
                            self.playlistManager.handleTrackCompletion()
                        } else {
                            self.isPlaying = false
                            self.stopStateSaveTimer()
                            NotificationCenter.default.post(
                                name: NSNotification.Name("SavePlaybackState"),
                                object: nil
                            )
                        }
                    }
                } else {
                    self.currentTime = 0
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
                self.currentTime = 0
                self.stopStateSaveTimer()

            case .error:
                self.currentTime = 0
                self.isPlaying = false
                Logger.error("Playback finished with error")
                NotificationManager.shared.addMessage(.error, String(localized: "Playback error occurred"))
            }
        }
    }
    
    func audioPlayerUnexpectedError(player: PlaybackEngine, error: AudioPlayerError) {
        DispatchQueue.main.async {
            Logger.error("Audio player error: \(error.localizedDescription)")
            NotificationManager.shared.addMessage(.error, String(localized: "Playback error: \(error.localizedDescription)"))
        }
    }

    func audioPlayerDidSkipQueueEntry(player: PlaybackEngine, entryId: AudioEntryId) {
        DispatchQueue.main.async {
            guard self.pendingNext?.entryId == entryId else { return }
            Logger.warning("Gapless lookahead skipped; falling back to app-driven advance")
            self.pendingNext = nil
            self.pendingNextWasSkipped = true
        }
    }
}
