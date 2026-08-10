import Foundation

struct PlaybackSession: Codable {
    static let formatVersion = 1

    let formatVersion: Int
    let appVersion: String
    let appBuild: String
    let foreground: Foreground
    let queue: SavedQueue
    let transport: Transport

    enum Foreground: Codable {
        case none
        case local(LocalForeground)
        case radio(RadioForeground)
    }

    struct LocalForeground: Codable {
        let track: TrackReference
        let queueOccurrenceID: UUID?
        let position: Double
        let presentation: Presentation
    }

    struct RadioForeground: Codable {
        let stationID: Int64
        let artworkID: UUID
        let presentation: Presentation
    }

    struct SavedQueue: Codable {
        let entries: [QueueEntry]
        let cursorOccurrenceID: UUID?
        let context: QueueContext
    }

    struct QueueEntry: Codable {
        let occurrenceID: UUID
        let track: TrackReference
    }

    struct TrackReference: Codable, Hashable {
        let databaseID: Int64?
        let path: String

        init(_ track: Track) {
            databaseID = track.trackId
            path = track.url.path
        }
    }

    enum QueueContext: Codable {
        case library
        case folder(path: String?)
        case playlist(id: UUID)
        case detached
    }

    struct Transport: Codable {
        let volume: Float
        let shuffleEnabled: Bool
        let repeatMode: RepeatMode
    }

    struct Presentation: Codable {
        let title: String
        let artist: String
        let album: String?
        let duration: Double?
        let artworkData: Data?
        let artworkColors: ArtworkColorSnapshot?
    }
}
