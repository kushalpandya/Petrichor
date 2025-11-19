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

    func setCurrentQueue(from playlist: Playlist) {
        currentPlaylist = playlist
        currentQueue = playlist.tracks
        currentQueueSource = .playlist
        Logger.info("Created playback queue from playlist")
        if isShuffleEnabled {
            shuffleCurrentQueue()
            Logger.info("Shuffled the playback queue")
        }
    }

    func setCurrentQueue(fromFolder folder: Folder) {
        guard let library = libraryManager else { return }
        let folderTracks = library.getTracksInFolder(folder)
        currentQueue = folderTracks
        currentPlaylist = nil
        currentQueueSource = .folder
        Logger.info("Created playback queue from folder")
        if isShuffleEnabled {
            shuffleCurrentQueue()
            Logger.info("Shuffled the playback queue")
        }
    }

    func clearQueue() {
        currentQueue.removeAll()
        currentQueueIndex = -1
        currentPlaylist = nil
        audioPlayer?.stop()
        audioPlayer?.currentTrack = nil
        Logger.info("Cleared playback queue")
    }

    func playNext(_ track: Track) {
        if currentQueue.isEmpty || currentQueueIndex < 0 {
            currentQueue = [track]
            currentQueueIndex = 0
            audioPlayer?.playTrack(track)
            return
        }

        let insertIndex = currentQueueIndex + 1

        if let existingIndex = currentQueue.firstIndex(where: { $0.id == track.id }) {
            currentQueue.remove(at: existingIndex)
            if existingIndex <= currentQueueIndex {
                currentQueueIndex -= 1
            }
        }

        currentQueue.insert(track, at: min(insertIndex, currentQueue.count))
        Logger.info("Added track to playback queue to play up next")
    }

    func addToQueue(_ track: Track) {
        if currentQueue.isEmpty {
            currentQueue = [track]
            currentQueueIndex = 0
            audioPlayer?.playTrack(track)
            return
        }

        if !currentQueue.contains(where: { $0.id == track.id }) {
            currentQueue.append(track)
            Logger.info("Added track to playback queue")
        }
    }

    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < currentQueue.count else { return }

        if index == currentQueueIndex {
            return
        }

        currentQueue.remove(at: index)
        Logger.info("Remove track from playback queue")

        if index < currentQueueIndex {
            currentQueueIndex -= 1
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
        Logger.info("Moved track in playback queue")
    }

    func playFromQueue(at index: Int) {
        guard index >= 0 && index < currentQueue.count else { return }

        currentQueueIndex = index
        let track = currentQueue[index]
        audioPlayer?.playTrack(track)
    }

    internal func shuffleCurrentQueue() {
        guard !currentQueue.isEmpty else { return }

        if let currentTrack = audioPlayer?.currentTrack,
           let currentIndex = currentQueue.firstIndex(where: { $0.id == currentTrack.id }) {
            var tracksToShuffle = currentQueue
            tracksToShuffle.remove(at: currentIndex)
            tracksToShuffle.shuffle()

            currentQueue = [currentTrack] + tracksToShuffle
            currentQueueIndex = 0
        } else {
            currentQueue.shuffle()
            currentQueueIndex = 0
        }
        Logger.info("Shuffled the playback queue")
    }
}
