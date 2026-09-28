import Combine
import Foundation
import GRDB

/// Single-flight, single-entry lyrics cache shared by every `TrackLyricsContent`
/// instance (main window, mini player, immersive mode).
@MainActor
final class LyricsStore: ObservableObject {
    static let shared = LyricsStore()
    private init() {}

    struct Lyrics {
        let trackId: UUID
        let lines: [LyricLine]
        let hasTimed: Bool
    }

    private struct LoadResult {
        let lyrics: Lyrics
        let source: LyricsSource
        let fullTrack: FullTrack?
    }

    @Published private(set) var cached: Lyrics?
    private var inFlight: [UUID: (id: UUID, task: Task<LoadResult, Error>)] = [:]
    private var timedUpgradeTask: Task<Void, Never>?
    private var timedUpgradeAttempted = false

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
            return try await existing.task.value.lyrics
        }

        let trackId = track.id
        let obsoleteTrackIds = inFlight.keys.filter { forceReload || $0 != trackId }
        for obsoleteTrackId in obsoleteTrackIds {
            inFlight[obsoleteTrackId]?.task.cancel()
            inFlight[obsoleteTrackId] = nil
        }
        if cached?.trackId != trackId || forceReload {
            timedUpgradeTask?.cancel()
            timedUpgradeTask = nil
            timedUpgradeAttempted = false
        }
        let requestId = UUID()
        let task = Task { () throws -> LoadResult in
            let result = try await LyricsLoader.loadLyrics(
                for: track,
                using: dbQueue,
                databaseManager: databaseManager
            )
            let lyrics = Lyrics(trackId: trackId, lines: result.lyrics, hasTimed: result.lyrics.hasTimedLyrics)
            return LoadResult(lyrics: lyrics, source: result.source, fullTrack: result.fullTrack)
        }
        inFlight[trackId] = (requestId, task)
        defer {
            if inFlight[trackId]?.id == requestId {
                inFlight[trackId] = nil
            }
        }

        let result = try await task.value
        guard inFlight[trackId]?.id == requestId else { throw CancellationError() }
        if case .online = result.source, !result.lyrics.hasTimed {
            timedUpgradeAttempted = true
        }
        cached = result.lyrics
        startTimedUpgradeIfNeeded(
            for: trackId,
            lyrics: result.lyrics,
            fullTrack: result.fullTrack,
            databaseManager: databaseManager
        )
        return result.lyrics
    }

    private func startTimedUpgradeIfNeeded(
        for trackId: UUID,
        lyrics: Lyrics,
        fullTrack: FullTrack?,
        databaseManager: DatabaseManager?
    ) {
        guard !lyrics.lines.isEmpty,
              !lyrics.hasTimed,
              !timedUpgradeAttempted,
              LyricsManager.shared.isOnlineLyricsEnabled,
              let fullTrack,
              let databaseManager else {
            return
        }

        timedUpgradeAttempted = true
        timedUpgradeTask = Task {
            guard let onlineText = await LyricsManager.shared.fetchLyrics(
                      for: fullTrack,
                      using: databaseManager,
                      onlyIfTimed: true
                  ),
                  !Task.isCancelled else {
                return
            }

            let lines = LyricLine.parseLRC(from: onlineText)
            guard cached?.trackId == trackId else { return }
            cached = Lyrics(trackId: trackId, lines: lines, hasTimed: true)
        }
    }
}
