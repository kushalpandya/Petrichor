//
// Automation App Intents - Intents
//
// The App Intents exposed to Shortcuts / Spotlight / Siri. Each is a thin
// adapter: it forwards to AutomationManager.shared on the main actor and returns.
// Transport/query intents run in-process (openAppWhenRun = false) and no-op
// gracefully when nothing is playing; content intents set openAppWhenRun = true
// so a cold app can satisfy "play <something>".
//

import AppIntents
import Foundation

// MARK: - Transport

struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Toggles playback in Petrichor.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.playPause()
        return .result()
    }
}

struct PlayIntent: AppIntent {
    static var title: LocalizedStringResource = "Play"
    static var description = IntentDescription("Resumes playback in Petrichor.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.play()
        return .result()
    }
}

struct PauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause"
    static var description = IntentDescription("Pauses playback in Petrichor.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.pause()
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Skips to the next track in Petrichor.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.nextTrack()
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var description = IntentDescription("Returns to the previous track in Petrichor.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.previousTrack()
        return .result()
    }
}

struct SeekIntent: AppIntent {
    static var title: LocalizedStringResource = "Seek to Position"
    static var description = IntentDescription("Seeks the current track to a position, in seconds.")
    static var openAppWhenRun = false

    @Parameter(title: "Seconds", default: 0)
    var seconds: Double

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.seek(toSeconds: seconds)
        return .result()
    }
}

struct SkipForwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Forward"
    static var description = IntentDescription("Jumps forward in the current track.")
    static var openAppWhenRun = false

    @Parameter(title: "Seconds", default: 15)
    var seconds: Double

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.skip(bySeconds: abs(seconds))
        return .result()
    }
}

struct SkipBackIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Back"
    static var description = IntentDescription("Jumps backward in the current track.")
    static var openAppWhenRun = false

    @Parameter(title: "Seconds", default: 15)
    var seconds: Double

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.skip(bySeconds: -abs(seconds))
        return .result()
    }
}

struct SetVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Volume"
    static var description = IntentDescription("Sets the playback volume (0-100).")
    static var openAppWhenRun = false

    @Parameter(title: "Volume (0-100)", default: 50)
    var level: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.setVolume(percent: level)
        return .result()
    }
}

struct ToggleShuffleIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Shuffle"
    static var description = IntentDescription("Turns shuffle on or off in Petrichor.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.toggleShuffle()
        return .result()
    }
}

struct SetShuffleIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Shuffle"
    static var description = IntentDescription("Enables or disables shuffle in Petrichor.")
    static var openAppWhenRun = false

    @Parameter(title: "Shuffle Enabled")
    var enabled: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.setShuffle(enabled)
        return .result()
    }
}

struct SetRepeatModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Repeat Mode"
    static var description = IntentDescription("Sets the repeat mode in Petrichor.")
    static var openAppWhenRun = false

    @Parameter(title: "Repeat Mode")
    var mode: RepeatModeOption

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.setRepeatMode(mode.repeatMode)
        return .result()
    }
}

struct ToggleFavoriteIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Favorite for Current Track"
    static var description = IntentDescription("Favorites or unfavorites the current track in Petrichor.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.toggleFavoriteCurrent()
        return .result()
    }
}

// MARK: - Query

struct CurrentTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Current Track"
    static var description = IntentDescription("Returns the track currently playing in Petrichor.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TrackEntity?> {
        .result(value: AutomationManager.shared.nowPlayingSnapshot().map(TrackEntity.init(snapshot:)))
    }
}

// MARK: - Content (play)

struct PlayArtistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Artist"
    static var description = IntentDescription("Plays songs by an artist in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Artist")
    var artist: ArtistAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.play(filterType: .artists, value: artist.name)
        return .result()
    }
}

struct PlayAlbumIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Album"
    static var description = IntentDescription("Plays an album in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Album")
    var album: AlbumAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.playAlbum(name: album.name, albumId: album.albumId)
        return .result()
    }
}

struct PlayAlbumArtistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Album Artist"
    static var description = IntentDescription("Plays songs by an album artist in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Album Artist")
    var albumArtist: AlbumArtistAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.play(filterType: .albumArtists, value: albumArtist.name)
        return .result()
    }
}

struct PlayComposerIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Composer"
    static var description = IntentDescription("Plays songs by a composer in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Composer")
    var composer: ComposerAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.play(filterType: .composers, value: composer.name)
        return .result()
    }
}

struct PlayGenreIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Genre"
    static var description = IntentDescription("Plays songs of a genre in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Genre")
    var genre: GenreAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.play(filterType: .genres, value: genre.name)
        return .result()
    }
}

struct PlayDecadeIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Decade"
    static var description = IntentDescription("Plays songs from a decade in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Decade")
    var decade: DecadeAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.play(filterType: .decades, value: decade.name)
        return .result()
    }
}

struct PlayYearIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Year"
    static var description = IntentDescription("Plays songs from a year in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Year")
    var year: YearAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.play(filterType: .years, value: year.name)
        return .result()
    }
}

struct PlayPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Playlist"
    static var description = IntentDescription("Plays a playlist in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Playlist")
    var playlist: PlaylistAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.playPlaylist(id: playlist.id)
        return .result()
    }
}

// MARK: - Content (queue)

struct AddAlbumToQueueIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Album to Queue"
    static var description = IntentDescription("Adds an album to the end of the queue in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Album")
    var album: AlbumAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.enqueueAlbum(name: album.name, albumId: album.albumId, playNext: false)
        return .result()
    }
}

struct PlayAlbumNextIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Album Next"
    static var description = IntentDescription("Queues an album to play next in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Album")
    var album: AlbumAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.enqueueAlbum(name: album.name, albumId: album.albumId, playNext: true)
        return .result()
    }
}

struct AddPlaylistToQueueIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Playlist to Queue"
    static var description = IntentDescription("Adds a playlist to the end of the queue in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Playlist")
    var playlist: PlaylistAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.enqueuePlaylist(id: playlist.id, playNext: false)
        return .result()
    }
}

struct PlayPlaylistNextIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Playlist Next"
    static var description = IntentDescription("Queues a playlist to play next in Petrichor.")
    static var openAppWhenRun = true

    @Parameter(title: "Playlist")
    var playlist: PlaylistAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomationManager.shared.enqueuePlaylist(id: playlist.id, playNext: true)
        return .result()
    }
}
