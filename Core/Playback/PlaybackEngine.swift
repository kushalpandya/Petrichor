//
// PlaybackEngine
//
// The single app-facing playback object. It owns the concrete `PlaybackBackend` and
// is the only object that calls `AudioPlayerDelegate`, so swapping the backend never
// touches call sites.
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

    // Entry ids only have to be unique within a session, so a counter is enough -
    // and a whole library queued at once mints one per track.
    private static var nextValue: UInt64 = 0

    /// A new identity, distinct from every other in this session. Main-thread only,
    /// which every queue mutation already is.
    public static func fresh() -> AudioEntryId {
        nextValue &+= 1
        return AudioEntryId(id: "e\(nextValue)")
    }
}

// MARK: - Queue Entry

/// One entry in the engine's queue. Identity is the `entryId`, never the URL: the
/// same file queued twice is two entries, which is how repeat-one is expressed.
public struct QueueEntry {
    public let entryId: AudioEntryId
    public let url: URL

    public init(entryId: AudioEntryId, url: URL) {
        self.entryId = entryId
        self.url = url
    }
}

// MARK: - Now Playing Metadata

/// The descriptive half of the system Now Playing tile. The engine owns the
/// dynamic half - duration, elapsed time, rate - and publishes the merged result.
public struct NowPlayingMetadata {
    public var title: String?
    public var artist: String?
    public var albumTitle: String?
    public var albumArtist: String?
    public var genre: String?
    /// Encoded image bytes; the engine decodes and caches them.
    public var artworkData: Data?

    public init(
        title: String? = nil,
        artist: String? = nil,
        albumTitle: String? = nil,
        albumArtist: String? = nil,
        genre: String? = nil,
        artworkData: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.albumArtist = albumArtist
        self.genre = genre
        self.artworkData = artworkData
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
    func audioPlayerDidSkipQueueEntry(player: PlaybackEngine, entryId: AudioEntryId)
}

// MARK: - Default Implementations

public extension AudioPlayerDelegate {
    func audioPlayerDidFinishBuffering(player: PlaybackEngine, with entryId: AudioEntryId) {}
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

    /// The backend's queue, in order: played, current, then upcoming.
    var queue: [AudioEntryId] { get }
    /// The queue index of `entryId`, or nil if it is no longer queued.
    func queueIndex(of entryId: AudioEntryId) -> Int?
    /// Whether an entry is queued after the one now loaded.
    var hasQueuedSuccessor: Bool { get }

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

    // MARK: Queue

    /// Installs `entries` as the queue and starts the one at `index`. This is the
    /// only queue call that (re)starts playback; every other mutation leaves the
    /// playing entry alone.
    func setQueue(_ entries: [QueueEntry], startingAt index: Int, startPaused: Bool)
    func insert(_ entry: QueueEntry, at index: Int)
    func append(_ entry: QueueEntry)
    /// Queues `entry` directly after the current one, making it the gapless successor.
    func insertNext(_ entry: QueueEntry)
    func move(from: Int, to: Int)
    func removeQueueEntry(at index: Int)
    func removeQueueEntry(id: AudioEntryId)
    func clearQueue()
    /// Plays the queue entry at `index`, keeping the rest of the queue intact.
    func playQueueEntry(at index: Int, startPaused: Bool)
    /// Shuffles the entries after the current one, leaving played and current in place.
    func shuffleQueue()

    /// Metadata for the playing track; the backend publishes the system Now
    /// Playing tile from it. `nil` clears it.
    func setNowPlayingMetadata(_ metadata: NowPlayingMetadata?)

    func setStereoWidening(enabled: Bool)
    func isStereoWideningEnabled() -> Bool
    func setEQEnabled(_ enabled: Bool)
    func isEQEnabled() -> Bool
    func applyEQPreset(_ preset: EqualizerPreset)
    func applyEQCustom(gains: [Float])
    func setPreamp(_ gain: Float)
    func getPreamp() -> Float
    func setCrossfadeEnabled(_ enabled: Bool)
    func isCrossfadeEnabled() -> Bool
    func setCrossfadeDuration(_ duration: TimeInterval)
    func getCrossfadeDuration() -> TimeInterval
    var crossfadeDurationRange: ClosedRange<TimeInterval> { get }
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

    // MARK: - Private Properties

    private let backend: PlaybackBackend

    // MARK: - Initialization

    override public init() {
        self.backend = CrescendoPlaybackBackend()
        super.init()
        self.backend.backendDelegate = self
    }

    // MARK: - Playback Control

    // MARK: - Queue

    /// The engine's queue in order. Only the shuffle read-back needs the whole list;
    /// single positions go through `queueIndex(of:)`, which avoids building it.
    public var queue: [AudioEntryId] {
        backend.queue
    }

    /// The engine index of `entryId`, or nil if it is no longer queued.
    public func queueIndex(of entryId: AudioEntryId) -> Int? {
        backend.queueIndex(of: entryId)
    }

    /// Whether an entry is queued after the one now playing.
    public var hasQueuedSuccessor: Bool {
        backend.hasQueuedSuccessor
    }

    public func setQueue(_ entries: [QueueEntry], startingAt index: Int, startPaused: Bool = false) {
        backend.setQueue(entries, startingAt: index, startPaused: startPaused)
    }

    public func insert(_ entry: QueueEntry, at index: Int) {
        backend.insert(entry, at: index)
    }

    public func append(_ entry: QueueEntry) {
        backend.append(entry)
    }

    public func insertNext(_ entry: QueueEntry) {
        backend.insertNext(entry)
    }

    public func move(from: Int, to: Int) {
        backend.move(from: from, to: to)
    }

    public func removeQueueEntry(at index: Int) {
        backend.removeQueueEntry(at: index)
    }

    public func removeQueueEntry(id: AudioEntryId) {
        backend.removeQueueEntry(id: id)
    }

    public func clearQueue() {
        backend.clearQueue()
    }

    public func playQueueEntry(at index: Int, startPaused: Bool = false) {
        backend.playQueueEntry(at: index, startPaused: startPaused)
    }

    public func shuffleQueue() {
        backend.shuffleQueue()
    }

    // MARK: - Now Playing

    /// Call on track change; the engine keeps elapsed, duration and rate current.
    public func setNowPlayingMetadata(_ metadata: NowPlayingMetadata?) {
        backend.setNowPlayingMetadata(metadata)
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

    public func setCrossfadeEnabled(_ enabled: Bool) {
        backend.setCrossfadeEnabled(enabled)
    }

    public func isCrossfadeEnabled() -> Bool {
        backend.isCrossfadeEnabled()
    }

    public func setCrossfadeDuration(_ duration: TimeInterval) {
        backend.setCrossfadeDuration(duration)
    }

    public func getCrossfadeDuration() -> TimeInterval {
        backend.getCrossfadeDuration()
    }

    public var crossfadeDurationRange: ClosedRange<TimeInterval> {
        backend.crossfadeDurationRange
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

    func backendDidSkipQueueEntry(entryId: AudioEntryId) {
        delegate?.audioPlayerDidSkipQueueEntry(player: self, entryId: entryId)
    }
}
