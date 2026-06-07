import AVFoundation
import Foundation
import SFBAudioEngine

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

/// Delegate protocol for receiving playback events
public protocol AudioPlayerDelegate: AnyObject {
    func audioPlayerDidStartPlaying(player: PAudioPlayer, with entryId: AudioEntryId)
    func audioPlayerStateChanged(player: PAudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState)
    func audioPlayerDidFinishPlaying(
        player: PAudioPlayer,
        entryId: AudioEntryId,
        stopReason: AudioPlayerStopReason,
        progress: Double,
        duration: Double
    )
    func audioPlayerUnexpectedError(player: PAudioPlayer, error: AudioPlayerError)
    
    // Optional methods with default implementations
    func audioPlayerDidFinishBuffering(player: PAudioPlayer, with entryId: AudioEntryId)
    func audioPlayerDidReadMetadata(player: PAudioPlayer, metadata: [String: String])
    func audioPlayerDidCancel(player: PAudioPlayer, queuedItems: [AudioEntryId])
}

// MARK: - Default Implementations

public extension AudioPlayerDelegate {
    func audioPlayerDidFinishBuffering(player: PAudioPlayer, with entryId: AudioEntryId) {}
    func audioPlayerDidReadMetadata(player: PAudioPlayer, metadata: [String: String]) {}
    func audioPlayerDidCancel(player: PAudioPlayer, queuedItems: [AudioEntryId]) {}
}

// MARK: - PAudioPlayer

/// Audio player that decodes with SFBAudioEngine and renders through
/// `SpatialAudioRenderer` (`AVSampleBufferAudioRenderer`).
///
/// Rendering through `AVSampleBufferAudioRenderer` makes the audio eligible for
/// macOS system-level Spatial Audio: with AirPods (3rd gen)/Pro/Max connected, the
/// Sound menu offers Spatialize Stereo (Fixed / Head Tracked) and the OS performs
/// the spatialization and head tracking natively — no app configuration required,
/// matching the behavior of Apple Music and other AVFoundation-based players.
public class PAudioPlayer: NSObject {
    
    // MARK: - Public Properties
    
    public weak var delegate: AudioPlayerDelegate?
    
    public var volume: Float {
        get {
            return renderer.volume
        }
        set {
            renderer.volume = newValue
        }
    }
    
    public private(set) var state: AudioPlayerState = .ready {
        didSet {
            guard oldValue != state else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.audioPlayerStateChanged(player: self, with: self.state, previous: oldValue)
            }
        }
    }
    
    /// Current playback progress in seconds
    public var currentPlaybackProgress: Double {
        renderer.currentTime
    }
    
    /// Total duration of current file in seconds
    public var duration: Double {
        renderer.duration
    }
    
    /// Legacy property name for backwards compatibility
    public var progress: Double {
        return currentPlaybackProgress
    }
    
    // MARK: - Private Properties
    
    private let renderer = SpatialAudioRenderer()
    private var currentEntryId: AudioEntryId?
    private var currentURL: URL?
    private static let maxPreBufferSize: UInt64 = 100 * 1024 * 1024
    
    /// Equalizer preamp state (the gain compensation policy lives here; the
    /// effect nodes live in the renderer's effects chain)
    private var userPreampGain: Float = 0.0
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        renderer.delegate = self
    }
    
    deinit {
        renderer.stop()
    }
    
    // MARK: - Playback Control
    
    /// Play an audio file from URL
    /// - Parameters:
    ///   - url: The URL of the audio file
    ///   - startPaused: If true, loads the file but doesn't start playback
    public func play(url: URL, startPaused: Bool = false) {
        currentURL = url
        let entryId = AudioEntryId(id: url.lastPathComponent)
        currentEntryId = entryId
        
        let shouldPreBuffer = Self.shouldPreBuffer(url: url)
            state = .ready
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                do {
                let decoder = try Self.makeDecoder(for: url, preBuffer: shouldPreBuffer)
                try decoder.open()
                    
                    DispatchQueue.main.async {
                    // Ignore the result of a stale load if another track started meanwhile
                    guard self.currentEntryId == entryId else { return }

                    do {
                        try self.renderer.play(decoder: decoder, startPaused: startPaused)
                        if startPaused {
                            self.state = .paused
                        } else {
                            self.notifyPlaybackStarted()
                        }
                        Logger.info("Started playing\(shouldPreBuffer ? " (pre-buffered)" : ""): \(url.lastPathComponent)")
                    } catch {
                        self.handlePlaybackError(error, entryId: entryId)
                    }
                        }
                    } catch {
                        DispatchQueue.main.async {
                    guard self.currentEntryId == entryId else { return }
                            self.handlePlaybackError(error, entryId: entryId)
                        }
            }
        }
    }
    
    /// Pause playback
    public func pause() {
        guard state == .playing else { return }
        renderer.pause()
        state = .paused
        Logger.info("Playback paused")
    }
    
    /// Resume playback
    public func resume() {
        guard state == .paused else { return }
        renderer.resume()
        notifyPlaybackStarted()
            Logger.info("Playback resumed")
    }
    
    /// Stop playback
    public func stop() {
        guard state != .stopped else { return }
        
        let wasPlaying = state == .playing
        let currentProgress = currentPlaybackProgress
        let currentDuration = duration
        let entryId = currentEntryId
        
        renderer.stop()
        state = .stopped
        
        if wasPlaying, let entryId = entryId {
            delegate?.audioPlayerDidFinishPlaying(
                player: self,
                entryId: entryId,
                stopReason: .userAction,
                progress: currentProgress,
                duration: currentDuration
            )
        }
        
        currentURL = nil
        currentEntryId = nil
        
        Logger.info("Playback stopped")
    }
    
    /// Toggle between play and pause
    public func togglePlayPause() {
        switch state {
            case .playing:
            pause()
            case .paused:
            resume()
        default:
                break
        }
    }
    
    /// Seek to a specific time in seconds
    /// - Parameter time: The target time in seconds
    /// - Returns: true if seek was successful
    @discardableResult
    public func seek(to time: Double) -> Bool {
        guard time >= 0 else { return false }
        
        let success = renderer.seek(to: time)
        
        if !success {
            Logger.error("Failed to seek to time: \(time)")
            delegate?.audioPlayerUnexpectedError(player: self, error: .seekError)
        }
        
        return success
    }
    
    /// Seek forward by a number of seconds
    /// - Parameter seconds: Number of seconds to skip forward
    /// - Returns: true if seek was successful
    @discardableResult
    public func seekForward(_ seconds: Double) -> Bool {
        return seek(to: currentPlaybackProgress + seconds)
    }
    
    /// Seek backward by a number of seconds
    /// - Parameter seconds: Number of seconds to skip backward
    /// - Returns: true if seek was successful
    @discardableResult
    public func seekBackward(_ seconds: Double) -> Bool {
        return seek(to: max(0, currentPlaybackProgress - seconds))
    }
    
    // MARK: - Audio Equalizer
    
    /// Enable or disable stereo widening effect
    /// - Parameter enabled: boolean for the current state of stereo widening
    public func setStereoWidening(enabled: Bool) {
        renderer.effects.setStereoWidening(enabled: enabled)
        Logger.info("Stereo Widening \(enabled ? "enabled" : "disabled")")
    }

    /// Check if stereo widening is currently enabled
    /// - Returns: true if Stereo Widening is enabled, false otherwise
    public func isStereoWideningEnabled() -> Bool {
        return renderer.effects.stereoWideningEnabled
    }
    
    /// Enable or disable the equalizer
    /// - Parameter enabled: boolean for the current state Equalizer
    public func setEQEnabled(_ enabled: Bool) {
        renderer.effects.setEQEnabled(enabled)
        applyEffectivePreamp()
        Logger.info("Audio Equalizer \(enabled ? "enabled" : "disabled")")
    }
    
    /// Check if EQ is currently enabled
    /// - Returns: true if Equalizer is enabled, false otherwise
    public func isEQEnabled() -> Bool {
        return renderer.effects.eqEnabled
    }
    
    /// Apply an EQ preset
    /// - Parameter preset: The EqualizerPreset to apply
    public func applyEQPreset(_ preset: EqualizerPreset) {
        renderer.effects.setEQGains(preset.gains)
        applyEffectivePreamp()
        Logger.info("Applied Equalizer preset: \(preset.displayName)")
    }
    
    /// Apply custom EQ gains
    /// - Parameter gains: Array of 10 gain values in dB (one for each frequency band)
    public func applyEQCustom(gains: [Float]) {
        guard gains.count == 10 else {
            Logger.warning("Equalizer gains array must contain exactly 10 values, got \(gains.count)")
            return
        }
        
        renderer.effects.setEQGains(gains)
        applyEffectivePreamp()
        Logger.info("Applied custom Equalizer gains")
    }
    
    /// Set the preamp gain (affects overall volume before EQ)
    /// - Parameter gain: Gain value in dB, typically -12 to +12
    /// - Note: Preamp adjusts the signal level before EQ processing
    public func setPreamp(_ gain: Float) {
        userPreampGain = max(-12.0, min(12.0, gain))
        applyEffectivePreamp()
        Logger.info("Preamp set to \(userPreampGain) dB")
    }

    /// Get the current preamp gain value
    /// - Returns: Current preamp gain in dB
    public func getPreamp() -> Float {
        return userPreampGain
    }
    
    // MARK: - Private Methods
    
    /// Creates a decoder for the URL, loading the file into memory when pre-buffering
    private static func makeDecoder(for url: URL, preBuffer: Bool) throws -> AudioDecoder {
        if preBuffer {
            do {
                let inputSource = try InputSource(for: url, flags: .loadFilesInMemory)
                return try AudioDecoder(inputSource: inputSource)
            } catch {
                Logger.warning("Pre-buffering failed, falling back to direct decoding: \(error.localizedDescription)")
                    }
                }
        return try AudioDecoder(url: url)
                }

    /// Fires didStartPlaying on transitions into the playing state
    private func notifyPlaybackStarted() {
        guard state != .playing else { return }
        state = .playing
        if let entryId = currentEntryId {
            delegate?.audioPlayerDidStartPlaying(player: self, with: entryId)
        }
    }
    
    /// Common end-of-track handling
    private func finishCurrentTrack() {
        let finalProgress = currentPlaybackProgress
        let finalDuration = duration
        
        if let entryId = currentEntryId {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.state = .stopped
                self.delegate?.audioPlayerDidFinishPlaying(
                    player: self,
                    entryId: entryId,
                    stopReason: .eof,
                    progress: finalProgress,
                    duration: finalDuration
                )
                
                self.currentURL = nil
                self.currentEntryId = nil
            }
        }
    }
    
    private static func shouldPreBuffer(url: URL) -> Bool {
        // Only consider pre-buffering for files under the size threshold
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              UInt64(fileSize) <= maxPreBufferSize else {
            return false
        }
        
        // Check if the file is on a network volume
        if let resourceValues = try? url.resourceValues(forKeys: [.volumeIsLocalKey]),
           let isLocal = resourceValues.volumeIsLocal,
           !isLocal {
            return true
        }
        
        // Check filesystem type for FUSE-based mounts
        if FilesystemUtils.isSlowFilesystem(url: url) {
            return true
        }
        
        return false
    }
    
    /// Handle playback errors
    private func handlePlaybackError(_ error: Error, entryId: AudioEntryId) {
        Logger.error("Failed to play audio: \(error)")
        state = .stopped
        
        delegate?.audioPlayerUnexpectedError(player: self, error: .engineError(error))
        delegate?.audioPlayerDidFinishPlaying(
            player: self,
            entryId: entryId,
            stopReason: .error,
            progress: 0,
            duration: 0
        )
    }
    
    private func calculateGainCompensation() -> Float {
        guard renderer.effects.eqEnabled else { return 0 }
        
        let maxBandGain = renderer.effects.eqGains.max() ?? 0
        
        if maxBandGain > 0 {
            // Offset max gain to prevent audio
            // distortion due to signal clipping
            return -(maxBandGain + 1.0)
        }
        return 0
    }
    
    private func applyEffectivePreamp() {
        let compensation = calculateGainCompensation()
        renderer.effects.setPreamp(userPreampGain + compensation)
    }
}

// MARK: - SpatialAudioRendererDelegate

extension PAudioPlayer: SpatialAudioRendererDelegate {
    func spatialAudioRendererDidReachEnd(_ renderer: SpatialAudioRenderer) {
        finishCurrentTrack()
    }
    
    func spatialAudioRenderer(_ renderer: SpatialAudioRenderer, encounteredError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.audioPlayerUnexpectedError(player: self, error: .engineError(error))
    }
}
}
