//
// Automation App Intents - Shortcuts provider
//
// Zero-setup Siri/Spotlight phrases. Apple registers at most 10 App Shortcuts
// per app, so this is the curated voice surface: Play/Pause, Current Track,
// Favorite, and the content pickers (artist, album, album artist, composer,
// genre, decade, playlist). Years are intentionally excluded from voice
// (numeric phrases collide); the full intent set is still available as manual
// actions in Shortcuts.app regardless of what's listed here.
//
// Parameterized phrases (e.g. "Play <artist>") match fairly literally, so each
// content intent donates a few natural variants. `\(.applicationName)` resolves
// to the app's display name - "Petrichor Dev" in Debug, "Petrichor" in Release.
//

import AppIntents

struct PetrichorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayPauseIntent(),
            phrases: [
                "Play or pause in \(.applicationName)",
                "Toggle playback in \(.applicationName)"
            ],
            shortTitle: "Play/Pause",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: CurrentTrackIntent(),
            phrases: [
                "What's playing in \(.applicationName)",
                "What's playing on \(.applicationName)"
            ],
            shortTitle: "Current Track",
            systemImageName: "music.note"
        )
        AppShortcut(
            intent: ToggleFavoriteIntent(),
            phrases: [
                "Favorite this in \(.applicationName)",
                "Favorite the current track in \(.applicationName)"
            ],
            shortTitle: "Favorite",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: PlayArtistIntent(),
            phrases: [
                "Play \(\.$artist) in \(.applicationName)",
                "Play songs by \(\.$artist) in \(.applicationName)",
                "Play songs from \(\.$artist) in \(.applicationName)",
                "Play music from \(\.$artist) in \(.applicationName)"
            ],
            shortTitle: "Play Artist",
            systemImageName: "music.mic"
        )
        AppShortcut(
            intent: PlayAlbumIntent(),
            phrases: [
                "Play the album \(\.$album) in \(.applicationName)",
                "Play album \(\.$album) in \(.applicationName)"
            ],
            shortTitle: "Play Album",
            systemImageName: "opticaldisc"
        )
        AppShortcut(
            intent: PlayAlbumArtistIntent(),
            phrases: [
                "Play album artist \(\.$albumArtist) in \(.applicationName)"
            ],
            shortTitle: "Play Album Artist",
            systemImageName: "person.2.fill"
        )
        AppShortcut(
            intent: PlayComposerIntent(),
            phrases: [
                "Play composer \(\.$composer) in \(.applicationName)",
                "Play music by \(\.$composer) in \(.applicationName)"
            ],
            shortTitle: "Play Composer",
            systemImageName: "music.quarternote.3"
        )
        AppShortcut(
            intent: PlayGenreIntent(),
            phrases: [
                "Play \(\.$genre) in \(.applicationName)",
                "Play some \(\.$genre) in \(.applicationName)"
            ],
            shortTitle: "Play Genre",
            systemImageName: "guitars.fill"
        )
        AppShortcut(
            intent: PlayDecadeIntent(),
            phrases: [
                "Play music from the \(\.$decade) in \(.applicationName)"
            ],
            shortTitle: "Play Decade",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: PlayPlaylistIntent(),
            phrases: [
                "Play the playlist \(\.$playlist) in \(.applicationName)",
                "Play playlist \(\.$playlist) in \(.applicationName)"
            ],
            shortTitle: "Play Playlist",
            systemImageName: "music.note.list"
        )
    }
}
