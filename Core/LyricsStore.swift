import Foundation
import GRDB

/// Single-flight, single-entry lyrics cache shared by every `TrackLyricsContent`
/// instance (main window, mini player, immersive mode).
@MainActor
final class LyricsStore {
    static let shared = LyricsStore()
    private init() {}

    struct Lyrics {
        let trackId: UUID
        let lines: [LyricLine]
        let hasTimed: Bool
    }

    private var cached: Lyrics?
    private var inFlight: [UUID: Task<Lyrics, Error>] = [:]

    func cachedLyrics(for trackId: UUID) -> Lyrics? {
        guard let cached, cached.trackId == trackId else { return nil }
        return cached
    }

    func lyrics(
        for track: Track,
        using dbQueue: DatabaseQueue,
        databaseManager: DatabaseManager?,
        forceReload: Bool = false
    ) async throws -> Lyrics {
        if !forceReload, let cached, cached.trackId == track.id {
            return cached
        }

        // Join an in-progress load for the same track rather than starting another.
        if !forceReload, let existing = inFlight[track.id] {
            return try await existing.value
        }

        let trackId = track.id
        let task = Task { () throws -> Lyrics in
            let result = try await LyricsLoader.loadLyrics(
                for: track,
                using: dbQueue,
                databaseManager: databaseManager
            )
            let hasTimed = result.lyrics.contains { $0.startTime > 0 || $0.endTime != nil }
            return Lyrics(trackId: trackId, lines: result.lyrics, hasTimed: hasTimed)
        }
        inFlight[trackId] = task
        defer { inFlight[trackId] = nil }

        let result = try await task.value
        cached = result
        return result
    }
}
