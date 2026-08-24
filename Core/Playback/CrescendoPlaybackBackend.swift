//
// CrescendoPlaybackBackend
//
// The Crescendo-backed `PlaybackBackend`. It wraps `CrescendoPlayer` and reports
// events to the `PlaybackEngine` facade. This is the only playback file that
// imports Crescendo.
//
// Concurrency: `CrescendoPlayer` and `CrescendoPlayerDelegate` are `@MainActor`,
// but `PlaybackBackend` is a synchronous, non-isolated protocol. To avoid pushing
// `@MainActor` through the whole manager graph, the backend stays non-isolated and:
//   - routes every call into the player through `onMain`, and
//   - receives delegate callbacks via a separate `@MainActor` bridge (the same
//     shape), which forwards to the backend's nonisolated `handle*` methods.
// All backend calls already happen on the main thread (UI, delegate hops, the
// .main progress timer), so `onMain` is direct in practice; the off-main branch
// is only a safety net (e.g. a teardown from `deinit`).
//

import Crescendo
import Foundation

final class CrescendoPlaybackBackend: PlaybackBackend {
    // MARK: - Backend Surface

    weak var backendDelegate: PlaybackBackendDelegate?

    var volume: Float {
        get { onMain { player.volume } }
        set { onMain { player.volume = newValue } }
    }

    var state: AudioPlayerState {
        onMain { Self.mapState(player.state) }
    }

    var currentPlaybackProgress: Double {
        onMain { player.currentTime }
    }

    var duration: Double {
        onMain { player.duration }
    }

    var currentStreamFormat: StreamFormat? {
        onMain {
            player.currentFormat.map {
                StreamFormat(
                    sampleRate: $0.sampleRate,
                    channelCount: $0.channelCount,
                    codec: $0.codec,
                    bitrate: $0.bitrate
                )
            }
        }
    }

    var currentEntryId: AudioEntryId? {
        onMain { player.currentEntryId.map { AudioEntryId(id: $0.id) } }
    }

    func playStream(url: URL, entryId: AudioEntryId) {
        onMain { player.play(streamURL: url, entryId: CrescendoEntryId(id: entryId.id)) }
    }

    var queue: [AudioEntryId] {
        onMain { player.queue.map { AudioEntryId(id: $0.id.id) } }
    }

    // Answered from the player's queue directly: building the mapped array just to
    // find one index (or read a count) allocates the whole thing per call, and these
    // run on every queue edit and every track boundary.
    func queueIndex(of entryId: AudioEntryId) -> Int? {
        onMain { player.queue.firstIndex { $0.id.id == entryId.id } }
    }

    var hasQueuedSuccessor: Bool {
        onMain { player.currentIndex.map { $0 + 1 < player.queue.count } ?? false }
    }

    // MARK: - Private Properties

    private let player: CrescendoPlayer
    private var delegateBridge: CrescendoDelegateBridge?

    // Effects state. Crescendo applies all effects as property sets, so there is
    // no graph to build; we keep the user-facing state here and push it down.
    private var eqEnabled = false
    private var currentEQGains = [Float](repeating: 0, count: 10)
    private var stereoWideningEnabled = false
    private var userPreampGain: Float = 0

    private static let flatEQGains = [Float](repeating: 0, count: 10)

    // MARK: - Initialization

    init() {
        player = onMainStatic { CrescendoPlayer() }
        onMain {
            let bridge = CrescendoDelegateBridge(owner: self)
            self.delegateBridge = bridge
            player.delegate = bridge
            // The engine owns the info tile: it anchors elapsed/duration/rate off the
            // real playback clock, which the app can only approximate.
            player.nowPlayingInfoEnabled = true
            // Commands stay app-owned: Crescendo's next/previous walk its queue in raw
            // order, ignoring Petrichor's repeat, shuffle and injected lookahead.
            player.remoteCommandsEnabled = false
            player.crossfadeCurve = .linear
            player.streamDestinationPolicy = CrescendoPlayer.publicInternetStreamDestinationPolicy
            installLogBridge()
        }
    }

    // MARK: - Playback Control

    // MARK: - Queue

    func setQueue(_ entries: [QueueEntry], startingAt index: Int, startPaused: Bool) {
        let mapped = entries.map { CrescendoQueueEntry(url: $0.url, entryId: CrescendoEntryId(id: $0.entryId.id)) }
        onMain {
            player.setQueue(mapped, startingAt: index, startPaused: startPaused)
        }
    }

    func insert(_ entry: QueueEntry, at index: Int) {
        onMain { player.insert(url: entry.url, entryId: CrescendoEntryId(id: entry.entryId.id), at: index) }
    }

    func append(_ entry: QueueEntry) {
        onMain { player.append(url: entry.url, entryId: CrescendoEntryId(id: entry.entryId.id)) }
    }

    func insertNext(_ entry: QueueEntry) {
        onMain { player.insertNext(url: entry.url, entryId: CrescendoEntryId(id: entry.entryId.id)) }
    }

    func move(from: Int, to: Int) {
        onMain { player.move(from: from, to: to) }
    }

    func removeQueueEntry(at index: Int) {
        onMain { _ = player.remove(at: index) }
    }

    func removeQueueEntry(id: AudioEntryId) {
        onMain { _ = player.remove(entryId: CrescendoEntryId(id: id.id)) }
    }

    func clearQueue() {
        onMain { player.clearQueue() }
    }

    func playQueueEntry(at index: Int, startPaused: Bool) {
        onMain { player.play(at: index, startPaused: startPaused) }
    }

    func shuffleQueue() {
        onMain { player.shuffle() }
    }

    // MARK: - Now Playing

    func setNowPlayingMetadata(_ metadata: NowPlayingMetadata?) {
        let mapped = metadata.map {
            CrescendoNowPlayingMetadata(
                title: $0.title,
                artist: $0.artist,
                albumTitle: $0.albumTitle,
                albumArtist: $0.albumArtist,
                genre: $0.genre,
                artworkData: $0.artworkData
            )
        }
        onMain { player.setNowPlayingMetadata(mapped) }
    }

    func pause() { onMain { player.pause() } }
    func resume() { onMain { player.resume() } }
    func stop() { onMain { player.stop() } }
    func togglePlayPause() { onMain { player.togglePlayPause() } }
    func releaseForIdle() { onMain { player.releaseForIdle() } }
    func resumeFromIdle() { onMain { player.resumeFromIdle() } }

    @discardableResult
    func seek(to time: Double) -> Bool {
        guard time >= 0 else { return false }
        return onMain { player.seek(to: time) }
    }

    @discardableResult
    func seekForward(_ seconds: Double) -> Bool {
        onMain { player.seekForward(seconds) }
    }

    @discardableResult
    func seekBackward(_ seconds: Double) -> Bool {
        onMain { player.seekBackward(seconds) }
    }

    // MARK: - Audio Effects

    func setStereoWidening(enabled: Bool) {
        stereoWideningEnabled = enabled
        // Crescendo uses a mid/side width (1.0 neutral); SFB used a Haas delay, so
        // the two engines sound slightly different here.
        onMain { player.stereoWidth = enabled ? 2.0 : 1.0 }
    }

    func isStereoWideningEnabled() -> Bool { stereoWideningEnabled }

    func setEQEnabled(_ enabled: Bool) {
        eqEnabled = enabled
        pushEQGains()
        pushEffectivePreamp()
    }

    func isEQEnabled() -> Bool { eqEnabled }

    func applyEQPreset(_ preset: EqualizerPreset) {
        currentEQGains = preset.gains
        pushEQGains()
        pushEffectivePreamp()
    }

    func applyEQCustom(gains: [Float]) {
        guard gains.count == 10 else {
            Logger.warning("Equalizer gains array must contain exactly 10 values, got \(gains.count)")
            return
        }
        currentEQGains = gains
        pushEQGains()
        pushEffectivePreamp()
    }

    func setPreamp(_ gain: Float) {
        userPreampGain = max(-12, min(12, gain))
        pushEffectivePreamp()
    }

    func getPreamp() -> Float { userPreampGain }

    func setCrossfadeEnabled(_ enabled: Bool) {
        onMain { player.crossfadeEnabled = enabled }
    }

    func isCrossfadeEnabled() -> Bool {
        onMain { player.crossfadeEnabled }
    }

    func setCrossfadeDuration(_ duration: TimeInterval) {
        onMain {
            player.crossfadeDuration = min(
                max(duration, CrescendoPlayer.crossfadeDurationMin),
                CrescendoPlayer.crossfadeDurationMax
            )
        }
    }

    func getCrossfadeDuration() -> TimeInterval {
        onMain { player.crossfadeDuration }
    }

    var crossfadeDurationRange: ClosedRange<TimeInterval> {
        onMain { CrescendoPlayer.crossfadeDurationMin...CrescendoPlayer.crossfadeDurationMax }
    }

    func setReplayGainMode(_ mode: ReplayGainMode) {
        onMain { player.replayGainMode = Self.mapReplayGainMode(mode) }
    }

    func getReplayGainMode() -> ReplayGainMode {
        onMain { Self.mapReplayGainMode(player.replayGainMode) }
    }

    func setReplayGainPreamp(_ decibels: Float) {
        onMain { player.replayGainPreampDB = decibels }
    }

    func getReplayGainPreamp() -> Float {
        onMain { player.replayGainPreampDB }
    }

    var replayGainPreampRange: ClosedRange<Float> {
        onMain { CrescendoPlayer.replayGainPreampRange }
    }

    // Disabled EQ is expressed as flat (all-zero) gains rather than Crescendo's
    // `effectsEnabled`, which would bypass preamp and width too.
    private func pushEQGains() {
        let gains = eqEnabled ? currentEQGains : Self.flatEQGains
        onMain { player.equalizerGains = gains }
    }

    private func pushEffectivePreamp() {
        let compensation = EqualizerHeadroomCompensation.gainOffset(
            eqEnabled: eqEnabled,
            gains: currentEQGains
        )
        onMain { player.preampGain = userPreampGain + compensation }
    }

    // MARK: - Logging bridge

    @MainActor
    private func installLogBridge() {
        player.logHandler = { record in
            let message = "[Crescendo/\(record.category.rawValue)] \(record.message)"
            switch record.level {
            case .warning: Logger.warning(message)
            case .error: Logger.error(message)
            case .fault: Logger.critical(message)
            case .debug, .info: Logger.info(message)
            @unknown default: Logger.info(message)
            }
        }
        player.logLevel = AppInfo.isDebugBuild ? .info : .warning
    }

    // MARK: - Delegate event handling (called by the @MainActor bridge)

    func handleStartPlaying(entryId: CrescendoEntryId) {
        backendDelegate?.backendDidStartPlaying(with: AudioEntryId(id: entryId.id))
    }

    func handleStateChange(
        entryId: CrescendoEntryId?,
        from oldState: CrescendoPlayerState,
        to newState: CrescendoPlayerState
    ) {
        backendDelegate?.backendStateChanged(
            entryId: entryId.map { AudioEntryId(id: $0.id) },
            with: Self.mapState(newState),
            previous: Self.mapState(oldState)
        )
    }

    func handleFinish(entryId: CrescendoEntryId, reason: CrescendoStopReason, progress: Double, duration: Double) {
        backendDelegate?.backendDidFinishPlaying(
            entryId: AudioEntryId(id: entryId.id),
            stopReason: Self.mapStopReason(reason),
            progress: progress,
            duration: duration
        )
    }

    func handleError(_ error: CrescendoError, entryId: CrescendoEntryId?) {
        backendDelegate?.backendUnexpectedError(
            entryId: entryId.map { AudioEntryId(id: $0.id) },
            error: Self.mapError(error)
        )
    }

    func handleFinishBuffering(entryId: CrescendoEntryId) {
        backendDelegate?.backendDidFinishBuffering(with: AudioEntryId(id: entryId.id))
    }

    func handleStreamMetadata(entryId: CrescendoEntryId, metadata: [String: String]) {
        backendDelegate?.backendDidReadStreamMetadata(
            entryId: AudioEntryId(id: entryId.id),
            metadata: metadata
        )
    }

    func handleSkippedEntry(entryId: CrescendoEntryId, url: URL, reason: CrescendoError) {
        Logger.warning("Crescendo skipped \(url.lastPathComponent): \(reason.localizedDescription)")
        backendDelegate?.backendDidSkipQueueEntry(entryId: AudioEntryId(id: entryId.id))
    }

    func handleAudioRouteProfile(_ profile: CrescendoAudioRouteProfile) {
        switch profile {
        case .standard:
            onMain { player.effectsEnabled = true }
            Logger.info("Audio effects restored for standard-latency output")
        case .highLatency:
            onMain { player.effectsEnabled = false }
            Logger.info("Audio effects bypassed for high-latency output")
        @unknown default:
            Logger.warning("Unrecognised audio route profile reported by Crescendo; leaving audio effects unchanged")
        }
    }

    // MARK: - Mapping

    private static func mapState(_ state: CrescendoPlayerState) -> AudioPlayerState {
        switch state {
        case .idle, .ready: return .ready
        // The stream-connect window; local files never enter it.
        case .buffering: return .buffering
        case .playing: return .playing
        case .paused: return .paused
        case .stopped: return .stopped
        @unknown default: return .ready
        }
    }

    private static func mapReplayGainMode(_ mode: ReplayGainMode) -> CrescendoReplayGainMode {
        switch mode {
        case .off: return .off
        case .track: return .track
        case .album: return .album
        case .auto: return .auto
        }
    }

    private static func mapReplayGainMode(_ mode: CrescendoReplayGainMode) -> ReplayGainMode {
        switch mode {
        case .off: return .off
        case .track: return .track
        case .album: return .album
        case .auto: return .auto
        // Reading an unrecognised mode as off is the inert answer: it makes the
        // settings toggle read as off rather than claiming a mode we can't name.
        @unknown default:
            Logger.warning("Unrecognised ReplayGain mode reported by the engine; treating as off")
            return .off
        }
    }

    private static func mapStopReason(_ reason: CrescendoStopReason) -> AudioPlayerStopReason {
        switch reason {
        case .endOfFile: return .eof
        case .userAction: return .userAction
        case .error: return .error
        // Treat an unknown future reason as a user action so it neither advances
        // the queue nor surfaces as an error.
        @unknown default: return .userAction
        }
    }

    private static func mapError(_ error: CrescendoError) -> AudioPlayerError {
        if case .streamingError(let underlying) = error,
           underlying is StreamDestinationRejected {
            return .restrictedStreamDestination
        }
        switch error {
        case .fileNotFound: return .fileNotFound
        case .unsupportedFormat: return .invalidFormat
        case .seekFailed: return .seekError
        case .invalidState: return .invalidState
        case .decoderError, .rendererError, .streamingError, .notImplemented: return .engineError(error)
        @unknown default: return .engineError(error)
        }
    }

    // MARK: - Main-actor bridging

    @inline(__always)
    private func onMain<T>(_ body: @MainActor () -> T) -> T {
        onMainStatic(body)
    }
}

// MARK: - Delegate Bridge

/// Bridges `CrescendoPlayer`'s `@MainActor` delegate callbacks to the non-isolated
/// backend. Kept separate so conforming to the `@MainActor` delegate protocol does
/// not force `@MainActor` onto the whole backend.
@MainActor
private final class CrescendoDelegateBridge: CrescendoPlayerDelegate {
    weak var owner: CrescendoPlaybackBackend?

    init(owner: CrescendoPlaybackBackend) {
        self.owner = owner
    }

    func playerDidStartPlaying(_ player: CrescendoPlayer, entryId: CrescendoEntryId) {
        owner?.handleStartPlaying(entryId: entryId)
    }

    func playerDidChangeState(
        _ player: CrescendoPlayer,
        entryId: CrescendoEntryId?,
        from oldState: CrescendoPlayerState,
        to newState: CrescendoPlayerState
    ) {
        owner?.handleStateChange(entryId: entryId, from: oldState, to: newState)
    }

    func playerDidFinishPlaying(
        _ player: CrescendoPlayer,
        entryId: CrescendoEntryId,
        reason: CrescendoStopReason,
        progress: TimeInterval,
        duration: TimeInterval
    ) {
        owner?.handleFinish(entryId: entryId, reason: reason, progress: progress, duration: duration)
    }

    func playerDidEncounterError(_ player: CrescendoPlayer, error: CrescendoError, entryId: CrescendoEntryId?) {
        owner?.handleError(error, entryId: entryId)
    }

    func playerDidFinishBuffering(_ player: CrescendoPlayer, entryId: CrescendoEntryId) {
        owner?.handleFinishBuffering(entryId: entryId)
    }

    func playerDidSkipQueueEntry(
        _ player: CrescendoPlayer,
        entryId: CrescendoEntryId,
        url: URL,
        reason: CrescendoError
    ) {
        owner?.handleSkippedEntry(entryId: entryId, url: url, reason: reason)
    }

    func playerDidReadMetadata(
        _ player: CrescendoPlayer,
        entryId: CrescendoEntryId,
        metadata: [String: String]
    ) {
        owner?.handleStreamMetadata(entryId: entryId, metadata: metadata)
    }

    func playerDidChangeAudioRouteProfile(_ player: CrescendoPlayer, profile: CrescendoAudioRouteProfile) {
        owner?.handleAudioRouteProfile(profile)
    }
}

// Runs a main-actor operation synchronously. Direct when already on the main
// thread; otherwise hops via the main queue. Lets the non-isolated backend drive
// the @MainActor CrescendoPlayer without making the whole graph @MainActor.
@inline(__always)
private func onMainStatic<T>(_ body: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated(body)
    }
    return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
}
