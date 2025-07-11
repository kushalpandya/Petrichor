import Foundation

// MARK: - Icons

enum Icons {
    // Music & Audio
    static let musicNote = "music.note"
    static let musicNoteList = "music.note.list"
    static let musicNoteHouse = "music.note.house"
    static let musicNoteHouseFill = "music.note.house.fill"
    static let speakerWave3Fill = "speaker.wave.3.fill"
    
    // Playback Controls
    static let star = "star"
    static let playFill = "play.fill"
    static let pauseFill = "pause.fill"
    static let playCircleFill = "play.circle.fill"
    static let pauseCircleFill = "pause.circle.fill"
    static let backwardFill = "backward.fill"
    static let forwardFill = "forward.fill"
    static let shuffleFill = "shuffle"
    static let repeatFill = "repeat"
    static let repeat1Fill = "repeat.1"
    
    // Navigation
    static let chevronRight = "chevron.right"
    static let chevronDown = "chevron.down"
    static let xmarkCircleFill = "xmark.circle.fill"
    
    // File & Folder
    static let folder = "folder"
    static let folderFill = "folder.fill"
    static let folderBadgePlus = "folder.badge.plus"
    static let folderFillBadgePlus = "folder.fill.badge.plus"
    static let folderFillBadgeMinus = "folder.fill.badge.minus"
    
    // UI Elements
    static let settings = "gear"
    static let magnifyingGlass = "magnifyingglass"
    static let checkmarkSquareFill = "checkmark.square.fill"
    static let square = "square"
    static let infoCircle = "info.circle"
    static let plusCircle = "plus.circle"
    static let chartUptrendFill = "chart.line.uptrend.xyaxis.circle.fill"
    static let infoCircleFill = "info.circle.fill"
    static let plusCircleFill = "plus.circle.fill"
    static let minusSquareFill = "minus.square.fill"
    static let minusCircleFill = "minus.circle.fill"
    static let arrowClockwise = "arrow.clockwise"
    
    // Entity Icons
    static let personFill = "person.fill"
    static let person2Fill = "person.2.fill"
    static let person2CropSquareStackFill = "person.2.crop.square.stack.fill"
    static let person2Wave2Fill = "person.2.wave.2.fill"
    static let opticalDiscFill = "opticaldisc.fill"
    static let calendarBadgeClock = "calendar.badge.clock"
    static let calendarCircleFill = "calendar.circle.fill"
    
    // Smart Playlist Icons
    static let starFill = "star.fill"
    static let clockFill = "clock.fill"
    
    // Sort Icons
    static let sortAscending = "sort.ascending"
    static let sortDescending = "sort.descending"
    
    // Custom Icons (from project assets)
    static let customMusicNoteRectangleStack = "custom.music.note.rectangle.stack"
    static let customMusicNoteRectangleStackFill = "custom.music.note.rectangle.stack.fill"
}

// MARK: - About View

enum About {
    static let bundleIdentifier = "org.Petrichor"
    static let appTitle = "Petrichor"
    static let appSubtitle = "An offline macOS music player"
    static let appWebsite = "https://github.com/kushalpandya/Petrichor"
    static let appWiki = "https://github.com/kushalpandya/Petrichor/wiki"
    static let appPlaybackQueueLabel = "org.Petrichor.playback"
}

// MARK: - Audio File Formats

enum AudioFormat {
    static let supportedExtensions = ["mp3", "m4a", "wav", "aac", "aiff", "flac"]
    
    static var supportedFormatsDisplay: String {
        supportedExtensions
            .map { $0.uppercased() }
            .joined(separator: ", ")
    }
    
    static func isSupported(_ fileExtension: String) -> Bool {
        supportedExtensions.contains(fileExtension.lowercased())
    }
}

// MARK: - String Formats
enum StringFormat {
    static let hhmmss: String = "%d:%02d:%02d"
    static let mmss: String = "%d:%02d"
    static let logEntryFormat: String = "yyyy-MM-dd HH:mm:ss.SSS"
}

// MARK: - Animation Durations

enum AnimationDuration {
    static let quickDuration: TimeInterval = 0.1
    static let standardDuration: TimeInterval = 0.15
    static let mediumDuration: TimeInterval = 0.2
    static let longDuration: TimeInterval = 0.3
}

// MARK: - Delay Durations

enum TimeConstants {
    static let fiftyMilliseconds: UInt64 = 50_000_000
    static let oneFiftyMilliseconds: UInt64 = 150_000_000
    static let stateSaveTimerDuration: Double = 30.0
    static let playbackProgressTimerDuration: Double = 5.0
}

// MARK: - Database Constants

enum DatabaseConstants {
    static let walMode = "WAL"
    static let batchSize = 50
    static let largeBatchSize = 100
}

// MARK: - Default Playlists

enum DefaultPlaylists {
    static let favorites = "Favorites"
    static let mostPlayed = "Top 25 Most Played"
    static let recentlyPlayed = "Top 25 Recently Played"
}

extension DefaultPlaylists {
    static func noSongsText(for playlist: Playlist) -> String {
        if playlist.type == .smart && !playlist.isUserEditable {
            switch playlist.name {
            case DefaultPlaylists.favorites:
                return "No Favorite Songs"
            case DefaultPlaylists.mostPlayed:
                return "No Frequently Played Songs"
            case DefaultPlaylists.recentlyPlayed:
                return "No Recently Played Songs"
            default:
                return "Empty Smart Playlist"
            }
        }
        return "Empty Playlist"
    }
    
    static func emptyStateText(for playlist: Playlist) -> String {
        if playlist.type == .smart && !playlist.isUserEditable {
            switch playlist.name {
            case DefaultPlaylists.favorites:
                return "Mark songs as favorites to see them here"
            case DefaultPlaylists.mostPlayed:
                return "Songs played more than 5 times will appear here"
            case DefaultPlaylists.recentlyPlayed:
                return "Songs played in the last week will appear here"
            default:
                return "This smart playlist will update automatically based on its criteria"
            }
        }
        return "Add some tracks to this playlist to get started"
    }
}

// MARK: - Icon Helpers

extension Icons {
    static func repeatIcon(for mode: RepeatMode) -> String {
        switch mode {
        case .off:
            return Icons.repeatFill
        case .one:
            return Icons.repeat1Fill
        case .all:
            return Icons.repeatFill
        }
    }
    
    static func sortIcon(for isAscending: Bool) -> String {
        isAscending ? Icons.sortAscending : Icons.sortDescending
    }
    
    static func entityIcon(for entity: any Entity) -> String {
        if entity is ArtistEntity {
            return Icons.personFill
        } else if entity is AlbumEntity {
            return Icons.opticalDiscFill
        }
        return Icons.musicNote
    }
    
    static func defaultPlaylistIcon(for playlist: Playlist) -> String {
        if playlist.type == .smart && !playlist.isUserEditable {
            switch playlist.name {
            case DefaultPlaylists.favorites:
                return Icons.starFill
            case DefaultPlaylists.mostPlayed:
                return Icons.chartUptrendFill
            case DefaultPlaylists.recentlyPlayed:
                return Icons.clockFill
            default:
                return Icons.musicNoteList
            }
        }
        return Icons.musicNoteList
    }
}
