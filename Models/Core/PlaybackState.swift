import Foundation

struct PlaybackUIState: Codable {
    let trackTitle: String
    let trackArtist: String
    let trackAlbum: String
    let artworkData: Data?
    let playbackPosition: Double
    let trackDuration: Double
    let volume: Float
}

struct PlaybackState: Codable {
    static let currentVersion = 1
    let version: Int

    // Track identification
    let currentTrackPath: String?
    let currentTrackId: Int64?

    // Playback position
    let playbackPosition: Double
    let trackDuration: Double

    // Queue state
    let queueTrackPaths: [String]
    let queueTrackIds: [Int64]
    let currentQueueIndex: Int
    let queueSource: String // "library", "folder", "playlist"
    let sourceIdentifier: String? // folder path or playlist ID

    // Playback settings
    let volume: Float
    let isMuted: Bool
    let shuffleEnabled: Bool
    let repeatMode: String // "off", "one", "all"

    // Metadata for validation
    let savedDate: Date
    let appVersion: String

    init(
        currentTrack: Track?,
        playbackPosition: Double,
        queue: [Track],
        currentQueueIndex: Int,
        queueSource: PlaylistManager.QueueSource,
        sourceIdentifier: String? = nil,
        volume: Float,
        isMuted: Bool,
        shuffleEnabled: Bool,
        repeatMode: RepeatMode
    ) {
        self.version = Self.currentVersion
        self.currentTrackPath = currentTrack?.url.path
        self.currentTrackId = currentTrack?.trackId
        self.playbackPosition = playbackPosition
        self.trackDuration = currentTrack?.duration ?? 0

        self.queueTrackPaths = queue.map { $0.url.path }
        self.queueTrackIds = queue.compactMap { $0.trackId }
        self.currentQueueIndex = currentQueueIndex

        // Convert queue source to string
        switch queueSource {
        case .library:
            self.queueSource = "library"
        case .folder:
            self.queueSource = "folder"
        case .playlist:
            self.queueSource = "playlist"
        }

        self.sourceIdentifier = sourceIdentifier
        self.volume = volume
        self.isMuted = isMuted
        self.shuffleEnabled = shuffleEnabled

        // Convert repeat mode to string
        switch repeatMode {
        case .off:
            self.repeatMode = "off"
        case .one:
            self.repeatMode = "one"
        case .all:
            self.repeatMode = "all"
        }

        self.savedDate = Date()
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Check version first
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0

        // If version is incompatible, throw an error
        if version > Self.currentVersion {
            throw PlaybackStateError.incompatibleVersion
        }

        self.version = version

        // Decode all other properties
        self.currentTrackPath = try container.decodeIfPresent(String.self, forKey: .currentTrackPath)
        self.currentTrackId = try container.decodeIfPresent(Int64.self, forKey: .currentTrackId)
        self.playbackPosition = try container.decode(Double.self, forKey: .playbackPosition)
        self.trackDuration = try container.decode(Double.self, forKey: .trackDuration)
        self.queueTrackPaths = try container.decode([String].self, forKey: .queueTrackPaths)
        self.queueTrackIds = try container.decode([Int64].self, forKey: .queueTrackIds)
        self.currentQueueIndex = try container.decode(Int.self, forKey: .currentQueueIndex)
        self.queueSource = try container.decode(String.self, forKey: .queueSource)
        self.sourceIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceIdentifier)
        self.volume = try container.decode(Float.self, forKey: .volume)
        self.isMuted = try container.decode(Bool.self, forKey: .isMuted)
        self.shuffleEnabled = try container.decode(Bool.self, forKey: .shuffleEnabled)
        self.repeatMode = try container.decode(String.self, forKey: .repeatMode)
        self.savedDate = try container.decode(Date.self, forKey: .savedDate)
        self.appVersion = try container.decode(String.self, forKey: .appVersion)
    }

    // Helper to convert back to RepeatMode enum
    var repeatModeEnum: RepeatMode {
        switch repeatMode {
        case "one": return .one
        case "all": return .all
        default: return .off
        }
    }

    // Helper to convert back to QueueSource enum
    var queueSourceEnum: PlaylistManager.QueueSource {
        switch queueSource {
        case "folder": return .folder
        case "playlist": return .playlist
        default: return .library
        }
    }

    func createUIState(from track: Track?) -> PlaybackUIState? {
        guard let track = track else { return nil }

        return PlaybackUIState(
            trackTitle: track.title,
            trackArtist: track.artist,
            trackAlbum: track.album,
            artworkData: track.artworkData,
            playbackPosition: playbackPosition,
            trackDuration: trackDuration,
            volume: volume
        )
    }
}

enum PlaybackStateError: Error {
    case incompatibleVersion
    case corruptedData
}
