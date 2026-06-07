import AVFoundation
import CoreMotion
import Foundation
import SFBAudioEngine

typealias SFBPlayer = SFBAudioEngine.AudioPlayer
typealias SFBPlayerPlaybackState = SFBAudioEngine.AudioPlayer.PlaybackState
typealias SFBDecoding = SFBAudioEngine.PCMDecoding

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

public class PAudioPlayer: NSObject {
    
    // MARK: - Public Properties
    
    public weak var delegate: AudioPlayerDelegate?
    
    public var volume: Float {
        get {
            return sfbPlayer.volume
        }
        set {
            do {
                try sfbPlayer.setVolume(newValue)
            } catch {
                Logger.error("Failed to set volume: \(error)")
            }
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
        sfbPlayer.currentTime ?? 0
    }
    
    /// Total duration of current file in seconds
    public var duration: Double {
        sfbPlayer.totalTime ?? 0
    }
    
    /// Legacy property name for backwards compatibility
    public var progress: Double {
        return currentPlaybackProgress
    }
    
    // MARK: - Private Properties
    
    private let sfbPlayer: SFBPlayer
    private var currentEntryId: AudioEntryId?
    private var currentURL: URL?
    private var delegateBridge: SFBAudioPlayerDelegateBridge?
    private static let maxPreBufferSize: UInt64 = 100 * 1024 * 1024
    
    // MARK: - Audio Effects Nodes

    private var effectsAttached = false

    /// Stereo Widening
    private var stereoWideningEnabled: Bool = false
    private var stereoWideningNode: AVAudioUnit?

    /// Equalizer
    private var eqEnabled: Bool = false
    private var eqNode: AVAudioUnitEQ?
    private var preampGain: Float = 0.0
    private var userPreampGain: Float = 0.0
    private var currentEQGains: [Float] = Array(repeating: 0.0, count: 10)
    private let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    /// Spatial Audio (Spatialize Stereo)
    private var spatialAudioEnabled: Bool = false
    private var headTrackingEnabled: Bool = false
    private var environmentNode: AVAudioEnvironmentNode?
    private var headphoneMotionManager: CMHeadphoneMotionManager?
    
    // MARK: - Initialization
    
    public override init() {
        self.sfbPlayer = SFBPlayer()
        super.init()
        
        // Create and set up the delegate bridge for playback event monitoring
        self.delegateBridge = SFBAudioPlayerDelegateBridge(owner: self)
        self.sfbPlayer.delegate = self.delegateBridge
    }
    
    deinit {
        headphoneMotionManager?.stopDeviceMotionUpdates()
        sfbPlayer.stop()
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
        
        if shouldPreBuffer {
            state = .ready
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                do {
                    let inputSource = try InputSource(for: url, flags: .loadFilesInMemory)
                    let decoder = try AudioDecoder(inputSource: inputSource)
                    
                    try self.sfbPlayer.play(decoder)
                    
                    DispatchQueue.main.async {
                        if startPaused {
                            self.sfbPlayer.pause()
                            self.state = .paused
                        } else {
                            self.state = .playing
                        }
                        Logger.info("Started playing (pre-buffered): \(url.lastPathComponent)")
                    }
                } catch {
                    Logger.warning("Pre-buffering failed, falling back to direct playback: \(error.localizedDescription)")
                    
                    do {
                        try self.sfbPlayer.play(url)
                        
                        DispatchQueue.main.async {
                            if startPaused {
                                self.sfbPlayer.pause()
                                self.state = .paused
                            } else {
                                self.state = .playing
                            }
                            Logger.info("Started playing (direct fallback): \(url.lastPathComponent)")
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.handlePlaybackError(error, entryId: entryId)
                        }
                    }
                }
            }
        } else {
            do {
                try sfbPlayer.play(url)
                
                if startPaused {
                    sfbPlayer.pause()
                    state = .paused
                } else {
                    state = .playing
                }
                
                Logger.info("Started playing: \(url.lastPathComponent)")
            } catch {
                handlePlaybackError(error, entryId: entryId)
            }
        }
    }
    
    /// Pause playback
    public func pause() {
        guard state == .playing else { return }
        sfbPlayer.pause()
        state = .paused
        Logger.info("Playback paused")
    }
    
    /// Resume playback
    public func resume() {
        guard state == .paused else { return }
        
        do {
            try sfbPlayer.play()
            state = .playing
            Logger.info("Playback resumed")
        } catch {
            Logger.error("Failed to resume playback: \(error)")
            delegate?.audioPlayerUnexpectedError(player: self, error: .engineError(error))
        }
    }
    
    /// Stop playback
    public func stop() {
        guard state != .stopped else { return }
        
        let wasPlaying = state == .playing
        let currentProgress = currentPlaybackProgress
        let currentDuration = duration
        let entryId = currentEntryId
        
        sfbPlayer.stop()
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
        do {
            try sfbPlayer.togglePlayPause()
            
            // Update state based on current playback state
            switch sfbPlayer.playbackState {
            case .playing:
                state = .playing
            case .paused:
                state = .paused
            case .stopped:
                state = .stopped
            @unknown default:
                break
            }
        } catch {
            Logger.error("Failed to toggle play/pause: \(error)")
            delegate?.audioPlayerUnexpectedError(player: self, error: .engineError(error))
        }
    }
    
    /// Seek to a specific time in seconds
    /// - Parameter time: The target time in seconds
    /// - Returns: true if seek was successful
    @discardableResult
    public func seek(to time: Double) -> Bool {
        guard time >= 0 else { return false }
        
        let success = sfbPlayer.seek(time: time)
        
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
        return sfbPlayer.seek(forward: seconds)
    }
    
    /// Seek backward by a number of seconds
    /// - Parameter seconds: Number of seconds to skip backward
    /// - Returns: true if seek was successful
    @discardableResult
    public func seekBackward(_ seconds: Double) -> Bool {
        return sfbPlayer.seek(backward: seconds)
    }
    
    // MARK: - Audio Equalizer
    
    /// Enable or disable stereo widening effect
    /// - Parameter enabled: boolean for the current state of stereo widening
    public func setStereoWidening(enabled: Bool) {
        stereoWideningEnabled = enabled
        
        if !effectsAttached {
            setupAudioEffects()
        }
        
        if let effectNode = stereoWideningNode as? AVAudioUnitEffect {
            effectNode.bypass = !enabled
        }
        
        Logger.info("Stereo Widening \(enabled ? "enabled" : "disabled")")
    }

    /// Check if stereo widening is currently enabled
    /// - Returns: true if Stereo Widening is enabled, false otherwise
    public func isStereoWideningEnabled() -> Bool {
        return stereoWideningEnabled
    }

    // MARK: - Spatial Audio

    /// Enable or disable Spatialize Stereo (spatial audio rendering)
    /// - Parameter enabled: boolean for the current state of spatial audio
    public func setSpatialAudio(enabled: Bool) {
        spatialAudioEnabled = enabled

        if !effectsAttached {
            setupAudioEffects()
        }

        applySpatialSourceMode()
        updateHeadTrackingState()

        Logger.info("Spatialize Stereo \(enabled ? "enabled" : "disabled")")
    }

    /// Check if spatial audio is currently enabled
    /// - Returns: true if Spatialize Stereo is enabled, false otherwise
    public func isSpatialAudioEnabled() -> Bool {
        return spatialAudioEnabled
    }

    /// Enable or disable head tracking for spatial audio
    /// - Parameter enabled: boolean for the current state of head tracking
    /// - Note: Head tracking only takes effect while spatial audio is enabled, and
    ///   requires headphones that provide motion data (e.g. AirPods Pro / AirPods Max)
    public func setHeadTracking(enabled: Bool) {
        headTrackingEnabled = enabled
        updateHeadTrackingState()
        Logger.info("Head tracking \(enabled ? "enabled" : "disabled")")
    }

    /// Check if head tracking is currently enabled
    /// - Returns: true if head tracking is enabled, false otherwise
    public func isHeadTrackingEnabled() -> Bool {
        return headTrackingEnabled
    }

    /// Enable or disable the equalizer
    /// - Parameter enabled: boolean for the current state Equalizer
    public func setEQEnabled(_ enabled: Bool) {
        eqEnabled = enabled
        
        if !effectsAttached {
            setupAudioEffects()
        }
        
        eqNode?.bypass = !enabled
        
        applyEffectivePreamp()
        
        Logger.info("Audio Equalizer \(enabled ? "enabled" : "disabled")")
    }
    
    /// Check if EQ is currently enabled
    /// - Returns: true if Equalizer is enabled, false otherwise
    public func isEQEnabled() -> Bool {
        return eqEnabled
    }
    
    /// Apply an EQ preset
    /// - Parameter preset: The EqualizerPreset to apply
    public func applyEQPreset(_ preset: EqualizerPreset) {
        currentEQGains = preset.gains
        
        if !effectsAttached {
            setupAudioEffects()
        }
        
        if let eq = eqNode {
            for (index, gain) in currentEQGains.enumerated() {
                eq.bands[index].gain = gain
            }
        }
        
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
        
        currentEQGains = gains
        
        if !effectsAttached {
            setupAudioEffects()
        }
        
        if let eq = eqNode {
            for (index, gain) in gains.enumerated() {
                eq.bands[index].gain = gain
            }
        }
        
        applyEffectivePreamp()
        
        Logger.info("Applied custom Equalizer gains")
    }
    
    /// Set the preamp gain (affects overall volume before EQ)
    /// - Parameter gain: Gain value in dB, typically -12 to +12
    /// - Note: Preamp adjusts the signal level before EQ processing
    public func setPreamp(_ gain: Float) {
        userPreampGain = max(-12.0, min(12.0, gain))
        applyEffectivePreamp()
        Logger.info("Preamp set to \(userPreampGain) dB (effective: \(preampGain) dB)")
    }

    /// Get the current preamp gain value
    /// - Returns: Current preamp gain in dB
    public func getPreamp() -> Float {
        return userPreampGain
    }
    
    // MARK: - Internal Methods (called by delegate bridge)
    
    internal func handlePlaybackStateChanged(_ newState: SFBPlayerPlaybackState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch newState {
            case .playing:
                if self.state != .playing {
                    self.state = .playing
                    if let entryId = self.currentEntryId {
                        self.delegate?.audioPlayerDidStartPlaying(player: self, with: entryId)
                    }
                }
            case .paused:
                if self.state != .paused {
                    self.state = .paused
                }
            case .stopped:
                if self.state != .stopped {
                    self.state = .stopped
                }
            @unknown default:
                break
            }
        }
    }
    
    internal func handleEndOfAudio() {
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
    
    /// Reconfigures the audio processing graph when the format changes
    /// This is called by SFBAudioEngine when switching between different sample rates
    internal func reconfigureAudioGraph(engine: AVAudioEngine, format: AVAudioFormat) -> AVAudioNode {
        Logger.info("Reconfiguring audio graph for format: \(format.sampleRate)Hz, \(format.channelCount)ch")
        
        guard effectsAttached else {
            Logger.info("No effects attached, connecting directly to mixer")
            return engine.mainMixerNode
        }
        
        // Detach and recreate effect nodes with the new format
        if let oldEnvironmentNode = environmentNode {
            engine.detach(oldEnvironmentNode)
            environmentNode = nil
        }

        if let oldStereoNode = stereoWideningNode {
            engine.detach(oldStereoNode)
            stereoWideningNode = nil
        }

        if let oldEQNode = eqNode {
            engine.detach(oldEQNode)
            eqNode = nil
        }

        // Recreate the effects chain
        setupSpatialAudio(engine: engine)
        setupStereoWidening(engine: engine)
        setupEqualizer(engine: engine)

        let mainMixer = engine.mainMixerNode

        if let environment = environmentNode, let stereoNode = stereoWideningNode, let equalizer = eqNode {
            let chainFormat = spatialChainFormat(for: format)
            engine.connect(environment, to: stereoNode, format: chainFormat)
            engine.connect(stereoNode, to: equalizer, format: chainFormat)
            engine.connect(equalizer, to: mainMixer, format: chainFormat)
            Logger.info("Reconfigured audio graph: playerNode -> spatialAudio -> stereoWidening -> EQ -> mainMixer")

            // SFBAudioEngine connects sourceNode to the returned node; the source mode is
            // re-applied async since the new mixing destination doesn't exist yet
            DispatchQueue.main.async { [weak self] in
                self?.applySpatialSourceMode()
            }

            return environment
        }

        Logger.warning("Failed to reconfigure effects chain, falling back to mixer")
        return mainMixer
    }
    
    internal func handleError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.audioPlayerUnexpectedError(player: self, error: .engineError(error))
        }
    }
    
    // MARK: - Private Methods
    
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
    
    private func setupAudioEffects() {
        guard !effectsAttached else {
            Logger.info("Audio effects already attached")
            return
        }
        
        let sourceNode = sfbPlayer.sourceNode
        let mainMixer = sfbPlayer.mainMixerNode
        let format = sourceNode.outputFormat(forBus: 0)
        
        Logger.info("Setting up audio effects...")
        Logger.info("Source node: \(sourceNode), Format: \(format.sampleRate)Hz, \(format.channelCount)ch")
        
        sfbPlayer.modifyProcessingGraph { [self] engine in
            setupSpatialAudio(engine: engine)
            setupStereoWidening(engine: engine)
            setupEqualizer(engine: engine)

            guard let environment = environmentNode,
                  let stereoNode = stereoWideningNode,
                  let equalizer = eqNode else {
                Logger.warning("Failed to create effect nodes")
                return
            }

            // The environment node renders to stereo regardless of the source channel count
            let chainFormat = spatialChainFormat(for: format)

            // Disconnect sourceNode from mainMixer
            engine.disconnectNodeOutput(sourceNode)

            // Connect: sourceNode -> spatialAudio -> stereoWidening -> EQ -> mainMixer
            engine.connect(sourceNode, to: environment, format: format)
            engine.connect(environment, to: stereoNode, format: chainFormat)
            engine.connect(stereoNode, to: equalizer, format: chainFormat)
            engine.connect(equalizer, to: mainMixer, format: chainFormat)

            // Apply the source mode after connecting so the mixing destination exists
            applySpatialSourceMode()

            effectsAttached = true
            Logger.info("Audio effects setup complete")
        }
    }

    private func setupSpatialAudio(engine: AVAudioEngine) {
        let environment = AVAudioEnvironmentNode()
        // Spatialize Stereo is a headphones feature; .headphones selects binaural rendering
        environment.outputType = .headphones
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)

        engine.attach(environment)
        self.environmentNode = environment

        Logger.info("Attached environment node (Spatialize Stereo)")
    }

    /// Stereo output format matching the source sample rate, used downstream of the environment node
    private func spatialChainFormat(for format: AVAudioFormat) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2) ?? format
    }

    /// Applies the spatialization mode to the player's source node feeding the environment node
    private func applySpatialSourceMode() {
        let sourceNode = sfbPlayer.sourceNode
        // .auto picks the highest-quality binaural algorithm for the configured output type
        sourceNode.renderingAlgorithm = .auto
        // .ambienceBed spatializes the stereo channels as far-field sources anchored to
        // global space (i.e. "Spatialize Stereo"); .bypass passes audio through untouched
        sourceNode.sourceMode = spatialAudioEnabled ? .ambienceBed : .bypass
    }

    // MARK: - Head Tracking

    private func updateHeadTrackingState() {
        if spatialAudioEnabled && headTrackingEnabled {
            startHeadTracking()
        } else {
            stopHeadTracking()
        }
    }

    private func startHeadTracking() {
        if headphoneMotionManager == nil {
            headphoneMotionManager = CMHeadphoneMotionManager()
        }

        guard let motionManager = headphoneMotionManager, !motionManager.isDeviceMotionActive else {
            return
        }

        if !motionManager.isDeviceMotionAvailable {
            Logger.info("Headphone motion currently unavailable; head tracking will engage when supported headphones connect")
        }

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }

            if let error = error {
                // e.g. motion access denied; fall back to fixed spatialization
                Logger.warning("Headphone motion error, disabling head tracking: \(error.localizedDescription)")
                self.stopHeadTracking()
                return
            }

            guard let motion = motion, self.spatialAudioEnabled, self.headTrackingEnabled else { return }

            // CMAttitude: positive yaw is counterclockwise (head turning left), while
            // AVAudio3DAngularOrientation: positive yaw is clockwise (head turning right),
            // so yaw is negated to keep the sound stage anchored in space
            self.environmentNode?.listenerAngularOrientation = AVAudio3DAngularOrientation(
                yaw: -Float(motion.attitude.yaw * 180 / .pi),
                pitch: Float(motion.attitude.pitch * 180 / .pi),
                roll: Float(motion.attitude.roll * 180 / .pi)
            )
        }

        Logger.info("Started headphone motion updates for head tracking")
    }

    private func stopHeadTracking() {
        guard let motionManager = headphoneMotionManager, motionManager.isDeviceMotionActive else {
            return
        }

        motionManager.stopDeviceMotionUpdates()
        environmentNode?.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        Logger.info("Stopped headphone motion updates")
    }

    private func setupStereoWidening(engine: AVAudioEngine) {
        let delay = AVAudioUnitDelay()
        delay.delayTime = 0.020
        delay.wetDryMix = 50
        delay.feedback = -10
        delay.lowPassCutoff = 15000
        delay.bypass = !stereoWideningEnabled
        
        engine.attach(delay)
        self.stereoWideningNode = delay

        Logger.info("Attached delay node (Haas effect stereo widening)")
    }

    private func setupEqualizer(engine: AVAudioEngine) {
        let eq = AVAudioUnitEQ(numberOfBands: 10)
        
        for (index, frequency) in eqFrequencies.enumerated() {
            let band = eq.bands[index]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1.0
            band.gain = currentEQGains[index]
            band.bypass = false
        }
        eq.globalGain = preampGain
        eq.bypass = !eqEnabled
        
        engine.attach(eq)
        self.eqNode = eq
        Logger.info("Attached EQ node to engine")
    }
    
    private func calculateGainCompensation() -> Float {
        guard eqEnabled else { return 0 }
        
        let maxBandGain = currentEQGains.max() ?? 0
        
        if maxBandGain > 0 {
            // Offset max gain to prevent audio
            // distortion due to signal clipping
            return -(maxBandGain + 1.0)
        }
        return 0
    }
    
    private func applyEffectivePreamp() {
        let compensation = calculateGainCompensation()
        preampGain = userPreampGain + compensation
        
        if !effectsAttached {
            setupAudioEffects()
        }
        
        eqNode?.globalGain = preampGain
    }
}

// MARK: - Private Delegate Bridge

/// Internal class that bridges SFBAudioEngine delegate callbacks to PAudioPlayer
private class SFBAudioPlayerDelegateBridge: NSObject, SFBAudioEngine.AudioPlayer.Delegate {
    weak var owner: PAudioPlayer?
    
    init(owner: PAudioPlayer) {
        self.owner = owner
        super.init()
    }
    
    func audioPlayer(
        _ audioPlayer: SFBAudioEngine.AudioPlayer,
        playbackStateChanged playbackState: SFBAudioEngine.AudioPlayer.PlaybackState
    ) {
        owner?.handlePlaybackStateChanged(playbackState)
    }
    
    func audioPlayerEndOfAudio(_ audioPlayer: SFBAudioEngine.AudioPlayer) {
        owner?.handleEndOfAudio()
    }
    
    func audioPlayer(
        _ audioPlayer: SFBAudioEngine.AudioPlayer,
        encounteredError error: Error
    ) {
        owner?.handleError(error)
    }
    
    func audioPlayer(
        _ audioPlayer: SFBAudioEngine.AudioPlayer,
        reconfigureProcessingGraph engine: AVAudioEngine,
        with format: AVAudioFormat
    ) -> AVAudioNode {
        owner?.reconfigureAudioGraph(engine: engine, format: format) ?? engine.mainMixerNode
    }
}
