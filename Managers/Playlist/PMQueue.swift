//
// PlaylistManager class extension
//
// This extension contains methods managing playback queue.
//

import Foundation

extension PlaylistManager {
    func createLibraryQueue() {
        guard let library = libraryManager else { return }
        currentQueue = library.tracks
        currentPlaylist = nil
        currentQueueSource = .library
        Logger.info("Created playback queue from library")
        if isShuffleEnabled {
            shuffleCurrentQueue()
            Logger.info("Shuffled the playback queue")
        }
    }

    func clearQueue() {
        currentQueue.removeAll()
        currentQueueIndex = -1
        currentPlaylist = nil
        // A stream isn't a queue member, so emptying the queue must not disconnect it.
        // The engine's own queue is already empty while streaming, so the rest is a no-op.
        if audioPlayer?.currentStation == nil {
            audioPlayer?.stop()
            audioPlayer?.currentTrack = nil
        }
        audioPlayer?.queueDidClear()
        Logger.info("Cleared playback queue")
    }

    func playNext(_ track: Track) {
        // A standby queue (entries but no cursor, as radio and Clear Queue leave it) takes
        // an insertion at the front; only a genuinely empty one is initialised.
        if !currentQueue.isEmpty, currentQueueIndex < 0 {
            stageInStandbyQueue(track, atFront: true)
            return
        }

        if currentQueue.isEmpty {
            currentQueue = [track]
            guard audioPlayer?.currentStation == nil else {
                currentQueueIndex = -1
                return
            }
            currentQueueIndex = 0
            audioPlayer?.startQueue(at: 0)
            return
        }

        if let existingIndex = currentQueue.firstIndex(where: { $0.id == track.id }) {
            // The playing track is already "next" in the only sense that matters, and
            // removing the engine's current entry would make it advance or stop.
            guard existingIndex != currentQueueIndex else { return }

            currentQueue.remove(at: existingIndex)
            if existingIndex <= currentQueueIndex {
                currentQueueIndex -= 1
            }
            // After the cursor: the mirror re-primes the repeat lookahead from it,
            // and a stale cursor indexes past the end of the shortened queue.
            audioPlayer?.queueDidRemove(at: existingIndex)
        }

        // Read after the dedupe removal, which can shift the cursor down by one.
        let position = min(currentQueueIndex + 1, currentQueue.count)
        currentQueue.insert(track, at: position)
        audioPlayer?.queueDidInsert(track, at: position)
        Logger.info("Added track to playback queue to play up next")
    }

    /// Appends or moves `track` within a queue that has no active cursor. The engine holds
    /// no mirror for a standby queue, so this is a pure app-side edit.
    private func stageInStandbyQueue(_ track: Track, atFront: Bool) {
        if let existing = currentQueue.firstIndex(where: { $0.id == track.id }) {
            currentQueue.remove(at: existing)
        }
        currentQueue.insert(track, at: atFront ? 0 : currentQueue.count)
    }

    func addToQueue(_ track: Track) {
        if !currentQueue.isEmpty, currentQueueIndex < 0 {
            stageInStandbyQueue(track, atFront: false)
            return
        }

        if currentQueue.isEmpty {
            currentQueue = [track]
            guard audioPlayer?.currentStation == nil else {
                currentQueueIndex = -1
                return
            }
            currentQueueIndex = 0
            audioPlayer?.startQueue(at: 0)
            return
        }

        if !currentQueue.contains(where: { $0.id == track.id }) {
            currentQueue.append(track)
            audioPlayer?.queueDidAppend(track)
            Logger.info("Added track to playback queue")
        }
    }

    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < currentQueue.count else { return }

        if index == currentQueueIndex {
            return
        }

        currentQueue.remove(at: index)
        if index < currentQueueIndex {
            currentQueueIndex -= 1
        }
        // After the cursor: the mirror re-primes the repeat lookahead from it, and a
        // stale cursor indexes past the end of the shortened queue.
        audioPlayer?.queueDidRemove(at: index)
        Logger.info("Remove track from playback queue")
    }

    /// Drops a row the engine has already discarded, adjusting the cursor. The engine
    /// and mirror are updated by the caller, so this does not notify them back.
    func dropQueueEntry(at index: Int) {
        guard index >= 0, index < currentQueue.count else { return }
        currentQueue.remove(at: index)
        if index < currentQueueIndex {
            currentQueueIndex -= 1
        } else if index == currentQueueIndex {
            currentQueueIndex = min(currentQueueIndex, currentQueue.count - 1)
        }
    }

    func moveInQueue(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < currentQueue.count,
              destinationIndex >= 0, destinationIndex < currentQueue.count,
              sourceIndex != destinationIndex else { return }

        let track = currentQueue.remove(at: sourceIndex)
        currentQueue.insert(track, at: destinationIndex)

        if sourceIndex == currentQueueIndex {
            currentQueueIndex = destinationIndex
        } else if sourceIndex < currentQueueIndex && destinationIndex >= currentQueueIndex {
            currentQueueIndex -= 1
        } else if sourceIndex > currentQueueIndex && destinationIndex <= currentQueueIndex {
            currentQueueIndex += 1
        }
        // After the cursor, so the mirror's repeat lookahead is primed from the
        // position the moved entry actually left behind.
        audioPlayer?.queueDidMove(from: sourceIndex, to: destinationIndex)
        Logger.info("Moved track in playback queue")
    }

    func playFromQueue(at index: Int) {
        guard index >= 0 && index < currentQueue.count else { return }

        currentQueueIndex = index
        audioPlayer?.jumpToQueueEntry(at: index)
    }

    /// Shuffles the upcoming entries, leaving played ones and the current track put.
    internal func shuffleCurrentQueue() {
        guard !currentQueue.isEmpty else { return }

        guard let audioPlayer, audioPlayer.hasMirroredQueue else {
            // No engine queue to disagree with; reorder the whole thing app-side.
            currentQueue.shuffle()
            // A standby queue has no active row, and inventing one would present the first
            // track as playing while radio actually owns the player.
            if currentQueueIndex >= 0 {
                currentQueueIndex = 0
            }
            Logger.info("Shuffled the playback queue")
            return
        }

        guard let reordered = audioPlayer.shuffleUpcomingQueueEntries() else { return }
        currentQueue = reordered
        if let position = audioPlayer.mirroredQueuePosition {
            currentQueueIndex = position
        }
        Logger.info("Shuffled the upcoming playback queue")
    }
}
