//
// PlaybackManager class extension
//
// This extension owns the engine queue mirror: Petrichor's queue lives in
// `PlaylistManager`, and this keeps the engine's copy of it in step so the engine
// can advance through the queue by itself. Positions are joined by entry id
// (`mirror`), never by assuming both arrays are index-aligned.
//

import Combine
import Foundation

extension PlaybackManager {
    /// Re-primes the repeat lookahead when the mode changes mid-track. Queue edits
    /// don't need it: they mutate the engine queue, which re-primes its own pre-decode.
    func observeRepeatModeForLookahead() {
        playlistManager.$repeatMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.currentTrack != nil else { return }
                let state = self.audioPlayer.state
                guard state == .playing || state == .paused else { return }
                self.primeRepeatLookahead()
            }
            .store(in: &queueObservers)
    }

    // MARK: - Mirror lookups

    /// Rebuilds the mirror with a fresh entry per track.
    func rebuildQueueMirror(for tracks: [Track]) {
        mirror = tracks.map { MirroredEntry(entryId: .fresh(), track: $0) }
        unmirroredTracks = [:]
        injectedNext = nil
    }

    func mirrorEntries() -> [QueueEntry] {
        mirror.map { QueueEntry(entryId: $0.entryId, url: $0.track.url) }
    }

    /// The track an entry plays, whether it is a queue member or a lookahead.
    func track(forEntry entryId: AudioEntryId) -> Track? {
        mirror.first { $0.entryId == entryId }?.track ?? unmirroredTracks[entryId.id]
    }

    /// The `currentQueue` position an entry maps to, or nil if it isn't mirrored.
    func queuePosition(ofEntry entryId: AudioEntryId) -> Int? {
        mirror.firstIndex { $0.entryId == entryId }
    }

    /// The engine index holding the entry mirrored at `position`, or nil if the
    /// engine has dropped it (an unplayable entry it removed itself).
    func engineIndex(ofQueuePosition position: Int) -> Int? {
        guard mirror.indices.contains(position) else { return nil }
        return audioPlayer.queueIndex(of: mirror[position].entryId)
    }

    /// Whether a queue is currently mirrored into the engine.
    var hasMirroredQueue: Bool {
        !mirror.isEmpty
    }

    /// The queue position now playing, for a caller resyncing its cursor.
    var mirroredQueuePosition: Int? {
        currentEntryId.flatMap { queuePosition(ofEntry: $0) }
    }

    // MARK: - Repeat lookahead

    /// Injects the successor when repeat makes it differ from the queue's natural
    /// order: repeat-one always, repeat-all at the last entry. In every other case
    /// the queue order is already right and the engine primes it unaided.
    func primeRepeatLookahead() {
        guard !mirror.isEmpty, let next = playlistManager.peekNextTrack() else {
            clearInjectedNext()
            return
        }

        guard next.index != playlistManager.currentQueueIndex + 1 else {
            // The engine's own successor is the right one.
            clearInjectedNext()
            return
        }

        if let injected = injectedNext, injected.standsInFor == next.index {
            return
        }

        clearInjectedNext()
        let entryId = AudioEntryId.fresh()
        injectedNext = InjectedNext(entryId: entryId, track: next.track, standsInFor: next.index)
        unmirroredTracks[entryId.id] = next.track
        audioPlayer.insertNext(QueueEntry(entryId: entryId, url: next.track.url))
        Logger.info("Primed repeat lookahead: \(next.track.title)")
    }

    func clearInjectedNext() {
        guard let injected = injectedNext else { return }
        audioPlayer.removeQueueEntry(id: injected.entryId)
        unmirroredTracks.removeValue(forKey: injected.entryId.id)
        injectedNext = nil
    }

    /// Folds a just-started injected entry into the mirror: it replaces the entry
    /// mirrored at `standsInFor` and moves into that slot. Both engine calls happen
    /// after the audio transition, so the boundary stays gapless.
    func absorbInjectedEntry(_ injected: InjectedNext) {
        injectedNext = nil
        unmirroredTracks.removeValue(forKey: injected.entryId.id)

        let position = injected.standsInFor
        guard mirror.indices.contains(position) else { return }

        if let displacedIndex = audioPlayer.queueIndex(of: mirror[position].entryId) {
            audioPlayer.removeQueueEntry(at: displacedIndex)
        }
        mirror[position] = MirroredEntry(entryId: injected.entryId, track: injected.track)

        // Slide it into the slot it now represents, so the engine's order still
        // matches the queue and its next pre-decode is the right track.
        if let from = audioPlayer.queueIndex(of: injected.entryId), from != position {
            audioPlayer.move(from: from, to: engineMoveDestination(from: from, to: position))
        }
    }

    /// Translates an app destination index into the pre-removal index the engine's
    /// `move` expects: it removes first, then inserts at `to - 1` for a forward move.
    private func engineMoveDestination(from: Int, to: Int) -> Int {
        to > from ? to + 1 : to
    }

    // MARK: - Following the engine

    /// Syncs app state to an engine-driven advance - the engine moved to the next
    /// entry on its own. The audio is already playing.
    func handleEngineAdvance(to entryId: AudioEntryId, track: Track) {
        restoredUITrack = nil
        currentTrack = track
        currentFullTrack = nil
        currentEntryId = entryId
        currentTime = 0
        isPlaying = true

        if let position = queuePosition(ofEntry: entryId) {
            playlistManager.advanceQueueIndex(to: position)
        }

        scrobbleManager?.trackStarted(track)
        publishNowPlayingMetadata(for: track)
        loadFullTrack(for: track)
        primeRepeatLookahead()
        Logger.info("Advanced to: \(track.title)")
    }

    /// Fetches the full record for pause/resume and the detail UI, discarding the
    /// result if the track changed while it was in flight.
    func loadFullTrack(for track: Track) {
        Task { [weak self] in
            guard let self else { return }
            let full = try? await track.fullTrack(using: self.libraryManager.databaseManager.dbQueue)
            await MainActor.run {
                if self.currentTrack?.url == track.url { self.currentFullTrack = full }
            }
        }
    }

    /// Seats `track` as the playback subject and fires the per-track side effects.
    /// The single definition of what it means for a track to become current.
    func adoptCurrentEntry(_ entryId: AudioEntryId, track: Track, at position: Double = 0) {
        pendingPlayOnRestore = false
        restoredUITrack = nil
        restoredPosition = 0
        currentTrack = track
        currentFullTrack = nil
        currentEntryId = entryId
        currentTime = position
        scrobbleManager?.trackStarted(track)
        loadFullTrack(for: track)
    }

    // MARK: - Queue mirroring (called by PlaylistManager)

    /// Installs the current queue in the engine and starts `index`.
    ///
    /// `resumeAt` is passed explicitly rather than read from `restoredPosition`: that
    /// field is also set by every seek, so picking it up here would resume a freshly
    /// chosen track at the position of the one before it.
    func startQueue(at index: Int, resumeAt: Double = 0) {
        let tracks = playlistManager.currentQueue
        guard tracks.indices.contains(index) else { return }

        guard let startIndex = firstPlayableIndex(in: tracks, from: index) else { return }
        if startIndex != index {
            playlistManager.advanceQueueIndex(to: startIndex)
        }
        let track = tracks[startIndex]

        rebuildQueueMirror(for: tracks)
        adoptCurrentEntry(mirror[startIndex].entryId, track: track, at: resumeAt)
        beginEngineSession(
            mirrorEntries(), startingAt: startIndex, entryId: mirror[startIndex].entryId, resumeAt: resumeAt
        )
        Logger.info("Started queue at: \(track.title)")
    }

    /// The first entry from `index` onward whose file is still on disk, searched in
    /// the order the current repeat mode would play them. Each entry is tested at
    /// most once: recursing through `playNextTrack` would spin forever on repeat-one
    /// and cycle forever on repeat-all.
    private func firstPlayableIndex(in tracks: [Track], from index: Int) -> Int? {
        // Repeat-one never moves off the chosen entry, so there is nothing to fall
        // back to; repeat-all wraps to the front, repeat-off stops at the end.
        let candidates: [Int]
        switch playlistManager.repeatMode {
        case .one:
            candidates = [index]
        case .all:
            candidates = (0..<tracks.count).map { (index + $0) % tracks.count }
        case .off:
            candidates = Array(index..<tracks.count)
        }

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: tracks[candidate].url.path) {
                return candidate
            }
            Logger.warning("Track file does not exist: \(tracks[candidate].url.path)")
            if candidate == index {
                NotificationManager.shared.addMessage(
                    .error, String(localized: "Cannot play '\(tracks[candidate].title)': File not found")
                )
            }
        }

        if candidates.count > 1 {
            NotificationManager.shared.addMessage(
                .error, String(localized: "No playable tracks left in the queue")
            )
        }
        return nil
    }

    /// Installs a one-entry queue for a track that isn't in `currentQueue` (a restored
    /// track before any queue exists).
    func startOffQueueTrack(_ track: Track, url: URL, resumeAt: Double) {
        let entryId = AudioEntryId.fresh()
        mirror = []
        unmirroredTracks = [entryId.id: track]
        injectedNext = nil

        adoptCurrentEntry(entryId, track: track, at: resumeAt)
        beginEngineSession(
            [QueueEntry(entryId: entryId, url: url)], startingAt: 0, entryId: entryId, resumeAt: resumeAt
        )
        Logger.info("Started playback: \(track.title)")
    }

    /// Hands the engine a queue and starts it, deferring a restore resume to the
    /// `.paused` transition the paused load produces so it can't race the async open.
    private func beginEngineSession(
        _ entries: [QueueEntry], startingAt index: Int, entryId: AudioEntryId, resumeAt: Double
    ) {
        pendingRestoreResume = resumeAt > 0 ? (entryId, resumeAt) : nil
        // Replacing a *paused* session in place hands the incoming track the outgoing
        // one's transport position; while playing, in-place keeps the switch seamless.
        if resumeAt == 0, audioPlayer.state == .paused {
            audioPlayer.stop()
        }
        audioPlayer.setQueue(entries, startingAt: index, startPaused: resumeAt > 0)
    }

    /// Jumps to a queue position, leaving the rest of the queue in place.
    func jumpToQueueEntry(at index: Int) {
        guard let engineIndex = engineIndex(ofQueuePosition: index) else {
            // Not mirrored (or the engine dropped it) - rebuild from the queue.
            startQueue(at: index)
            return
        }

        clearInjectedNext()
        pendingRestoreResume = nil
        adoptCurrentEntry(mirror[index].entryId, track: playlistManager.currentQueue[index])
        audioPlayer.playQueueEntry(at: engineIndex)
        Logger.info("Jumped to queue entry: \(playlistManager.currentQueue[index].title)")
    }

    func queueDidInsert(_ track: Track, at index: Int) {
        guard !mirror.isEmpty else { return }
        let entryId = AudioEntryId.fresh()
        let clamped = min(max(index, 0), mirror.count)
        mirror.insert(MirroredEntry(entryId: entryId, track: track), at: clamped)

        let entry = QueueEntry(entryId: entryId, url: track.url)
        // Resolve the destination through the entry that follows it, so an injected
        // lookahead between them doesn't skew the index.
        if let engineIndex = engineIndex(ofQueuePosition: clamped + 1) {
            audioPlayer.insert(entry, at: engineIndex)
        } else {
            audioPlayer.append(entry)
        }
        primeRepeatLookahead()
    }

    func queueDidAppend(_ track: Track) {
        queueDidInsert(track, at: mirror.count)
    }

    func queueDidRemove(at index: Int) {
        guard mirror.indices.contains(index) else { return }
        // Removing the engine's current entry would make it advance or stop; the
        // callers guard against it, so refuse rather than disturb playback.
        guard mirror[index].entryId != currentEntryId else { return }
        let entryId = mirror.remove(at: index).entryId
        audioPlayer.removeQueueEntry(id: entryId)
        primeRepeatLookahead()
    }

    func queueDidMove(from source: Int, to destination: Int) {
        guard mirror.indices.contains(source), mirror.indices.contains(destination) else { return }
        let entry = mirror[source]
        // Read both engine indices before mutating: afterwards the destination slot
        // holds the entry being moved.
        let from = audioPlayer.queueIndex(of: entry.entryId)
        let to = engineIndex(ofQueuePosition: destination)

        mirror.remove(at: source)
        mirror.insert(entry, at: destination)

        if let from, let to {
            audioPlayer.move(from: from, to: engineMoveDestination(from: from, to: to))
        }
        primeRepeatLookahead()
    }

    /// Drops an entry the engine discarded as undecodable. Keyed by identity and
    /// applied to the mirror and the app queue together: routing it through the
    /// index-based removal path lets either side refuse and leaves the two queues
    /// differing in membership, which every later edit assumes cannot happen.
    func dropSkippedEntry(_ entryId: AudioEntryId) {
        unmirroredTracks.removeValue(forKey: entryId.id)
        if injectedNext?.entryId == entryId {
            injectedNext = nil
        }
        guard let position = queuePosition(ofEntry: entryId) else { return }
        mirror.remove(at: position)
        playlistManager.dropQueueEntry(at: position)
    }

    func queueDidClear() {
        mirror = []
        unmirroredTracks = [:]
        injectedNext = nil
        audioPlayer.clearQueue()
    }

    /// Shuffles the upcoming entries engine-side and mirrors the resulting order back
    /// into the app queue. Engine-led because it is the only reordering that must not
    /// restart the playing track. Returns nil when there is no usable mirror, leaving
    /// the caller to shuffle app-side rather than silently doing nothing.
    func shuffleUpcomingQueueEntries() -> [Track]? {
        guard !mirror.isEmpty else { return nil }

        clearInjectedNext()

        // Verify membership BEFORE shuffling: bailing afterwards would leave the
        // engine reordered while the mirror and app queue kept their old order.
        let byId = Dictionary(uniqueKeysWithValues: mirror.map { ($0.entryId, $0) })
        guard Set(audioPlayer.queue) == Set(byId.keys) else {
            Logger.error("Engine queue diverged from the mirror; skipping shuffle")
            return nil
        }

        audioPlayer.shuffleQueue()
        let reordered = audioPlayer.queue.compactMap { byId[$0] }
        guard reordered.count == mirror.count else {
            Logger.error("Shuffle read-back dropped entries; leaving the queue order untouched")
            return nil
        }

        mirror = reordered
        return reordered.map(\.track)
    }
}
