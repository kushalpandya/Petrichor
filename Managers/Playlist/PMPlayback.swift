//
// PlaylistManager class extension
//
// This extension contains methods for handling track playback,
// the methods internally also use PlaybackManager methods to work with AVFoundation along
// with DatabaseManager methods.
//

import Foundation

extension PlaylistManager {
    // MARK: - Playback Control

    func playTrack(_ track: Track, fromTracks contextTracks: [Track]? = nil) {
        currentPlaylist = nil
        beginPlayback(of: track, in: contextTracks ?? [track])
    }

    func playTrackFromPlaylist(_ playlist: Playlist, at index: Int) {
        guard index >= 0, index < playlist.tracks.count else { return }

        currentPlaylist = playlist
        currentQueueSource = .playlist
        beginPlayback(of: playlist.tracks[index], in: playlist.tracks)
    }

    func playTrackFromFolder(_ track: Track, folderTracks: [Track]) {
        currentQueueSource = .folder
        currentPlaylist = nil
        beginPlayback(of: track, in: folderTracks)
    }

    /// Queues `contextTracks` and starts `track` within it. With shuffle off the whole
    /// list is queued with the cursor on the chosen track, so Previous walks back up
    /// the list the user is looking at; with shuffle on the chosen track leads and the
    /// rest follow in random order.
    private func beginPlayback(of track: Track, in contextTracks: [Track]) {
        guard let index = contextTracks.firstIndex(where: { $0.id == track.id }) else {
            currentQueue = [track]
            currentQueueIndex = 0
            audioPlayer?.startQueue(at: 0)
            return
        }

        if isShuffleEnabled {
            var rest = contextTracks
            rest.remove(at: index)
            rest.shuffle()
            currentQueue = [track] + rest
            currentQueueIndex = 0
        } else {
            currentQueue = contextTracks
            currentQueueIndex = index
        }

        audioPlayer?.startQueue(at: currentQueueIndex)
        Logger.info("Played track: \(track.url)")
    }

    // MARK: - Track Navigation

    /// Resolves the index of the next track per the current repeat mode, or nil at
    /// end-of-queue under `.off`. Shuffle is already reflected in `currentQueue`'s
    /// order. The single source of truth for "what plays next", shared by
    /// `playNextTrack` (which advances) and `peekNextTrack` (which only looks).
    private func nextQueueIndex() -> Int? {
        guard !currentQueue.isEmpty else { return nil }

        switch repeatMode {
        case .one:
            return currentQueueIndex
        case .all:
            return (currentQueueIndex + 1) % currentQueue.count
        case .off:
            let nextIndex = currentQueueIndex + 1
            return nextIndex < currentQueue.count ? nextIndex : nil
        }
    }

    func playNextTrack() {
        guard !currentQueue.isEmpty else {
            createLibraryQueue()
            if !currentQueue.isEmpty {
                currentQueueIndex = 0
                audioPlayer?.startQueue(at: 0)
            }
            return
        }

        guard let nextIndex = nextQueueIndex() else { return }

        currentQueueIndex = nextIndex
        audioPlayer?.jumpToQueueEntry(at: nextIndex)
        Logger.info("Played track: \(currentQueue[nextIndex].url)")
    }

    /// The next track per the current repeat mode, without advancing or playing.
    /// Feeds `primeRepeatLookahead`.
    func peekNextTrack() -> (track: Track, index: Int)? {
        guard let nextIndex = nextQueueIndex() else { return nil }
        return (currentQueue[nextIndex], nextIndex)
    }

    /// Moves the cursor after the engine advanced by itself. Does not trigger
    /// playback; keeps `PlaylistManager` the sole writer of `currentQueueIndex`.
    func advanceQueueIndex(to index: Int) {
        guard index >= 0, index < currentQueue.count else { return }
        currentQueueIndex = index
    }

    func playPreviousTrack() {
        guard !currentQueue.isEmpty else {
            createLibraryQueue()
            return
        }

        if let currentTime = audioPlayer?.currentTime, currentTime > 3 {
            audioPlayer?.seekTo(time: 0)
            return
        }

        var prevIndex: Int

        switch repeatMode {
        case .one:
            prevIndex = currentQueueIndex
        case .all:
            prevIndex = currentQueueIndex > 0 ? currentQueueIndex - 1 : currentQueue.count - 1
        case .off:
            prevIndex = currentQueueIndex - 1
            if prevIndex < 0 {
                audioPlayer?.seekTo(time: 0)
                return
            }
        }

        currentQueueIndex = prevIndex
        audioPlayer?.jumpToQueueEntry(at: prevIndex)
        Logger.info("Played track: \(currentQueue[prevIndex].url)")
    }

    // MARK: - Repeat and Shuffle

    func toggleShuffle() {
        isShuffleEnabled.toggle()
        Logger.info("Shuffle state changed to: \(isShuffleEnabled)")

        if isShuffleEnabled {
            shuffleCurrentQueue()
        }
    }

    func toggleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }
}
