//
// SmartPlaylistField
//
// Typed metadata layer that drives the smart-playlist editor UI. The stored model
// (`SmartPlaylistCriteria.Rule`) keeps `field` as a plain string for forward
// compatibility; this enum maps each supported field to its display name, the kind
// of value it compares against, and the operators the evaluation backend
// (`DMSmartPlaylistQueries.buildExpression`) actually honors. Keeping these in sync
// with the backend ensures the UI never offers a field/operator combination that
// would silently match nothing.
//

import Foundation

/// The kind of value a field compares against. Determines which value editor the
/// editor sheet shows for a rule and how the raw stored string is interpreted.
enum SmartFieldValueKind {
    case text      // free-text string (e.g. Artist, Title)
    case number    // integer value (e.g. Play Count, Year)
    case duration  // edited as H:MM:SS, stored as seconds
    case date      // absolute calendar date (time ignored), stored as "yyyy-MM-dd"
    case boolean   // Yes / No
}

enum SmartField: String, CaseIterable, Identifiable {
    // Text fields
    case title
    case artist
    case album
    case albumArtist
    case genre
    case composer
    case filename
    // Numeric fields
    case year
    case playCount
    case trackNumber
    case discNumber
    case duration
    // Date fields
    case lastPlayedDate
    case dateAdded
    // Boolean fields
    case isFavorite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .title: return String(localized: "Title")
        case .artist: return String(localized: "Artist")
        case .album: return String(localized: "Album")
        case .albumArtist: return String(localized: "Album Artist")
        case .genre: return String(localized: "Genre")
        case .composer: return String(localized: "Composer")
        case .filename: return String(localized: "Filename")
        case .year: return String(localized: "Year")
        case .playCount: return String(localized: "Play Count")
        case .trackNumber: return String(localized: "Track Number")
        case .discNumber: return String(localized: "Disc Number")
        case .duration: return String(localized: "Duration")
        case .lastPlayedDate: return String(localized: "Last Played")
        case .dateAdded: return String(localized: "Date Added")
        case .isFavorite: return String(localized: "Favorite")
        }
    }

    var valueKind: SmartFieldValueKind {
        switch self {
        case .title, .artist, .album, .albumArtist, .genre, .composer, .filename:
            return .text
        case .year, .playCount, .trackNumber, .discNumber:
            return .number
        case .duration:
            return .duration
        case .lastPlayedDate, .dateAdded:
            return .date
        case .isFavorite:
            return .boolean
        }
    }

    /// Operators valid for this field, in display order. Mirrors what the backend
    /// `buildExpression` resolves to a real SQL predicate for the field's type.
    var operators: [SmartPlaylistCriteria.Condition] {
        switch valueKind {
        case .text:
            return [.equals, .contains, .startsWith, .endsWith]
        case .number:
            // `year` is stored as text and only supports equals/greaterThan/lessThan reliably.
            if self == .year {
                return [.equals, .greaterThan, .lessThan]
            }
            return [.equals, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual]
        case .duration:
            return [.equals, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual]
        case .date:
            return [.equals, .greaterThan, .lessThan]
        case .boolean:
            return [.equals]
        }
    }

    /// The value a freshly-added rule for this field starts with.
    var defaultValue: String {
        switch valueKind {
        case .text, .number, .duration: return ""
        case .date: return SmartPlaylistDate.string(from: Date())
        case .boolean: return "true"
        }
    }

    /// Fields that make sense as a "selected by" sort key for the LIMIT clause.
    /// Each rawValue is understood by `DMSmartPlaylistQueries.applySorting`.
    static var sortableFields: [SmartField] {
        [
            .dateAdded, .title, .artist, .album, .genre, .year,
            .duration, .playCount, .lastPlayedDate, .trackNumber, .discNumber
        ]
    }
}

extension SmartPlaylistCriteria.Condition {
    /// Human-readable operator label, contextual to the field's value kind.
    func displayName(for kind: SmartFieldValueKind) -> String {
        switch kind {
        case .date: return dateLabel
        case .number: return numberLabel
        case .duration: return durationLabel
        case .text, .boolean: return textLabel
        }
    }

    private var dateLabel: String {
        switch self {
        case .equals: return String(localized: "is on")
        case .greaterThan: return String(localized: "is after")
        case .lessThan: return String(localized: "is before")
        default: return rawValue
        }
    }

    private var numberLabel: String {
        switch self {
        case .equals: return String(localized: "is")
        case .greaterThan: return String(localized: "is greater than")
        case .greaterThanOrEqual: return String(localized: "is at least")
        case .lessThan: return String(localized: "is less than")
        case .lessThanOrEqual: return String(localized: "is at most")
        default: return rawValue
        }
    }

    private var durationLabel: String {
        switch self {
        case .equals: return String(localized: "is")
        case .greaterThan: return String(localized: "is longer than")
        case .greaterThanOrEqual: return String(localized: "is at least")
        case .lessThan: return String(localized: "is shorter than")
        case .lessThanOrEqual: return String(localized: "is at most")
        default: return rawValue
        }
    }

    private var textLabel: String {
        switch self {
        case .equals: return String(localized: "is")
        case .contains: return String(localized: "contains")
        case .startsWith: return String(localized: "starts with")
        case .endsWith: return String(localized: "ends with")
        default: return rawValue
        }
    }
}

/// Shared encoding for absolute date rule values ("yyyy-MM-dd"). The editor and the
/// query backend both use this so a date picked in the UI matches the same calendar
/// day at evaluation time.
enum SmartPlaylistDate {
    static let format = "yyyy-MM-dd"

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
}

/// Conversions between the H:MM:SS text shown in the duration editor and the raw
/// seconds the backend compares against `tracks.duration`.
enum SmartPlaylistDuration {
    /// Parse "H:MM:SS", "M:SS", or "SS" into total seconds. Returns nil for malformed input.
    static func seconds(from text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count) else { return nil }

        var total = 0
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return Double(total)
    }

    /// Format total seconds as "H:MM:SS".
    static func text(fromSeconds seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
