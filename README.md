<img width="200" src="./Resources/Assets.xcassets/AppIcon.appiconset/1024-mac.png" alt="Petrichor App Icon" align="left"/>

<div>
<h3>Petrichor</h3>
<p>An offline music player for macOS</p>
<a href="https://github.com/kushalpandya/Petrichor/releases/latest"><img src=".github/assets/macos_download.png" width="140" alt="Download for macOS"/></a>
</div>

<br/><br/>

<div align="center">
<a href="https://github.com/kushalpandya/Petrichor/releases"><img alt="GitHub Downloads (all assets, all releases)" src="https://img.shields.io/github/downloads/kushalpandya/Petrichor/total?label=Downloads&style=flat-square&color=ba68c8"></a>
<a href="https://github.com/kushalpandya/Petrichor/actions/workflows/ci.yml"><img alt="GitHub Actions Workflow Status" src="https://img.shields.io/github/actions/workflow/status/kushalpandya/Petrichor/ci.yml?label=CI&style=flat-square"></a>
<a href="https://github.com/kushalpandya/Petrichor/blob/main/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/kushalpandya/Petrichor?label=License&style=flat-square&color=ffa726"></a>
<a href="https://github.com/kushalpandya/Petrichor/"><img src="https://img.shields.io/badge/platform-macOS-blue.svg?label=Platform&style=flat-square&logo=apple" alt="Platform"/></a>
<br/>
<br/>
<a href="https://github.com/kushalpandya/Petrichor/releases/latest"><img alt="GitHub Release" src="https://img.shields.io/github/v/release/kushalpandya/Petrichor?display_name=release&style=flat-square&label=Latest%20Release&color=26a69a"></a>

<br/>
<br/>

<img src=".github/assets/hero_screenshot.png" width="824" alt="Screenshot"/><br/>

</div>

<hr>

## Summary

### ✨ Features

- Everything you'd expect from an offline music player!
- Supports MP3, M4A, WAV, AAC, AIFF, and FLAC file formats.
- Map your music folders and browse your library in an organized view.
- Create playlists and manage the play queue interactively.
- Browse music using folder view when needed.
- Pin _anything_ (almost!) to the sidebar for quick access to your favorite music.
- Navigate easily: right-click a track to go to its album, artist, year, etc.
- Native macOS integration with menubar and dock playback controls, plus dark mode support.
- Works with well large libraries containing thousands of songs.

💡 **Tip**: Petrichor relies heavily on tracks having good metadata for all its features to work well.

### ⌛ Upcoming Features

- ~~Automatic in-app updates~~
- Audio Equalizer
- Better file format support (eg; Opus & OGG)
- AirPlay 2 casting support
- Miniplayer and full-screen modes
- Smart playlists with user-configurable conditional filters
- Online album & artist information fetching
- ... and much more!

###  Requirements

- macOS 14 or later

### ⚙️ Installation

#### Homebrew (recommended)

While Petrichor is still in alpha/beta stage, it is available to install through
my personal Homebrew tap.

```
# Add the tap
brew tap kushalpandya/tap

# Install Petrichor
brew install --cask petrichor
```

_P.S. once stable release is ready, I'll publish it on official Homebrew repo._

#### Manually

- Go to [Releases](https://github.com/kushalpandya/Petrichor/releases) and download the latest `.dmg`.
- Open the `.dmg` and drag the app icon into the Applications folder.
- In Applications, right-click **Petrichor > Open**.

### 📷 Screenshots

<div align="center">
<img src=".github/assets/screenshot_1.png" width="392" alt="Screenshot"/>
<img src=".github/assets/screenshot_2.png" width="392" alt="Screenshot"/>
<img src=".github/assets/screenshot_3.png" width="392" alt="Screenshot"/>
<img src=".github/assets/screenshot_4.png" width="392" alt="Screenshot"/>
<img src=".github/assets/screenshot_5.png" width="392" alt="Screenshot"/>
<img src=".github/assets/screenshot_6.png" width="392" alt="Screenshot"/>
</div>

## 🏗️ Development

### Motivation

I have a large collection of music files that I’ve gathered over the years, and I missed having a good offline
music player on macOS. I used [Swinsian](https://swinsian.com/) (great app, by the way!), but it hasn't been
updated in years. I also missed features commonly found in streaming apps; so I built Petrichor to scratch that
itch and learn Swift and macOS app development along the way!

### Implementation Overview

- Built with Swift and SwiftUI with some parts in AppKit for the best macOS integration.
- Once folders containing music files are added, the app scans them, extracts required metadata, and populates the SQLite database.
- The app does **not** alter your music files, it only reads from the directories you add.
- Tracks searching is handled by [SQLite FTS5](https://www.sqlite.org/fts5.html).
- Playback is handled by [AVFoundation](https://developer.apple.com/av-foundation/).

<details>
<summary>View Database Schema</summary>

```mermaid
erDiagram
    folders {
        INTEGER id PK "AUTO_INCREMENT"
        TEXT name "NOT NULL"
        TEXT path "NOT NULL UNIQUE"
        INTEGER track_count "NOT NULL DEFAULT 0"
        DATETIME date_added "NOT NULL"
        DATETIME date_updated "NOT NULL"
        BLOB bookmark_data "Security-scoped bookmark"
    }

    artists {
        INTEGER id PK "AUTO_INCREMENT"
        TEXT name "NOT NULL"
        TEXT normalized_name "NOT NULL UNIQUE"
        TEXT sort_name
        BLOB artwork_data
        TEXT bio
        TEXT bio_source
        DATETIME bio_updated_at
        TEXT image_url
        TEXT image_source
        DATETIME image_updated_at
        TEXT discogs_id
        TEXT musicbrainz_id
        TEXT spotify_id
        TEXT apple_music_id
        TEXT country
        INTEGER formed_year
        INTEGER disbanded_year
        TEXT genres "JSON array"
        TEXT websites "JSON array"
        TEXT members "JSON array"
        INTEGER total_tracks "NOT NULL DEFAULT 0 CHECK >= 0"
        INTEGER total_albums "NOT NULL DEFAULT 0 CHECK >= 0"
        DATETIME created_at "NOT NULL"
        DATETIME updated_at "NOT NULL"
    }

    albums {
        INTEGER id PK "AUTO_INCREMENT"
        TEXT title "NOT NULL"
        TEXT normalized_title "NOT NULL"
        TEXT sort_title
        BLOB artwork_data
        TEXT release_date
        INTEGER release_year "CHECK 1900-2100"
        TEXT album_type
        INTEGER total_tracks "CHECK >= 0"
        INTEGER total_discs "CHECK >= 0"
        TEXT description
        TEXT review
        TEXT review_source
        TEXT cover_art_url
        TEXT thumbnail_url
        TEXT discogs_id
        TEXT musicbrainz_id
        TEXT spotify_id
        TEXT apple_music_id
        TEXT label
        TEXT catalog_number
        TEXT barcode
        TEXT genres "JSON array"
        DATETIME created_at "NOT NULL"
        DATETIME updated_at "NOT NULL"
    }

    album_artists {
        INTEGER album_id FK "NOT NULL"
        INTEGER artist_id FK "NOT NULL"
        TEXT role "NOT NULL DEFAULT 'primary'"
        INTEGER position "NOT NULL DEFAULT 0"
    }

    genres {
        INTEGER id PK "AUTO_INCREMENT"
        TEXT name "NOT NULL UNIQUE"
    }

    tracks {
        INTEGER id PK "AUTO_INCREMENT"
        INTEGER folder_id FK "NOT NULL"
        INTEGER album_id FK
        TEXT path "NOT NULL UNIQUE"
        TEXT filename "NOT NULL"
        TEXT title
        TEXT artist
        TEXT album
        TEXT composer
        TEXT genre
        TEXT year
        REAL duration "CHECK >= 0"
        TEXT format
        INTEGER file_size
        DATETIME date_added "NOT NULL"
        DATETIME date_modified
        BLOB track_artwork_data
        BOOLEAN is_favorite "NOT NULL DEFAULT false"
        INTEGER play_count "NOT NULL DEFAULT 0"
        DATETIME last_played_date
        BOOLEAN is_duplicate "NOT NULL DEFAULT false"
        INTEGER primary_track_id FK
        TEXT duplicate_group_id
        TEXT album_artist
        INTEGER track_number "CHECK > 0"
        INTEGER total_tracks
        INTEGER disc_number "CHECK > 0"
        INTEGER total_discs
        INTEGER rating "CHECK 0-5"
        BOOLEAN compilation "DEFAULT false"
        TEXT release_date
        TEXT original_release_date
        INTEGER bpm
        TEXT media_type "Music/Audiobook/Podcast"
        INTEGER bitrate "CHECK > 0"
        INTEGER sample_rate
        INTEGER channels "1=mono, 2=stereo"
        TEXT codec
        INTEGER bit_depth
        TEXT sort_title
        TEXT sort_artist
        TEXT sort_album
        TEXT sort_album_artist
        TEXT extended_metadata "JSON"
    }

    playlists {
        TEXT id PK "UUID"
        TEXT name "NOT NULL"
        TEXT type "NOT NULL (regular/smart)"
        BOOLEAN is_user_editable "NOT NULL"
        BOOLEAN is_content_editable "NOT NULL"
        DATETIME date_created "NOT NULL"
        DATETIME date_modified "NOT NULL"
        BLOB cover_artwork_data
        TEXT smart_criteria "JSON"
        INTEGER sort_order "NOT NULL DEFAULT 0"
    }

    playlist_tracks {
        TEXT playlist_id FK "NOT NULL"
        INTEGER track_id FK "NOT NULL"
        INTEGER position "NOT NULL"
        DATETIME date_added "NOT NULL"
    }

    track_artists {
        INTEGER track_id FK "NOT NULL"
        INTEGER artist_id FK "NOT NULL"
        TEXT role "NOT NULL DEFAULT 'artist'"
        INTEGER position "NOT NULL DEFAULT 0"
    }

    track_genres {
        INTEGER track_id FK "NOT NULL"
        INTEGER genre_id FK "NOT NULL"
    }

    pinned_items {
        INTEGER id PK "AUTO_INCREMENT"
        TEXT item_type "NOT NULL (library/playlist)"
        TEXT filter_type "For library items"
        TEXT filter_value "Artist/album name"
        TEXT entity_id "UUID for entities"
        INTEGER artist_id "Database ID"
        INTEGER album_id "Database ID"
        TEXT playlist_id "For playlist items"
        TEXT display_name "NOT NULL"
        TEXT subtitle "For albums"
        TEXT icon_name "NOT NULL"
        INTEGER sort_order "NOT NULL DEFAULT 0"
        DATETIME date_added "NOT NULL"
    }

    tracks_fts {
        INTEGER track_id "NOT INDEXED"
        TEXT title
        TEXT artist
        TEXT album
        TEXT album_artist
        TEXT composer
        TEXT genre
        TEXT year
    }

    folders ||--o{ tracks : contains
    albums ||--o{ album_artists : "has artists"
    artists ||--o{ album_artists : "appears on"
    albums ||--o{ tracks : contains
    artists ||--o{ track_artists : "appears in"
    tracks ||--o{ track_artists : "has artists"
    tracks ||--o| tracks : "duplicate of"
    genres ||--o{ track_genres : "categorizes"
    tracks ||--o{ track_genres : "has genres"
    playlists ||--o{ playlist_tracks : contains
    tracks ||--o{ playlist_tracks : "appears in"
    tracks ||--|| tracks_fts : "searchable in"
```

</details>

#### Dependencies

- [GRDB.swift](https://github.com/groue/GRDB.swift/)
- [Sparkle](https://github.com/sparkle-project/Sparkle)

### Development Setup

- Make sure you’re running macOS 14 or later.
- Install [Xcode](https://developer.apple.com/xcode/).
- To build the `.dmg` installer using the [`build-installer.sh`](Scripts/build-installer.sh) script, install:
  - [xcpretty](https://github.com/xcpretty/xcpretty)
  - [create-dmg](https://github.com/sindresorhus/create-dmg)

## 📝 License

[MIT](LICENSE)
