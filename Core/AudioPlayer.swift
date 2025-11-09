import AVFoundation
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
        let positionAndTime = sfbPlayer.playerNode.playbackPositionAndTime
        return positionAndTime.time.currentTime
    }
    
    /// Total duration of current file in seconds
    public var duration: Double {
        let positionAndTime = sfbPlayer.playerNode.playbackPositionAndTime
        return positionAndTime.time.totalTime
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
    
    // MARK: - Initialization
    
    public override init() {
        self.sfbPlayer = SFBPlayer()
        super.init()
        
        // Create and set up the delegate bridge for playback event monitoring
        self.delegateBridge = SFBAudioPlayerDelegateBridge(owner: self)
        self.sfbPlayer.delegate = self.delegateBridge
    }
    
    deinit {
        sfbPlayer.stop()
    }
    
    // MARK: - Playback Control
    
    /// Play an audio file from URL
    /// - Parameters:
    ///   - url: The URL of the audio file
    ///   - startPaused: If true, loads the file but doesn't start playback
    public func play(url: URL, startPaused: Bool = false) {
        currentURL = url
        currentEntryId = AudioEntryId(id: url.lastPathComponent)
        
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
            Logger.error("Failed to play audio: \(error)")
            state = .stopped
            
            if let entryId = currentEntryId {
                delegate?.audioPlayerUnexpectedError(player: self, error: .engineError(error))
                delegate?.audioPlayerDidFinishPlaying(
                    player: self,
                    entryId: entryId,
                    stopReason: .error,
                    progress: 0,
                    duration: 0
                )
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
    
    internal func handleError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.audioPlayerUnexpectedError(player: self, error: .engineError(error))
        }
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
    
    func audioPlayer(_ audioPlayer: SFBAudioEngine.AudioPlayer, playbackStateChanged playbackState: SFBAudioEngine.AudioPlayer.PlaybackState) {
        owner?.handlePlaybackStateChanged(playbackState)
    }
    
    func audioPlayerEndOfAudio(_ audioPlayer: SFBAudioEngine.AudioPlayer) {
        owner?.handleEndOfAudio()
    }
    
    func audioPlayer(_ audioPlayer: SFBAudioEngine.AudioPlayer, encounteredError error: Error) {
        owner?.handleError(error)
    }
}
