//
// PlaybackManager class
//
// This class handles track playback coordination with PlaybackEngine,
// including database updates, state persistence, and integration with
// PlaylistManager and RemoteCommandManager.
//

import AVFoundation
import Combine
import Foundation

class PlaybackManager: NSObject, ObservableObject {
    let playbackProgressState = PlaybackProgressState()
    
    var scrobbleManager: ScrobbleManager? {
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
    
    let audioPlayer: PlaybackEngine
    var currentFullTrack: FullTrack?
    private var progressUpdateTimer: DispatchSourceTimer?
    private var fineProgressSampling = false
    // Reference count of views requesting fine sampling (e.g. main-window and
    // mini-player lyrics can be visible at once); sampling stays fine while > 0.
    private var fineSamplingConsumers = 0
    // Detects a pinned engine position (see watchProgressForFreeze).
    private let progressFreezeWatchdog = ProgressFreezeWatchdog()
    var restoredPosition: Double = 0

    /// Position to seek to and resume from once a restored track settles in
    /// `.paused` (see `audioPlayerStateChanged`). Deferring to that transition
    /// instead of a fixed delay ensures the asset is open before the resume lands,
    /// avoiding the stuck-paused race on the async Crescendo backend. Carries the
    /// entry identity so a normal user-pause never trips the restore.
    var pendingRestoreResume: (entryId: AudioEntryId, position: Double)?

    /// Play pressed before the restored track finished loading; honored by
    /// `prepareTrackForRestoration` once the track lands.
    var pendingPlayOnRestore = false

    // MARK: - Engine queue mirror

    /// Identity of the track currently loaded in the engine.
    var currentEntryId: AudioEntryId?
    /// One element per `playlistManager.currentQueue` position, same order. Engine
    /// indices are looked up through these, never assumed equal, so an injected
    /// successor can't shift them. Empty while playing something outside the queue.
    var mirror: [MirroredEntry] = []
    /// Entries the mirror doesn't own but callbacks must still be able to name: the
    /// injected repeat lookahead, and the single entry used for an off-queue track.
    /// Kept separate so a finish can never punch a hole in queue order.
    var unmirroredTracks: [String: Track] = [:]
    /// A successor injected because repeat makes it differ from the queue's natural
    /// order. Not a queue member until it starts, at which point it takes over the
    /// position it stands in for (see `absorbInjectedEntry`).
    var injectedNext: InjectedNext?
    var queueObservers: Set<AnyCancellable> = []

    struct MirroredEntry {
        let entryId: AudioEntryId
        let track: Track
    }

    struct InjectedNext {
        let entryId: AudioEntryId
        let track: Track
        /// The `currentQueue` position this entry occupies once it starts.
        let standsInFor: Int
    }
    
    // MARK: - Dependencies
    
    let libraryManager: LibraryManager
    let playlistManager: PlaylistManager
    // Transport commands only; the engine publishes the Now Playing info tile.
    private let remoteCommandManager: RemoteCommandManager

    // MARK: - Initialization

    init(libraryManager: LibraryManager, playlistManager: PlaylistManager) {
        self.libraryManager = libraryManager
        self.playlistManager = playlistManager
        self.remoteCommandManager = RemoteCommandManager()
        self.audioPlayer = PlaybackEngine()
        
        super.init()
        
        self.audioPlayer.delegate = self
        self.audioPlayer.volume = volume
        
        startProgressUpdateTimer()
        restoreAudioEffectsSettings()
        observeRepeatModeForLookahead()
    }

    deinit {
        stop()
        stopProgressUpdateTimer()
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
    }
    
    // MARK: - Playback Controls
    
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
        } else if audioPlayer.state == .paused {
            // A loaded, paused session always just resumes. Checked first because the
            // full track is fetched asynchronously after every advance and jump, so it
            // is briefly nil for a track that is perfectly resumable.
            audioPlayer.resume()
            isPlaying = true
        } else if let fullTrack = currentFullTrack, let track = currentTrack {
            startPlayback(of: fullTrack, lightweightTrack: track)
        } else if currentTrack != nil {
            // Restored track still loading; resume() would no-op, so latch the intent
            pendingPlayOnRestore = true
            isPlaying = true
        } else {
            audioPlayer.resume()
            isPlaying = true
        }
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
        Logger.info("Playback stopped gracefully")
    }

    /// The shared teardown behind both stop flavors.
    private func haltPlayback() {
        audioPlayer.stop()
        currentTrack = nil
        currentFullTrack = nil
        currentEntryId = nil
        mirror = []
        unmirroredTracks = [:]
        injectedNext = nil
        currentTime = 0
        isPlaying = false
        pendingPlayOnRestore = false
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

        // The engine re-anchors the Now Playing tile on its own seek.
    }

    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
    }

    /// Feeds the engine the metadata for its system Now Playing tile. Called only
    /// when the engine adopts a new entry; it keeps elapsed and rate current itself.
    func publishNowPlayingMetadata(for track: Track) {
        audioPlayer.setNowPlayingMetadata(
            NowPlayingMetadata(
                title: track.title,
                artist: track.artist,
                albumTitle: track.album,
                albumArtist: track.albumArtist,
                genre: track.genre,
                artworkData: track.artworkData
            )
        )
    }

    /// Wires the system remote command center (lock screen / Control Center) to
    /// this manager, so the transport buttons drive Petrichor's own queue.
    func connectRemoteCommandCenter() {
        remoteCommandManager.connectRemoteCommandCenter(
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

    /// Enable or disable crossfading between tracks
    /// - Parameter enabled: true to fade between tracks, false for a plain gapless join
    func setCrossfadeEnabled(_ enabled: Bool) {
        audioPlayer.setCrossfadeEnabled(enabled)
        UserDefaults.standard.set(enabled, forKey: "crossfadeEnabled")
        Logger.info("Crossfade \(enabled ? "enabled" : "disabled") via PlaybackManager")
    }

    /// Check if crossfading is currently enabled
    /// - Returns: true if enabled, false otherwise
    func isCrossfadeEnabled() -> Bool {
        audioPlayer.isCrossfadeEnabled()
    }

    /// Set how long the fade between tracks lasts. Takes effect on the next
    /// transition; one already under way keeps the duration it started with.
    /// - Parameter duration: Fade length in seconds, clamped to `crossfadeDurationRange`
    func setCrossfadeDuration(_ duration: TimeInterval) {
        audioPlayer.setCrossfadeDuration(duration)
        let effective = audioPlayer.getCrossfadeDuration()
        UserDefaults.standard.set(effective, forKey: "crossfadeDuration")
        Logger.info("Crossfade duration set to \(effective)s via PlaybackManager")
    }

    /// Get the current crossfade duration
    /// - Returns: Fade length in seconds
    func getCrossfadeDuration() -> TimeInterval {
        audioPlayer.getCrossfadeDuration()
    }

    /// The durations the engine accepts, for the settings slider to bound itself to
    var crossfadeDurationRange: ClosedRange<TimeInterval> {
        audioPlayer.crossfadeDurationRange
    }

    /// Get the current preamp gain
    /// - Returns: Current preamp gain in dB
    func getPreamp() -> Float {
        audioPlayer.getPreamp()
    }
    
    // MARK: - Private Methods
    
    private func startPlayback(of fullTrack: FullTrack, lightweightTrack: Track) {
        // Hand the restore/watchdog position over explicitly (see startQueue's resumeAt).
        let resumeAt = restoredPosition
        restoredPosition = 0

        // A track that is in the queue starts as a queue entry, so the engine can
        // advance through the rest of the queue by itself.
        if let position = playlistManager.currentQueue.firstIndex(where: { $0.url == lightweightTrack.url }) {
            startQueue(at: position, resumeAt: resumeAt)
        } else {
            startOffQueueTrack(lightweightTrack, url: fullTrack.url, resumeAt: resumeAt)
        }
        // adoptCurrentEntry kicks off an async fetch; we already have the record.
        currentFullTrack = fullTrack
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
            let sampled = self.audioPlayer.currentPlaybackProgress
            self.currentTime = sampled
            self.watchProgressForFreeze(sampled)
            // No Now Playing work here - the engine anchors elapsed and rate itself.
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

        // Restore crossfade. Duration first: a change only reaches the transition
        // after it, so enabling before the length is in place would fade the very
        // next boundary with a stale duration.
        if UserDefaults.standard.object(forKey: "crossfadeDuration") != nil {
            let duration = UserDefaults.standard.double(forKey: "crossfadeDuration")
            audioPlayer.setCrossfadeDuration(duration)
            Logger.info("Restored crossfade duration: \(duration)s")
        }

        if UserDefaults.standard.bool(forKey: "crossfadeEnabled") {
            audioPlayer.setCrossfadeEnabled(true)
            Logger.info("Restored crossfade: enabled")
        }
    }
}

// MARK: - Progress-freeze watchdog

/// Flags when the sampled engine position stops advancing while the engine
/// still reports playing (see watchProgressForFreeze).
private final class ProgressFreezeWatchdog {
    enum Recovery {
        case none
        case reload
    }

    private static let recoveryThreshold: TimeInterval = 3.0

    private var lastSampled: Double = -1
    private var frozenSince: TimeInterval?
    private var attemptedTrackURL: URL?
    private var attempts = 0

    /// Reloads once the position stays pinned past the threshold, then stands
    /// down until progress moves or the track changes.
    func check(sampled: Double, isPlaying: Bool, trackURL: URL?) -> Recovery {
        guard sampled == lastSampled, isPlaying else {
            lastSampled = sampled
            frozenSince = nil
            attemptedTrackURL = nil
            attempts = 0
            return .none
        }

        let now = Date().timeIntervalSinceReferenceDate
        guard let frozenSince else {
            self.frozenSince = now
            return .none
        }
        guard now - frozenSince >= Self.recoveryThreshold, let trackURL else { return .none }

        if trackURL != attemptedTrackURL {
            attemptedTrackURL = trackURL
            attempts = 0
        }
        attempts += 1
        // Restart the clock so a follow-up check also waits a full threshold.
        self.frozenSince = nil

        // One reload per stuck track, then stand down to avoid a restart loop.
        return attempts == 1 ? .reload : .none
    }
}

private extension PlaybackManager {
    /// Crescendo can pin the reported position while audio keeps playing
    /// (CrescendoKit issues #4/#5). Reloading the track at the frozen position
    /// rebuilds the engine session and re-syncs audio + progress bar.
    func watchProgressForFreeze(_ sampled: Double) {
        switch progressFreezeWatchdog.check(
            sampled: sampled, isPlaying: isPlaying, trackURL: currentTrack?.url
        ) {
        case .none:
            return
        case .reload:
            guard let fullTrack = currentFullTrack, let track = currentTrack else { return }
            Logger.warning(
                "Playback progress pinned at \(sampled)s while engine reports playing; "
                    + "reloading '\(track.title)'"
            )
            restoredPosition = sampled
            startPlayback(of: fullTrack, lightweightTrack: track)
        }
    }
}

// MARK: - AudioPlayerDelegate

extension PlaybackManager: AudioPlayerDelegate {
    func audioPlayerDidStartPlaying(player: PlaybackEngine, with entryId: AudioEntryId) {
        DispatchQueue.main.async {
            if let injected = self.injectedNext, injected.entryId == entryId {
                // A repeat lookahead started; fold it into the mirror, then treat it
                // like any other engine-driven advance.
                self.absorbInjectedEntry(injected)
                self.handleEngineAdvance(to: entryId, track: injected.track)
            } else if entryId != self.currentEntryId, let track = self.track(forEntry: entryId) {
                // The engine walked to the next queue entry on its own.
                self.handleEngineAdvance(to: entryId, track: track)
            } else if let started = self.track(forEntry: entryId) {
                self.isPlaying = true
                // Adopted now, so the tile's timeline is this track's. Resolved by
                // id so a superseded load can't publish the wrong track.
                self.publishNowPlayingMetadata(for: started)
            } else {
                self.isPlaying = true
                Logger.warning("Started an entry the mirror cannot name: \(entryId.id)")
            }
            self.currentTime = self.audioPlayer.currentPlaybackProgress
            Logger.info("Track started playing: \(entryId.id)")
        }
    }
    
    func audioPlayerStateChanged(player: PlaybackEngine, with newState: AudioPlayerState, previous: AudioPlayerState) {
        DispatchQueue.main.async {
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

            // Finish a deferred restore-resume: the startPaused load has now
            // settled in `.paused`, so the asset is open and the seek+resume is
            // safe. Guarded by entry identity so an unrelated pause never trips it.
            if newState == .paused,
               let pending = self.pendingRestoreResume,
               pending.entryId == self.currentEntryId {
                self.pendingRestoreResume = nil
                // startPaused adopts without a start callback, so restored tiles
                // publish here.
                if let track = self.currentTrack {
                    self.publishNowPlayingMetadata(for: track)
                }
                if self.audioPlayer.seek(to: pending.position) {
                    self.currentTime = pending.position
                    self.audioPlayer.resume()
                    Logger.info("Resumed restored playback from \(pending.position)s")
                } else if let engineIndex = self.audioPlayer.queueIndex(of: pending.entryId) {
                    Logger.warning("Restore seek failed, starting from beginning")
                    self.currentTime = 0
                    self.audioPlayer.playQueueEntry(at: engineIndex)
                }
            }

            // Re-derive the repeat lookahead once the engine is actually playing.
            // This fires for every start path - fresh play, restored resume (which
            // goes startPaused -> seek -> resume), and resume-from-pause.
            if newState == .playing {
                self.primeRepeatLookahead()
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
            // Resolve before forgetting, and only forget entries the mirror does not
            // own - a queue member outlives its finish and can be played again.
            let finishedTrack = self.track(forEntry: entryId)
            self.unmirroredTracks.removeValue(forKey: entryId.id)

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
                // The engine walks to the next entry itself, so a finish only ends
                // playback when it has stopped and nothing is queued after the current
                // entry. A gapless advance keeps it .playing and delivers the finish
                // before the start, so the state check is what tells them apart.
                if self.audioPlayer.state != .playing, !self.engineHasSuccessor, finishedEntryIsCurrent {
                    self.currentTime = 0
                    self.isPlaying = false
                }

            case .userAction:
                self.currentTime = 0

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
            // The engine drops an entry it cannot decode and primes the one after it,
            // so the boundary stays gapless. Drop it from the app queue too: leaving
            // the row would make the two queues differ in membership, which every
            // later edit and the shuffle read-back both assume cannot happen.
            self.dropSkippedEntry(entryId)
            Logger.warning("Engine skipped an undecodable queue entry: \(entryId.id)")
            self.primeRepeatLookahead()
        }
    }

    /// Whether the engine still has an entry queued after the current one - either a
    /// natural successor or an injected repeat lookahead.
    private var engineHasSuccessor: Bool {
        injectedNext != nil || audioPlayer.hasQueuedSuccessor
    }
}
