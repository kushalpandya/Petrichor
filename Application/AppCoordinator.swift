import SwiftUI

class AppCoordinator: ObservableObject {
    // MARK: - Managers

    private(set) static var shared: AppCoordinator?

    let libraryManager: LibraryManager
    let playlistManager: PlaylistManager
    let playbackManager: PlaybackManager
    let menuBarManager: MenuBarManager
    let scrobbleManager: ScrobbleManager

    private let sessionStore: PlaybackSessionStore
    private var restorationGeneration: UInt64 = 0
    private var restorationTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        sessionStore = PlaybackSessionStore()
        libraryManager = LibraryManager()
        playlistManager = PlaylistManager()
        playbackManager = PlaybackManager(libraryManager: libraryManager, playlistManager: playlistManager)

        playlistManager.setAudioPlayer(playbackManager)
        playlistManager.setLibraryManager(libraryManager)
        playbackManager.connectRemoteCommandCenter()
        menuBarManager = MenuBarManager(playbackManager: playbackManager, playlistManager: playlistManager)
        scrobbleManager = ScrobbleManager()

        Self.shared = self

        InternetRadioManager.shared.prepareForLaunch(
            stations: libraryManager.databaseManager.loadStationSummaries()
        )
        InternetRadioManager.shared.loadStations()

        if let session = sessionStore.load() {
            restorePresentation(from: session)
            restorationGeneration = playbackManager.sourceGeneration
            restorationTask = Task { await restore(session, expecting: restorationGeneration) }
        }
    }

    deinit {
        restorationTask?.cancel()
    }

    // MARK: - Persistence

    func savePlaybackState() {
        savePlaybackState(synchronous: true)
    }

    func savePlaybackState(synchronous: Bool) {
        guard playbackManager.restoredUITrack == nil else { return }
        guard let session = makeSession() else {
            sessionStore.clear()
            return
        }
        if synchronous {
            sessionStore.flush(session)
        } else {
            sessionStore.save(session)
        }
        Logger.info("Playback session saved")
    }

    func clearSavedPlaybackSession() {
        restorationTask?.cancel()
        restorationTask = nil
        sessionStore.clear()
        playbackManager.restoredUITrack = nil
    }

    func cancelPlaybackRestoration() {
        guard restorationTask != nil else { return }
        restorationTask?.cancel()
        restorationTask = nil
        playbackManager.beginSourceGeneration()
        playbackManager.abandonSessionRestoration()
    }

    // MARK: - Session Snapshot

    private func makeSession() -> PlaybackSession? {
        let foreground: PlaybackSession.Foreground
        if let station = playbackManager.currentStation, let stationID = station.id {
            foreground = .radio(PlaybackSession.RadioForeground(
                stationID: stationID,
                artworkID: station.artworkCacheID,
                presentation: presentation(
                    title: station.name,
                    artist: playbackManager.streamNowPlayingTitle ?? station.description ?? "",
                    album: nil,
                    duration: nil,
                    artworkData: station.artworkData
                )
            ))
        } else if let track = playbackManager.currentTrack, track.trackId != nil {
            let occurrenceID = playlistManager.currentQueue.indices.contains(playlistManager.currentQueueIndex)
                ? queueOccurrenceID(at: playlistManager.currentQueueIndex)
                : nil
            foreground = .local(PlaybackSession.LocalForeground(
                track: PlaybackSession.TrackReference(track),
                queueOccurrenceID: occurrenceID,
                position: playbackManager.actualCurrentTime,
                presentation: presentation(
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: track.duration,
                    artworkData: track.artworkData
                )
            ))
        } else if playlistManager.currentQueue.isEmpty {
            return nil
        } else {
            foreground = .none
        }

        let entries = playlistManager.currentQueue.enumerated().map { index, track in
            PlaybackSession.QueueEntry(
                occurrenceID: queueOccurrenceID(at: index),
                track: PlaybackSession.TrackReference(track)
            )
        }
        let cursorID = playlistManager.currentQueue.indices.contains(playlistManager.currentQueueIndex)
            ? entries[playlistManager.currentQueueIndex].occurrenceID
            : nil

        return PlaybackSession(
            formatVersion: PlaybackSession.formatVersion,
            appVersion: AppInfo.version,
            appBuild: AppInfo.build,
            foreground: foreground,
            queue: PlaybackSession.SavedQueue(
                entries: entries,
                cursorOccurrenceID: cursorID,
                context: savedQueueContext()
            ),
            transport: PlaybackSession.Transport(
                volume: playbackManager.volume,
                shuffleEnabled: playlistManager.isShuffleEnabled,
                repeatMode: playlistManager.repeatMode
            )
        )
    }

    private func queueOccurrenceID(at index: Int) -> UUID {
        // Stable for a single captured session and distinct for duplicate queue entries.
        let upper = UInt32(truncatingIfNeeded: index)
        let lower = UInt64(bitPattern: Int64(index + 1))
        let raw = String(
            format: "%08X-0000-0000-%04X-%012llX",
            upper,
            UInt16(truncatingIfNeeded: index),
            lower
        )
        return UUID(uuidString: raw) ?? UUID()
    }

    private func savedQueueContext() -> PlaybackSession.QueueContext {
        switch playlistManager.currentQueueSource {
        case .library:
            return .library
        case .folder:
            let path = playlistManager.currentQueue
                .first?.folderId
                .flatMap { id in
                    libraryManager.folders.first { $0.id == id }?.url.path
                }
            return .folder(path: path)
        case .playlist:
            return playlistManager.currentPlaylist.map { .playlist(id: $0.id) } ?? .detached
        }
    }

    private func presentation(
        title: String,
        artist: String,
        album: String?,
        duration: Double?,
        artworkData: Data?
    ) -> PlaybackSession.Presentation {
        let colors = UserDefaults.standard.bool(forKey: "useArtworkColors")
            ? ArtworkColorSnapshot(colors: playbackManager.nowPlayingSource?.dominantColors ?? [])
            : nil
        return PlaybackSession.Presentation(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkData: artworkData,
            artworkColors: colors
        )
    }

    // MARK: - Restoration

    private func restorePresentation(from session: PlaybackSession) {
        playbackManager.setVolume(session.transport.volume)
        playlistManager.isShuffleEnabled = session.transport.shuffleEnabled
        playlistManager.repeatMode = session.transport.repeatMode

        switch session.foreground {
        case .none:
            break
        case .local(let local):
            playbackManager.restoreUIState(local.presentation, position: local.position)
        case .radio(let radio):
            guard let station = libraryManager.databaseManager.loadStation(id: radio.stationID) else { return }
            let colors = radio.artworkID == station.artworkCacheID ? radio.presentation.artworkColors : nil
            playbackManager.restoreStation(station, colorSnapshot: colors)
        }
    }

    @MainActor
    private func restore(_ session: PlaybackSession, expecting generation: UInt64) async {
        let references = session.queue.entries.map(\.track) + foregroundReferences(session.foreground)
        let databaseManager = libraryManager.databaseManager
        let resolved: [PlaybackSession.TrackReference: Track]
        do {
            resolved = try await Task.detached(priority: .userInitiated) {
                try databaseManager.resolveTrackReferences(references)
            }.value
        } catch {
            Logger.error("Failed to restore playback session tracks: \(error)")
            playbackManager.abandonSessionRestoration()
            restorationTask = nil
            return
        }

        guard !Task.isCancelled, playbackManager.sourceGeneration == generation else { return }

        let surviving = session.queue.entries.enumerated().compactMap { oldIndex, entry -> RestoredEntry? in
            resolved[entry.track].map {
                RestoredEntry(oldIndex: oldIndex, occurrenceID: entry.occurrenceID, track: $0)
            }
        }
        var restoredTracks = surviving.map(\.track)
        let queueSource = runtimeQueueSource(session.queue.context)
        let playlist = restoredPlaylist(session.queue.context)

        switch session.foreground {
        case .radio:
            playlistManager.installRestoredQueue(restoredTracks, cursor: nil, source: queueSource, playlist: playlist)
            restorationTask = nil
        case .local(let local):
            let cursor = restoredCursor(local: local, queue: session.queue, surviving: surviving)
            playlistManager.installRestoredQueue(restoredTracks, cursor: cursor, source: queueSource, playlist: playlist)

            guard let cursor, restoredTracks.indices.contains(cursor) else {
                playbackManager.abandonSessionRestoration()
                playbackManager.currentTrack = nil
                restorationTask = nil
                return
            }
            let nextIndex = restoredSuccessorIndex(after: cursor, count: restoredTracks.count)
            let hydrationIndices = Set([cursor, nextIndex].compactMap { $0 })
            let ids = hydrationIndices.compactMap { restoredTracks[$0].trackId }
            let hydrated = await Task.detached(priority: .userInitiated) {
                databaseManager.getTracksWithArtwork(byIds: Array(Set(ids)))
            }.value
            guard !Task.isCancelled, playbackManager.sourceGeneration == generation else { return }

            let hydratedByID = Dictionary(uniqueKeysWithValues: hydrated.compactMap { track in
                track.trackId.map { ($0, track) }
            })
            for index in hydrationIndices {
                guard let trackID = restoredTracks[index].trackId,
                      let hydratedTrack = hydratedByID[trackID] else { continue }
                restoredTracks[index] = hydratedTrack
                playlistManager.currentQueue[index] = hydratedTrack
            }
            let current = restoredTracks[cursor]
            let fileIsAvailable = FileManager.default.isReadableFile(atPath: current.url.path)
            let position = matches(local.track, current) && fileIsAvailable ? local.position : 0
            playbackManager.prepareTrackForRestoration(
                current,
                at: position,
                queueIndex: cursor,
                expecting: generation
            ) { [weak self] in
                self?.restorationTask = nil
            }
            Logger.info("Playback session restored")
        case .none:
            let cursor = restoredCursor(queue: session.queue, surviving: surviving)
            playlistManager.installRestoredQueue(restoredTracks, cursor: cursor, source: queueSource, playlist: playlist)
            restorationTask = nil
        }
    }

    // MARK: - Queue Reconciliation

    private struct RestoredEntry {
        let oldIndex: Int
        let occurrenceID: UUID
        let track: Track
    }

    private func restoredSuccessorIndex(after cursor: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        switch playlistManager.repeatMode {
        case .one:
            return cursor
        case .all:
            return (cursor + 1) % count
        case .off:
            let next = cursor + 1
            return next < count ? next : nil
        }
    }

    private func foregroundReferences(_ foreground: PlaybackSession.Foreground) -> [PlaybackSession.TrackReference] {
        if case .local(let local) = foreground { return [local.track] }
        return []
    }

    private func restoredCursor(
        local: PlaybackSession.LocalForeground,
        queue: PlaybackSession.SavedQueue,
        surviving: [RestoredEntry]
    ) -> Int? {
        if let occurrenceID = local.queueOccurrenceID,
           let index = surviving.firstIndex(where: { $0.occurrenceID == occurrenceID }) {
            return index
        }
        if let index = surviving.firstIndex(where: { matches(local.track, $0.track) }) { return index }
        return fallbackCursor(queue: queue, surviving: surviving)
    }

    private func restoredCursor(
        queue: PlaybackSession.SavedQueue,
        surviving: [RestoredEntry]
    ) -> Int? {
        guard let cursor = queue.cursorOccurrenceID else { return nil }
        if let index = surviving.firstIndex(where: { $0.occurrenceID == cursor }) {
            return index
        }
        return fallbackCursor(queue: queue, surviving: surviving)
    }

    private func fallbackCursor(
        queue: PlaybackSession.SavedQueue,
        surviving: [RestoredEntry]
    ) -> Int? {
        guard !surviving.isEmpty else { return nil }
        let oldCursor = queue.cursorOccurrenceID
            .flatMap { id in queue.entries.firstIndex { $0.occurrenceID == id } } ?? 0
        return surviving.firstIndex { $0.oldIndex >= oldCursor } ?? surviving.indices.last
    }

    private func matches(_ reference: PlaybackSession.TrackReference, _ track: Track) -> Bool {
        if let id = reference.databaseID, id == track.trackId { return true }
        return reference.path == track.url.path
    }

    private func runtimeQueueSource(_ context: PlaybackSession.QueueContext) -> PlaylistManager.QueueSource {
        switch context {
        case .folder: return .folder
        case .playlist: return .playlist
        case .library, .detached: return .library
        }
    }

    private func restoredPlaylist(_ context: PlaybackSession.QueueContext) -> Playlist? {
        guard case .playlist(let id) = context else { return nil }
        return playlistManager.playlists.first { $0.id == id }
    }
}
