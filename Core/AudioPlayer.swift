import AVFoundation
import Foundation

// MARK: - EQ Preset

/// Available EQ presets matching Apple Music presets
enum EQPreset: String, CaseIterable {
    case flat = "flat"
    case acoustic = "acoustic"
    case classical = "classical"
    case dance = "dance"
    case deep = "deep"
    case electronic = "electronic"
    case hipHop = "hiphop"
    case increaseBass = "increasebass"
    case increaseTreble = "increasetreble"
    case increaseVocals = "increasevocals"
    case jazz = "jazz"
    case latin = "latin"
    case loudness = "loudness"
    case lounge = "lounge"
    case piano = "piano"
    case pop = "pop"
    case rnb = "rnb"
    case reduceBass = "reducebass"
    case reduceTreble = "reducetreble"
    case rock = "rock"
    case smallSpeakers = "smallspeakers"
    case spokenWord = "spokenword"
    case wow = "wow"
    
    /// Gain values for 10 bands: 32Hz, 64Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz
    var gains: [Float] {
        switch self {
        case .flat:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .acoustic:
            return [5, 4, 3, 1, 2, 2, 3, 3, 3, 2]
        case .rock:
            return [4, 3, -1, -1, 1, 2, 3, 3, 3, 3]
        case .pop:
            return [-1, -1, 0, 2, 4, 4, 2, 0, -1, -1]
        case .jazz:
            return [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]
        case .classical:
            return [4, 3, 2, 0, 0, 0, -1, -2, -2, -3]
        case .electronic:
            return [6, 5, 3, 0, -2, 0, 2, 3, 4, 5]
        case .dance:
            return [5, 6, 4, 0, 2, 3, 4, 3, 2, 1]
        case .hipHop:
            return [7, 6, 3, 2, -1, -1, 1, 2, 3, 4]
        case .rnb:
            return [6, 5, 2, -1, -2, 1, 2, 2, 3, 4]
        case .latin:
            return [4, 3, 0, 0, -1, -1, 2, 3, 4, 5]
        case .increaseBass:
            return [8, 7, 6, 4, 2, 0, 0, 0, 0, 0]
        case .reduceBass:
            return [-6, -5, -4, -2, -1, 0, 0, 0, 0, 0]
        case .increaseTreble:
            return [0, 0, 0, 0, 0, 2, 4, 6, 7, 8]
        case .reduceTreble:
            return [0, 0, 0, 0, 0, -1, -2, -4, -5, -6]
        case .increaseVocals:
            return [-2, -1, -1, 1, 3, 4, 4, 3, 1, 0]
        case .deep:
            return [7, 6, 4, 2, 1, -1, -2, -3, -3, -4]
        case .lounge:
            return [-3, -2, -1, 1, 3, 2, 0, -1, 2, 1]
        case .piano:
            return [-1, 0, 1, 2, 3, 2, 1, 3, 4, 3]
        case .spokenWord:
            return [-3, -2, 0, 1, 3, 4, 4, 3, 2, 0]
        case .smallSpeakers:
            return [5, 4, 3, 2, 1, 0, -1, -2, -2, -3]
        case .loudness:
            return [6, 4, 0, 0, 0, 0, -1, 3, 5, 6]
        case .wow:
            return [8, 7, 5, 2, 1, 1, 2, 3, 4, 3]
        }
    }
}

// MARK: - Player State

/// Represents the current state of the audio player
public enum AudioPlayerState: Equatable {
    case ready          // Player initialized but no file loaded
    case bufferring     // Loading audio file
    case playing        // Currently playing
    case paused         // Paused
    case stopped        // Stopped
    case running        // Engine running but not playing (internal state)
    case error          // Error occurred
    case disposed       // Player has been disposed
}

// MARK: - Stop Reason

/// Reason why playback stopped
public enum AudioPlayerStopReason: Equatable {
    case eof            // Reached end of file
    case userAction     // User stopped playback
    case error          // Error occurred
    case disposed       // Player disposed
    case none           // Unknown or not applicable
}

// MARK: - Player Error

/// Errors that can occur during audio playback
public enum AudioPlayerError: Error, LocalizedError {
    case fileNotFound
    case invalidFormat
    case engineError(Error)
    case nodeError(String)
    case seekError
    case invalidState
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .invalidFormat:
            return "Unsupported audio format"
        case .engineError(let error):
            return "Audio engine error: \(error.localizedDescription)"
        case .nodeError(let message):
            return "Audio node error: \(message)"
        case .seekError:
            return "Failed to seek to position"
        case .invalidState:
            return "Invalid player state for this operation"
        }
    }
}

// MARK: - Audio Entry ID

/// Unique identifier for an audio entry
public struct AudioEntryId: Hashable {
    public let id: String
    
    public init(id: String) {
        self.id = id
    }
}

// MARK: - Delegate Protocol

/// Delegate protocol for receiving playback events
public protocol AudioPlayerDelegate: AnyObject {
    func audioPlayerDidStartPlaying(player: AudioPlayer, with entryId: AudioEntryId)
    func audioPlayerStateChanged(player: AudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState)
    func audioPlayerDidFinishPlaying(
        player: AudioPlayer,
        entryId: AudioEntryId,
        stopReason: AudioPlayerStopReason,
        progress: Double,
        duration: Double
    )
    func audioPlayerUnexpectedError(player: AudioPlayer, error: AudioPlayerError)
    
    // Optional methods with default implementations
    func audioPlayerDidFinishBuffering(player: AudioPlayer, with entryId: AudioEntryId)
    func audioPlayerDidReadMetadata(player: AudioPlayer, metadata: [String: String])
    func audioPlayerDidCancel(player: AudioPlayer, queuedItems: [AudioEntryId])
}

// MARK: - Default Implementations

public extension AudioPlayerDelegate {
    func audioPlayerDidFinishBuffering(player: AudioPlayer, with entryId: AudioEntryId) {}
    func audioPlayerDidReadMetadata(player: AudioPlayer, metadata: [String: String]) {}
    func audioPlayerDidCancel(player: AudioPlayer, queuedItems: [AudioEntryId]) {}
}

// MARK: - Audio Player

public class AudioPlayer {
    
    // MARK: - Public Properties
    
    public weak var delegate: AudioPlayerDelegate?
    
    public var volume: Float = 1.0 {
        didSet {
            playerNode.volume = volume
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
    
    /// Current playback time in seconds
    public var progress: Double {
        if state != .playing || !playerNode.isPlaying {
            return savedSeekPosition
        }
        
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
           let audioFile = audioFile {
            let sampleRate = audioFile.processingFormat.sampleRate
            let relativeTime = Double(playerTime.sampleTime) / sampleRate
            let absoluteTime = bufferStartTime + relativeTime
            
            savedSeekPosition = absoluteTime
            return absoluteTime
        }
        
        return savedSeekPosition
    }
    
    /// Total duration of current file in seconds
    public var duration: Double {
        guard let audioFile = audioFile else { return 0 }
        let sampleRate = audioFile.processingFormat.sampleRate
        return Double(audioFile.length) / sampleRate
    }
    
    // MARK: - Private Properties
    
    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let mainMixer: AVAudioMixerNode
    private let eqNode: AVAudioUnitEQ
    private let delayNode: AVAudioUnitDelay
    
    private var audioFile: AVAudioFile?
    private var currentEntryId: AudioEntryId?
    private var currentURL: URL?
    
    // Seeking support
    private var targetSeekTime: Double?
    private var isSeeking = false
    private var bufferStartTime: Double = 0.0
    
    // Completion tracking
    private var scheduleCompletionSemaphore: DispatchSemaphore?
    private var monitoringQueue: DispatchQueue
    
    // Hibernation support
    private var hibernationTimer: Timer?
    private var isHibernating = false
    private let hibernationDelay: TimeInterval = TimeConstants.pauseHibernationThreshold
    private var savedSeekPosition: Double = 0
    
    // MARK: - Initialization
    
    public init() {
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.mainMixer = engine.mainMixerNode
        self.eqNode = AVAudioUnitEQ(numberOfBands: 10)
        self.delayNode = AVAudioUnitDelay()
        self.monitoringQueue = DispatchQueue(label: "org.Petrichor.audioplayer.monitoring", qos: .userInitiated)
        
        setupAudioEngine()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Setup
    
    private func setupAudioEngine() {
        engine.attach(playerNode)
        engine.attach(delayNode)
        engine.attach(eqNode)
        
        setupStereoWidening()
        setStereoWidening(enabled: false)
        
        engine.connect(playerNode, to: delayNode, format: nil)
        engine.connect(delayNode, to: eqNode, format: nil)
        engine.connect(eqNode, to: mainMixer, format: nil)
        
        applyEQ(preset: "flat")
        
        do {
            try engine.start()
            state = .ready
        } catch {
            state = .error
            delegate?.audioPlayerUnexpectedError(player: self, error: .engineError(error))
        }
    }
    
    private func setupStereoWidening() {
        delayNode.delayTime = 0.012
        delayNode.wetDryMix = 20
        delayNode.lowPassCutoff = 15000
    }
    
    // MARK: - Public Methods
    
    /// Play audio from a URL
    /// - Parameters:
    ///   - url: URL of the audio file
    ///   - startPaused: If true, loads and schedules but doesn't start playing
    public func play(url: URL, startPaused: Bool = false) {
        if state == .playing || state == .paused {
            playerNode.stop()
        }
        
        state = .bufferring
        currentURL = url
        currentEntryId = AudioEntryId(id: url.lastPathComponent)
        bufferStartTime = 0.0
        
        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            
            if !engine.isRunning {
                try engine.start()
            }
            
            reconnectPlayerNodeIfNeeded(format: file.processingFormat)
            scheduleFile(file, at: nil)
            
            if startPaused {
                state = .paused
                savedSeekPosition = 0
            } else {
                playerNode.play()
                state = .playing
                
                if let entryId = currentEntryId {
                    delegate?.audioPlayerDidStartPlaying(player: self, with: entryId)
                    delegate?.audioPlayerDidFinishBuffering(player: self, with: entryId)
                }
                
                startCompletionMonitoring()
            }
            
        } catch {
            state = .error
            audioFile = nil
            delegate?.audioPlayerUnexpectedError(player: self, error: .engineError(error))
        }
    }
    
    /// Pause playback
    public func pause() {
        guard state == .playing else { return }
        
        savedSeekPosition = progress
        playerNode.pause()
        state = .paused
        startHibernationTimer()
    }
    
    /// Resume playback
    public func resume() {
        guard state == .paused else { return }
        
        cancelHibernation()
        
        if isHibernating {
            wakeFromHibernation()
        } else {
            playerNode.play()
            state = .playing
        }
    }
    
    /// Stop playback
    public func stop() {
        guard state != .stopped && state != .ready else { return }
        
        cancelHibernation()
        
        let previousState = state
        let currentProgress = self.progress
        let trackDuration = self.duration
        let entryId = currentEntryId
        
        playerNode.stop()
        audioFile = nil
        currentURL = nil
        savedSeekPosition = 0
        state = .stopped
        
        if let entryId = entryId, previousState == .playing || previousState == .paused {
            delegate?.audioPlayerDidFinishPlaying(
                player: self,
                entryId: entryId,
                stopReason: .userAction,
                progress: currentProgress,
                duration: trackDuration
            )
        }
    }
    
    /// Seek to a specific time
    public func seek(to time: Double) {
        guard let audioFile = audioFile else { return }
        guard time >= 0 && time <= duration else { return }
        
        isSeeking = true
        targetSeekTime = time
        savedSeekPosition = time
        
        let wasPlaying = (state == .playing)
        
        playerNode.stop()
        
        let sampleRate = audioFile.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(time * sampleRate)
        
        scheduleFile(audioFile, at: framePosition)
        
        if wasPlaying {
            playerNode.play()
            state = .playing
        } else {
            state = .paused
        }
        
        isSeeking = false
        targetSeekTime = nil
    }
    
    /// Set stereo widening effect state
    /// - Parameter enabled: true to enable stereo widening, false to disable
    public func setStereoWidening(enabled: Bool) {
        delayNode.bypass = !enabled
    }
    
    /// Apply EQ preset
    /// - Parameter preset: Name of the preset (case-insensitive)
    public func applyEQ(preset: String) {
        guard let eqPreset = EQPreset(rawValue: preset.lowercased()) else {
            Logger.error("Invalid EQ preset: \(preset). Defaulting to flat.")
            applyEQ(gains: EQPreset.flat.gains)
            return
        }
        
        applyEQ(gains: eqPreset.gains)
    }
    
    /// Apply custom EQ gains
    /// - Parameter gains: Array of 10 gain values in dB
    public func applyEQ(gains: [Float]) {
        guard gains.count == 10 else {
            Logger.error("EQ gains array must contain exactly 10 values")
            return
        }
        
        let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        
        for (index, band) in eqNode.bands.enumerated() {
            band.frequency = frequencies[index]
            band.gain = gains[index]
            band.bandwidth = 1.0
            band.bypass = false
            band.filterType = .parametric
        }
    }
    
    // MARK: - Private Methods
    
    private func scheduleFile(_ file: AVAudioFile, at framePosition: AVAudioFramePosition?) {
        let startFrame = framePosition ?? 0
        let frameCount = AVAudioFrameCount(file.length - startFrame)
        
        guard frameCount > 0 else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return
        }
        
        do {
            if let startFrame = framePosition {
                file.framePosition = startFrame
                let sampleRate = file.processingFormat.sampleRate
                bufferStartTime = Double(startFrame) / sampleRate
                savedSeekPosition = bufferStartTime
            } else {
                bufferStartTime = 0.0
            }
            
            try file.read(into: buffer)
            
            playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) { [weak self] in
                self?.handleBufferCompletion()
            }
        } catch {
            delegate?.audioPlayerUnexpectedError(player: self, error: .engineError(error))
        }
    }
    
    private func handleBufferCompletion() {
        guard state == .playing, !isSeeking else { return }
        
        let entryId = currentEntryId
        let trackDuration = self.duration
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.state = .stopped
            self.savedSeekPosition = 0
            
            if let entryId = entryId {
                self.delegate?.audioPlayerDidFinishPlaying(
                    player: self,
                    entryId: entryId,
                    stopReason: .eof,
                    progress: trackDuration,
                    duration: trackDuration
                )
            }
        }
    }
    
    private func reconnectPlayerNodeIfNeeded(format: AVAudioFormat) {
        let currentFormat = engine.outputNode.inputFormat(forBus: 0)
        if currentFormat.sampleRate == format.sampleRate,
           currentFormat.channelCount == format.channelCount {
            return
        }
        
        engine.disconnectNodeInput(playerNode)
        engine.disconnectNodeInput(delayNode)
        engine.disconnectNodeInput(eqNode)
        
        engine.connect(playerNode, to: delayNode, format: format)
        engine.connect(delayNode, to: eqNode, format: format)
        engine.connect(eqNode, to: mainMixer, format: format)
    }
    
    private func startCompletionMonitoring() {
        monitoringQueue.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            self?.checkForCompletion()
        }
    }
    
    private func checkForCompletion() {
        guard state == .playing else { return }
        
        if !playerNode.isPlaying {
            handleBufferCompletion()
        } else {
            monitoringQueue.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                self?.checkForCompletion()
            }
        }
    }
    
    private func cleanup() {
        cancelHibernation()
        playerNode.stop()
        engine.stop()
        audioFile = nil
        state = .disposed
    }
    
    // MARK: - Hibernation Management
    
    private func startHibernationTimer() {
        cancelHibernation()
        hibernationTimer = Timer.scheduledTimer(withTimeInterval: hibernationDelay, repeats: false) { [weak self] _ in
            self?.enterHibernation()
        }
    }
    
    private func cancelHibernation() {
        hibernationTimer?.invalidate()
        hibernationTimer = nil
    }
    
    private func enterHibernation() {
        guard state == .paused, !isHibernating else { return }
        
        savedSeekPosition = progress
        playerNode.stop()
        audioFile = nil
        engine.stop()
        isHibernating = true
        
        Logger.info("AudioPlayer entered hibernation mode after \(hibernationDelay)s pause")
    }
    
    private func wakeFromHibernation() {
        guard isHibernating, let url = currentURL else { return }
        
        isHibernating = false
        
        do {
            if !engine.isRunning {
                try engine.start()
            }
            
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            
            reconnectPlayerNodeIfNeeded(format: file.processingFormat)
            
            let sampleRate = file.processingFormat.sampleRate
            let framePosition = AVAudioFramePosition(savedSeekPosition * sampleRate)
            
            scheduleFile(file, at: framePosition)
            playerNode.play()
            state = .playing
            
            Logger.info("AudioPlayer woke from hibernation, restored position: \(savedSeekPosition)s")
        } catch {
            state = .error
            delegate?.audioPlayerUnexpectedError(player: self, error: .engineError(error))
            Logger.error("Failed to wake from hibernation: \(error)")
        }
    }
}
