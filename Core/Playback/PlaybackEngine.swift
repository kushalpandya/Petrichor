//
// PlaybackEngine
//
// The single app-facing playback object. It owns one concrete `PlaybackBackend`
// (SFBAudioEngine or Crescendo) and is the only object that calls
// `AudioPlayerDelegate`. Selecting or removing a backend is a change to this file
// plus the backend files, and call sites stay untouched.
//

import Foundation

// MARK: - Audio Player State

public enum AudioPlayerState {
    case ready
    case playing
    case paused
    case stopped
}

// MARK: - Audio Player Stop Reason

public enum AudioPlayerStopReason {
    case eof
    case userAction
    case error
}

// MARK: - Audio Player Error

public enum AudioPlayerError: Error {
    case fileNotFound
    case invalidFormat
    case engineError(Error)
    case seekError
    case invalidState

    var localizedDescription: String {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .invalidFormat:
            return "Unsupported audio format"
        case .engineError(let error):
            return "Audio engine error: \(error.localizedDescription)"
        case .seekError:
            return "Failed to seek to position"
        case .invalidState:
            return "Invalid player state for this operation"
        }
    }
}

// MARK: - Audio Entry ID

public struct AudioEntryId: Hashable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

// MARK: - Delegate Protocol

/// Delegate protocol for receiving playback events from the active engine.
/// Events are always published by the `PlaybackEngine` facade, never by a concrete backend.
public protocol AudioPlayerDelegate: AnyObject {
    func audioPlayerDidStartPlaying(player: PlaybackEngine, with entryId: AudioEntryId)
    func audioPlayerStateChanged(player: PlaybackEngine, with newState: AudioPlayerState, previous: AudioPlayerState)
    func audioPlayerDidFinishPlaying(
        player: PlaybackEngine,
        entryId: AudioEntryId,
        stopReason: AudioPlayerStopReason,
        progress: Double,
        duration: Double
    )
    func audioPlayerUnexpectedError(player: PlaybackEngine, error: AudioPlayerError)

    // Optional methods with default implementations
    func audioPlayerDidFinishBuffering(player: PlaybackEngine, with entryId: AudioEntryId)
    func audioPlayerDidReadMetadata(player: PlaybackEngine, metadata: [String: String])
    func audioPlayerDidCancel(player: PlaybackEngine, queuedItems: [AudioEntryId])
    func audioPlayerDidSkipQueueEntry(player: PlaybackEngine, entryId: AudioEntryId)
}

// MARK: - Default Implementations

public extension AudioPlayerDelegate {
    func audioPlayerDidFinishBuffering(player: PlaybackEngine, with entryId: AudioEntryId) {}
    func audioPlayerDidReadMetadata(player: PlaybackEngine, metadata: [String: String]) {}
    func audioPlayerDidCancel(player: PlaybackEngine, queuedItems: [AudioEntryId]) {}
    func audioPlayerDidSkipQueueEntry(player: PlaybackEngine, entryId: AudioEntryId) {}
}

// MARK: - Backend Abstraction

/// Internal abstraction over a concrete playback engine. Not part of the app-facing
/// surface; only `PlaybackEngine` talks to it. This lets every delegate signature
/// stay the concrete `PlaybackEngine` type, so the rest of the app never refers to
/// a backend directly.
protocol PlaybackBackend: AnyObject {
    var backendDelegate: PlaybackBackendDelegate? { get set }

    var volume: Float { get set }
    var state: AudioPlayerState { get }
    var currentPlaybackProgress: Double { get }
    var duration: Double { get }

    /// Whether this backend can pre-decode a queued next track for gapless
    /// transitions. When true, the app feeds it the upcoming track via
    /// `setNextTrack` and stops driving its own end-of-track advance.
    var supportsGaplessQueue: Bool { get }

    func play(url: URL, entryId: AudioEntryId, startPaused: Bool)
    func pause()
    func resume()
    func stop()
    func togglePlayPause()
    @discardableResult
    func seek(to time: Double) -> Bool
    @discardableResult
    func seekForward(_ seconds: Double) -> Bool
    @discardableResult
    func seekBackward(_ seconds: Double) -> Bool

    /// Pre-decodes `url` as the gapless successor to the current track. Replaces
    /// any previously set next track. No-op on backends without gapless support.
    func setNextTrack(url: URL, entryId: AudioEntryId)
    /// Drops the pre-decoded next track (e.g. when it's no longer the successor).
    func clearNextTrack()

    func setStereoWidening(enabled: Bool)
    func isStereoWideningEnabled() -> Bool
    func setEQEnabled(_ enabled: Bool)
    func isEQEnabled() -> Bool
    func applyEQPreset(_ preset: EqualizerPreset)
    func applyEQCustom(gains: [Float])
    func setPreamp(_ gain: Float)
    func getPreamp() -> Float
}

/// Shared EQ headroom policy used by playback backends.
///
/// Positive EQ boosts consume digital headroom before the signal reaches the
/// output path. Offset the largest boost, plus a small safety margin, so the
/// user-facing preamp can remain stable while the backend feeds a safer
/// effective gain to its engine.
enum EqualizerHeadroomCompensation {
    static func gainOffset(eqEnabled: Bool, gains: [Float]) -> Float {
        guard eqEnabled else { return 0 }

        let maxBandGain = gains.max() ?? 0
        if maxBandGain > 0 {
            return -(maxBandGain + 1.0)
        }
        return 0
    }
}

/// Events a `PlaybackBackend` reports up to the `PlaybackEngine` facade. The facade
/// re-publishes these to its `AudioPlayerDelegate` with itself as the `player`.
protocol PlaybackBackendDelegate: AnyObject {
    func backendDidStartPlaying(with entryId: AudioEntryId)
    func backendStateChanged(with newState: AudioPlayerState, previous: AudioPlayerState)
    func backendDidFinishPlaying(
        entryId: AudioEntryId,
        stopReason: AudioPlayerStopReason,
        progress: Double,
        duration: Double
    )
    func backendUnexpectedError(error: AudioPlayerError)
    func backendDidFinishBuffering(with entryId: AudioEntryId)
    func backendDidReadMetadata(metadata: [String: String])
    func backendDidCancel(queuedItems: [AudioEntryId])
    func backendDidSkipQueueEntry(entryId: AudioEntryId)
}

// MARK: - PlaybackEngine Facade

public class PlaybackEngine: NSObject {
    // MARK: - Public Properties

    public weak var delegate: AudioPlayerDelegate?

    public var volume: Float {
        get { backend.volume }
        set { backend.volume = newValue }
    }

    public var state: AudioPlayerState {
        backend.state
    }

    /// Current playback progress in seconds
    public var currentPlaybackProgress: Double {
        backend.currentPlaybackProgress
    }

    /// Total duration of current file in seconds
    public var duration: Double {
        backend.duration
    }

    /// Legacy property name for backwards compatibility
    public var progress: Double {
        currentPlaybackProgress
    }

    // MARK: - Private Properties

    private var backend: PlaybackBackend

    // MARK: - Initialization

    override public init() {
        self.backend = Self.makeBackend()
        super.init()
        self.backend.backendDelegate = self
    }

    /// Builds the backend for the selected engine.
    private static func makeBackend() -> PlaybackBackend {
        switch MediaBackend.current {
        case .sfb:
            return SFBPlaybackBackend()
        case .crescendo:
            return CrescendoPlaybackBackend()
        }
    }

    /// Tears down the current backend and rebuilds it from the current
    /// `MediaBackend` selection. The caller is responsible for first capturing
    /// any playback state to resume and for re-applying volume/effects afterward,
    /// since the new backend starts clean. The old backend's delegate is detached
    /// before teardown so its stop callbacks are not delivered as real events.
    public func reload() {
        backend.backendDelegate = nil
        backend.stop()
        backend = Self.makeBackend()
        backend.backendDelegate = self
    }

    /// Whether the active backend can pre-decode a queued next track for gapless.
    public var supportsGaplessQueue: Bool {
        backend.supportsGaplessQueue
    }

    // MARK: - Playback Control

    public func play(url: URL, entryId: AudioEntryId, startPaused: Bool = false) {
        backend.play(url: url, entryId: entryId, startPaused: startPaused)
    }

    /// Pre-decodes the gapless successor to the current track (gapless backends only).
    public func setNextTrack(url: URL, entryId: AudioEntryId) {
        backend.setNextTrack(url: url, entryId: entryId)
    }

    /// Drops the pre-decoded next track.
    public func clearNextTrack() {
        backend.clearNextTrack()
    }

    public func pause() {
        backend.pause()
    }

    public func resume() {
        backend.resume()
    }

    public func stop() {
        backend.stop()
    }

    public func togglePlayPause() {
        backend.togglePlayPause()
    }

    @discardableResult
    public func seek(to time: Double) -> Bool {
        backend.seek(to: time)
    }

    @discardableResult
    public func seekForward(_ seconds: Double) -> Bool {
        backend.seekForward(seconds)
    }

    @discardableResult
    public func seekBackward(_ seconds: Double) -> Bool {
        backend.seekBackward(seconds)
    }

    // MARK: - Audio Effects

    public func setStereoWidening(enabled: Bool) {
        backend.setStereoWidening(enabled: enabled)
    }

    public func isStereoWideningEnabled() -> Bool {
        backend.isStereoWideningEnabled()
    }

    public func setEQEnabled(_ enabled: Bool) {
        backend.setEQEnabled(enabled)
    }

    public func isEQEnabled() -> Bool {
        backend.isEQEnabled()
    }

    public func applyEQPreset(_ preset: EqualizerPreset) {
        backend.applyEQPreset(preset)
    }

    public func applyEQCustom(gains: [Float]) {
        backend.applyEQCustom(gains: gains)
    }

    public func setPreamp(_ gain: Float) {
        backend.setPreamp(gain)
    }

    public func getPreamp() -> Float {
        backend.getPreamp()
    }
}

// MARK: - PlaybackBackendDelegate

extension PlaybackEngine: PlaybackBackendDelegate {
    func backendDidStartPlaying(with entryId: AudioEntryId) {
        delegate?.audioPlayerDidStartPlaying(player: self, with: entryId)
    }

    func backendStateChanged(with newState: AudioPlayerState, previous: AudioPlayerState) {
        delegate?.audioPlayerStateChanged(player: self, with: newState, previous: previous)
    }

    func backendDidFinishPlaying(
        entryId: AudioEntryId,
        stopReason: AudioPlayerStopReason,
        progress: Double,
        duration: Double
    ) {
        delegate?.audioPlayerDidFinishPlaying(
            player: self,
            entryId: entryId,
            stopReason: stopReason,
            progress: progress,
            duration: duration
        )
    }

    func backendUnexpectedError(error: AudioPlayerError) {
        delegate?.audioPlayerUnexpectedError(player: self, error: error)
    }

    func backendDidFinishBuffering(with entryId: AudioEntryId) {
        delegate?.audioPlayerDidFinishBuffering(player: self, with: entryId)
    }

    func backendDidReadMetadata(metadata: [String: String]) {
        delegate?.audioPlayerDidReadMetadata(player: self, metadata: metadata)
    }

    func backendDidCancel(queuedItems: [AudioEntryId]) {
        delegate?.audioPlayerDidCancel(player: self, queuedItems: queuedItems)
    }

    func backendDidSkipQueueEntry(entryId: AudioEntryId) {
        delegate?.audioPlayerDidSkipQueueEntry(player: self, entryId: entryId)
    }
}
