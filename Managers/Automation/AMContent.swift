//
// AutomationManager extension - Content
//
// Starts or queues playback of library content (any LibraryFilterType category
// or a playlist) for the content App Intents. All seven category types share one
// path: hydrate tracks via LibraryManager.getTracksBy(filterType:value:) - the
// entity's own `tracks` may be empty (lazy) - then hand them to PlaylistManager.
//

import Foundation

@MainActor
extension AutomationManager {
    @discardableResult
    func play(filterType: LibraryFilterType, value: String) -> Bool {
        playNow(tracks(filterType: filterType, value: value))
    }

    @discardableResult
    func playPlaylist(id: UUID) -> Bool {
        playNow(playlistTracks(id: id))
    }

    /// Albums take an explicit `albumId` because titles are not unique; without it,
    /// duplicate titles would play every matching track across both albums.
    @discardableResult
    func playAlbum(name: String, albumId: Int64?) -> Bool {
        playNow(albumTracks(name: name, albumId: albumId))
    }

    func enqueue(filterType: LibraryFilterType, value: String, playNext: Bool) {
        enqueue(tracks(filterType: filterType, value: value), playNext: playNext)
    }

    func enqueueAlbum(name: String, albumId: Int64?, playNext: Bool) {
        enqueue(albumTracks(name: name, albumId: albumId), playNext: playNext)
    }

    func enqueuePlaylist(id: UUID, playNext: Bool) {
        enqueue(playlistTracks(id: id), playNext: playNext)
    }

    // MARK: - Helpers

    private func tracks(filterType: LibraryFilterType, value: String) -> [Track] {
        library?.getTracksBy(filterType: filterType, value: value) ?? []
    }

    private func albumTracks(name: String, albumId: Int64?) -> [Track] {
        guard let library else { return [] }

        // Build the AlbumEntity from the carried albumId rather than resolving it from
        // the albumEntities cache. This keeps the disc/track-ordered fetch path (the
        // generic getTracksBy path sorts by title) while staying correct during cold
        // start, before that cache is populated.
        let entity = AlbumEntity(name: name, trackCount: 0, albumId: albumId)
        return library.databaseManager.getTracksForAlbumEntity(entity)
    }

    private func playlistTracks(id: UUID) -> [Track] {
        guard let playlist, let match = playlist.playlists.first(where: { $0.id == id }) else { return [] }
        return playlist.getPlaylistTracks(match)
    }

    @discardableResult
    private func playNow(_ tracks: [Track]) -> Bool {
        guard let playlist, let first = tracks.first else { return false }
        playlist.playTrack(first, fromTracks: tracks)
        return true
    }

    private func enqueue(_ tracks: [Track], playNext: Bool) {
        guard let playlist, let first = tracks.first else { return }

        // With an empty queue there is no current track to insert relative to, and
        // the single-track ops would start playback on the wrong track (the reversed
        // play-next loop would leave the last track playing). Start the whole set in
        // natural order instead.
        guard !playlist.currentQueue.isEmpty else {
            playlist.playTrack(first, fromTracks: tracks)
            return
        }

        // Queue ops are single-track. For "play next", insert in reverse so the first
        // selected track ends up immediately after the current one; for the tail,
        // append in natural order.
        if playNext {
            for track in tracks.reversed() { playlist.playNext(track) }
        } else {
            for track in tracks { playlist.addToQueue(track) }
        }
    }
}
