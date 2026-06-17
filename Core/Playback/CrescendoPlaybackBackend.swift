//
// CrescendoPlaybackBackend
//
// The Crescendo-backed `PlaybackBackend`. It wraps `CrescendoPlayer` and reports
// events to the `PlaybackEngine` facade. This is the only playback file that
// imports Crescendo.
//
// Concurrency: `CrescendoPlayer` and `CrescendoPlayerDelegate` are `@MainActor`,
// but `PlaybackBackend` is a synchronous, non-isolated protocol. To avoid pushing
// `@MainActor` through the whole manager graph (and changing the SFB path), the
// backend stays non-isolated and:
//   - routes every call into the player through `onMain`, and
//   - receives delegate callbacks via a separate `@MainActor` bridge (the same
//     shape SFB uses), which forwards to the backend's nonisolated `handle…`
//     methods.
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
            // Petrichor's NowPlayingManager owns the system tile for both engines
            // for now, so Crescendo does not publish Now Playing or take over the
            // remote commands this phase.
            player.nowPlayingInfoEnabled = false
            player.remoteCommandsEnabled = false
            installLogBridge()
        }
    }

    // MARK: - Playback Control

    func play(url: URL, startPaused: Bool) {
        onMain {
            // Match the SFB backend's entry identity (last path component) so the
            // app-facing entry id is stable across engines.
            player.play(url: url, entryId: CrescendoEntryId(id: url.lastPathComponent), startPaused: startPaused)
        }
    }

    func pause() { onMain { player.pause() } }
    func resume() { onMain { player.resume() } }
    func stop() { onMain { player.stop() } }
    func togglePlayPause() { onMain { player.togglePlayPause() } }

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
        onMain { player.stereoWidth = enabled ? 1.8 : 1.0 }
    }

    func isStereoWideningEnabled() -> Bool { stereoWideningEnabled }

    func setEQEnabled(_ enabled: Bool) {
        eqEnabled = enabled
        pushEQGains()
    }

    func isEQEnabled() -> Bool { eqEnabled }

    func applyEQPreset(_ preset: EqualizerPreset) {
        currentEQGains = preset.gains
        pushEQGains()
    }

    func applyEQCustom(gains: [Float]) {
        guard gains.count == 10 else {
            Logger.warning("Equalizer gains array must contain exactly 10 values, got \(gains.count)")
            return
        }
        currentEQGains = gains
        pushEQGains()
    }

    func setPreamp(_ gain: Float) {
        userPreampGain = max(-12, min(12, gain))
        onMain { player.preampGain = userPreampGain }
    }

    func getPreamp() -> Float { userPreampGain }

    // Disabled EQ is expressed as flat (all-zero) gains rather than Crescendo's
    // `effectsEnabled`, which would bypass preamp and width too.
    private func pushEQGains() {
        let gains = eqEnabled ? currentEQGains : Self.flatEQGains
        onMain { player.equalizerGains = gains }
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

    func handleStateChange(from oldState: CrescendoPlayerState, to newState: CrescendoPlayerState) {
        backendDelegate?.backendStateChanged(with: Self.mapState(newState), previous: Self.mapState(oldState))
    }

    func handleFinish(entryId: CrescendoEntryId, reason: CrescendoStopReason, progress: Double, duration: Double) {
        backendDelegate?.backendDidFinishPlaying(
            entryId: AudioEntryId(id: entryId.id),
            stopReason: Self.mapStopReason(reason),
            progress: progress,
            duration: duration
        )
    }

    func handleError(_ error: CrescendoError) {
        backendDelegate?.backendUnexpectedError(error: Self.mapError(error))
    }

    func handleFinishBuffering(entryId: CrescendoEntryId) {
        backendDelegate?.backendDidFinishBuffering(with: AudioEntryId(id: entryId.id))
    }

    func handleSkippedEntry(url: URL, reason: CrescendoError) {
        Logger.warning("Crescendo skipped \(url.lastPathComponent): \(reason.localizedDescription)")
    }

    // MARK: - Mapping

    private static func mapState(_ state: CrescendoPlayerState) -> AudioPlayerState {
        switch state {
        case .idle, .ready: return .ready
        case .playing: return .playing
        case .paused: return .paused
        case .stopped: return .stopped
        @unknown default: return .ready
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
/// not force `@MainActor` onto the whole backend (mirrors SFB's bridge).
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
        from oldState: CrescendoPlayerState,
        to newState: CrescendoPlayerState
    ) {
        owner?.handleStateChange(from: oldState, to: newState)
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
        owner?.handleError(error)
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
        owner?.handleSkippedEntry(url: url, reason: reason)
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
