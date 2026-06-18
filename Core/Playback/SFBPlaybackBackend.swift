//
// SFBPlaybackBackend
//
// The SFBAudioEngine-backed `PlaybackBackend`. This is the original `PAudioPlayer`
// implementation moved behind the `PlaybackEngine` facade unchanged: it keeps all of
// the SFBAudioEngine + AVAudioEngine graph code (EQ nodes, stereo widening, preamp
// compensation, processing-graph reconfiguration, and the network-volume pre-buffer
// branch). The only structural change from `PAudioPlayer` is that playback events are
// reported to `backendDelegate` (the facade) instead of directly to the app.
//

import AVFoundation
import Foundation
import SFBAudioEngine

typealias SFBPlayer = SFBAudioEngine.AudioPlayer
typealias SFBPlayerPlaybackState = SFBAudioEngine.AudioPlayer.PlaybackState

// MARK: - SFBPlaybackBackend

final class SFBPlaybackBackend: NSObject, PlaybackBackend {
    // MARK: - Backend Surface

    weak var backendDelegate: PlaybackBackendDelegate?

    var volume: Float {
        get {
            sfbPlayer.volume
        }
        set {
            do {
                try sfbPlayer.setVolume(newValue)
            } catch {
                Logger.error("Failed to set volume: \(error)")
            }
        }
    }

    private(set) var state: AudioPlayerState = .ready {
        didSet {
            guard oldValue != state else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.backendDelegate?.backendStateChanged(with: self.state, previous: oldValue)
            }
        }
    }

    /// Current playback progress in seconds
    var currentPlaybackProgress: Double {
        sfbPlayer.currentTime ?? 0
    }

    /// Total duration of current file in seconds
    var duration: Double {
        sfbPlayer.totalTime ?? 0
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

    // MARK: - Initialization

    override init() {
        self.sfbPlayer = SFBPlayer()
        super.init()

        // Create and set up the delegate bridge for playback event monitoring
        self.delegateBridge = SFBAudioPlayerDelegateBridge(owner: self)
        self.sfbPlayer.delegate = self.delegateBridge
    }

    deinit {
        sfbPlayer.stop()
    }

    // MARK: - Gapless lookahead (unsupported)

    // SFBAudioEngine plays one URL at a time; the app drives end-of-track advance.
    let supportsGaplessQueue = false

    func setNextTrack(url: URL, entryId: AudioEntryId) {}
    func clearNextTrack() {}

    // MARK: - Playback Control

    /// Play an audio file from URL
    /// - Parameters:
    ///   - url: The URL of the audio file
    ///   - startPaused: If true, loads the file but doesn't start playback
    func play(url: URL, entryId: AudioEntryId, startPaused: Bool = false) {
        currentURL = url
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
    func pause() {
        guard state == .playing else { return }
        sfbPlayer.pause()
        state = .paused
        Logger.info("Playback paused")
    }

    /// Resume playback
    func resume() {
        guard state == .paused else { return }

        do {
            try sfbPlayer.play()
            state = .playing
            Logger.info("Playback resumed")
        } catch {
            Logger.error("Failed to resume playback: \(error)")
            backendDelegate?.backendUnexpectedError(error: .engineError(error))
        }
    }

    /// Stop playback
    func stop() {
        guard state != .stopped else { return }

        let wasPlaying = state == .playing
        let currentProgress = currentPlaybackProgress
        let currentDuration = duration
        let entryId = currentEntryId

        sfbPlayer.stop()
        state = .stopped

        if wasPlaying, let entryId = entryId {
            backendDelegate?.backendDidFinishPlaying(
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
    func togglePlayPause() {
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
            backendDelegate?.backendUnexpectedError(error: .engineError(error))
        }
    }

    /// Seek to a specific time in seconds
    /// - Parameter time: The target time in seconds
    /// - Returns: true if seek was successful
    @discardableResult
    func seek(to time: Double) -> Bool {
        guard time >= 0 else { return false }

        let success = sfbPlayer.seek(time: time)

        if !success {
            Logger.error("Failed to seek to time: \(time)")
            backendDelegate?.backendUnexpectedError(error: .seekError)
        }

        return success
    }

    /// Seek forward by a number of seconds
    /// - Parameter seconds: Number of seconds to skip forward
    /// - Returns: true if seek was successful
    @discardableResult
    func seekForward(_ seconds: Double) -> Bool {
        sfbPlayer.seek(forward: seconds)
    }

    /// Seek backward by a number of seconds
    /// - Parameter seconds: Number of seconds to skip backward
    /// - Returns: true if seek was successful
    @discardableResult
    func seekBackward(_ seconds: Double) -> Bool {
        sfbPlayer.seek(backward: seconds)
    }

    // MARK: - Audio Equalizer

    /// Enable or disable stereo widening effect
    /// - Parameter enabled: boolean for the current state of stereo widening
    func setStereoWidening(enabled: Bool) {
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
    func isStereoWideningEnabled() -> Bool {
        stereoWideningEnabled
    }

    /// Enable or disable the equalizer
    /// - Parameter enabled: boolean for the current state Equalizer
    func setEQEnabled(_ enabled: Bool) {
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
    func isEQEnabled() -> Bool {
        eqEnabled
    }

    /// Apply an EQ preset
    /// - Parameter preset: The EqualizerPreset to apply
    func applyEQPreset(_ preset: EqualizerPreset) {
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
    func applyEQCustom(gains: [Float]) {
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
    func setPreamp(_ gain: Float) {
        userPreampGain = max(-12.0, min(12.0, gain))
        applyEffectivePreamp()
        Logger.info("Preamp set to \(userPreampGain) dB (effective: \(preampGain) dB)")
    }

    /// Get the current preamp gain value
    /// - Returns: Current preamp gain in dB
    func getPreamp() -> Float {
        userPreampGain
    }

    // MARK: - Internal Methods (called by delegate bridge)

    func handlePlaybackStateChanged(_ newState: SFBPlayerPlaybackState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch newState {
            case .playing:
                if self.state != .playing {
                    self.state = .playing
                    if let entryId = self.currentEntryId {
                        self.backendDelegate?.backendDidStartPlaying(with: entryId)
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

    func handleEndOfAudio() {
        let finalProgress = currentPlaybackProgress
        let finalDuration = duration

        if let entryId = currentEntryId {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.state = .stopped
                self.backendDelegate?.backendDidFinishPlaying(
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
    func reconfigureAudioGraph(engine: AVAudioEngine, format: AVAudioFormat) -> AVAudioNode {
        Logger.info("Reconfiguring audio graph for format: \(format.sampleRate)Hz, \(format.channelCount)ch")

        guard effectsAttached else {
            Logger.info("No effects attached, connecting directly to mixer")
            return engine.mainMixerNode
        }

        // Detach and recreate effect nodes with the new format
        if let oldStereoNode = stereoWideningNode {
            engine.detach(oldStereoNode)
            stereoWideningNode = nil
        }

        if let oldEQNode = eqNode {
            engine.detach(oldEQNode)
            eqNode = nil
        }

        // Recreate the effects chain
        setupStereoWidening(engine: engine)
        setupEqualizer(engine: engine)

        let mainMixer = engine.mainMixerNode

        if let stereoNode = stereoWideningNode, let equalizer = eqNode {
            engine.connect(stereoNode, to: equalizer, format: format)
            engine.connect(equalizer, to: mainMixer, format: format)
            Logger.info("Reconfigured audio graph: playerNode -> stereoWidening -> EQ -> mainMixer")

            return stereoNode
        }

        Logger.warning("Failed to reconfigure effects chain, falling back to mixer")
        return mainMixer
    }

    func handleError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.backendDelegate?.backendUnexpectedError(error: .engineError(error))
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

        backendDelegate?.backendUnexpectedError(error: .engineError(error))
        backendDelegate?.backendDidFinishPlaying(
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
            setupStereoWidening(engine: engine)
            setupEqualizer(engine: engine)

            guard let stereoNode = stereoWideningNode, let equalizer = eqNode else {
                Logger.warning("Failed to create effect nodes")
                return
            }

            // Disconnect sourceNode from mainMixer
            engine.disconnectNodeOutput(sourceNode)

            // Connect: sourceNode -> stereoWidening -> EQ -> mainMixer
            engine.connect(sourceNode, to: stereoNode, format: format)
            engine.connect(stereoNode, to: equalizer, format: format)
            engine.connect(equalizer, to: mainMixer, format: format)

            effectsAttached = true
            Logger.info("Audio effects setup complete")
        }
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
        EqualizerHeadroomCompensation.gainOffset(
            eqEnabled: eqEnabled,
            gains: currentEQGains
        )
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

/// Internal class that bridges SFBAudioEngine delegate callbacks to SFBPlaybackBackend
private class SFBAudioPlayerDelegateBridge: NSObject, SFBAudioEngine.AudioPlayer.Delegate {
    weak var owner: SFBPlaybackBackend?

    init(owner: SFBPlaybackBackend) {
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
