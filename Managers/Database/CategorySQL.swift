//
// SQL fragments for the denormalized category columns.
//
// Genres and decades read from `tracks.genre` and `tracks.year` rather than the `genres`
// table, with the "Unknown X" sentinels stored in English and localized at display time.
// Every query grouping or filtering on them has to agree exactly, or a Discover tile's
// count silently disagrees with the Library sidebar's.
//

import Foundation

enum CategorySQL {
    /// Known (non-sentinel) genre. `alias` is the table alias, if the query uses one.
    static func knownGenre(alias: String = "") -> String {
        let column = qualified("genre", alias)
        return "\(column) IS NOT NULL AND \(column) != '' AND \(column) != '\(sentinel(.genres))'"
    }

    /// The Unknown bucket: NULL, empty, or the stored sentinel.
    static func unknownGenre(alias: String = "") -> String {
        let column = qualified("genre", alias)
        return "\(column) IS NULL OR \(column) = '' OR \(column) = '\(sentinel(.genres))'"
    }

    static func knownYear(alias: String = "") -> String {
        let column = qualified("year", alias)
        return "\(column) IS NOT NULL AND \(column) != '' AND \(column) != '\(sentinel(.years))'"
    }

    static func unknownYear(alias: String = "") -> String {
        let column = qualified("year", alias)
        return "\(column) IS NULL OR \(column) = '' OR \(column) = '\(sentinel(.years))'"
    }

    /// Emits the `"1990s"` form that `getTracksByFilterType` parses back, so a tile can
    /// open its own tracks.
    static func decadeExpression(alias: String = "") -> String {
        "SUBSTR(\(qualified("year", alias)), 1, 3) || '0s'"
    }

    /// Including the Unknown bucket, for the Library sidebar's full list.
    static func decadeExpressionWithUnknown(alias: String = "") -> String {
        """
        CASE
            WHEN \(unknownYear(alias: alias)) THEN '\(sentinel(.decades))'
            ELSE \(decadeExpression(alias: alias))
        END
        """
    }

    static func sentinel(_ filterType: LibraryFilterType) -> String {
        filterType.unknownPlaceholder
    }

    private static func qualified(_ column: String, _ alias: String) -> String {
        alias.isEmpty ? column : "\(alias).\(column)"
    }
}
