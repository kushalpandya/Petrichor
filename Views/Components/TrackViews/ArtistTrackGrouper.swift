import Foundation

struct DiscGroup: Identifiable {
    let number: Int
    let tracks: [Track]

    var id: Int { number }
}

enum AlbumGroupID: Hashable {
    case database(Int64)
    case metadata(album: String, albumArtist: String)
}

struct AlbumGroup: Identifiable {
    let id: AlbumGroupID
    let name: String
    let year: Int?
    let dateAdded: Date?
    let tracks: [Track]
    let discGroups: [DiscGroup]

    var showsDiscGroups: Bool { discGroups.count > 1 }
}

struct ArtistTrackSection: Identifiable {
    let id: String
    let albumName: String?
    let albumTracks: [Track]?
    let discNumber: Int?
    let tracks: [Track]
}

enum ArtistTrackGrouper {
    static func groups(
        from tracks: [Track],
        usesDefaultOrdering: Bool,
        fallbackSortOrder: [KeyPathComparator<Track>],
        albumSortField: ArtistAlbumGroupSortField,
        albumsAscending: Bool,
        discsAscending: Bool
    ) -> [AlbumGroup] {
        Dictionary(grouping: tracks, by: albumGroupID)
            .map { id, tracks in
                let orderedTracks = orderedTracks(
                    tracks,
                    usesDefaultOrdering: usesDefaultOrdering,
                    fallbackSortOrder: fallbackSortOrder
                )
                return AlbumGroup(
                    id: id,
                    name: tracks.first?.displayAlbum ?? LibraryFilterType.albums.unknownPlaceholder,
                    year: tracks.compactMap { Int($0.year.prefix(4)) }.min(),
                    dateAdded: tracks.compactMap(\.dateAdded).min(),
                    tracks: orderedTracks,
                    discGroups: discGroups(for: orderedTracks, ascending: discsAscending)
                )
            }
            .sorted {
                compareAlbums($0, $1, by: albumSortField, ascending: albumsAscending)
            }
    }

    static func sections(from albums: [AlbumGroup]) -> [ArtistTrackSection] {
        albums.flatMap { album in
            guard album.showsDiscGroups else {
                return [
                    ArtistTrackSection(
                        id: String(describing: album.id),
                        albumName: album.name,
                        albumTracks: album.tracks,
                        discNumber: nil,
                        tracks: album.tracks
                    )
                ]
            }
            return album.discGroups.enumerated().map { index, disc in
                ArtistTrackSection(
                    id: "\(String(describing: album.id))-\(disc.number)",
                    albumName: index == 0 ? album.name : nil,
                    albumTracks: index == 0 ? album.discGroups.flatMap(\.tracks) : nil,
                    discNumber: disc.number,
                    tracks: disc.tracks
                )
            }
        }
    }

    private static func albumGroupID(for track: Track) -> AlbumGroupID {
        if let albumId = track.albumId {
            return .database(albumId)
        }
        return .metadata(album: track.album, albumArtist: track.albumArtist ?? track.artist)
    }

    private static func orderedTracks(
        _ tracks: [Track],
        usesDefaultOrdering: Bool,
        fallbackSortOrder: [KeyPathComparator<Track>]
    ) -> [Track] {
        guard usesDefaultOrdering else { return tracks }
        let sortOrder = tracks.allSatisfy { ($0.trackNumber ?? 0) > 0 }
            ? Track.artistSortOrder
            : fallbackSortOrder
        return tracks.sorted(using: sortOrder)
    }

    private static func discGroups(for tracks: [Track], ascending: Bool) -> [DiscGroup] {
        guard tracks.allSatisfy({ ($0.discNumber ?? 0) > 0 }) else { return [] }
        return Dictionary(grouping: tracks, by: \.normalizedDiscNumber)
            .map { DiscGroup(number: $0.key, tracks: $0.value) }
            .sorted { ascending ? $0.number < $1.number : $0.number > $1.number }
    }

    private static func compareAlbums(
        _ left: AlbumGroup,
        _ right: AlbumGroup,
        by field: ArtistAlbumGroupSortField,
        ascending: Bool
    ) -> Bool {
        let comparison: ComparisonResult
        switch field {
        case .albumName:
            comparison = left.name.localizedCaseInsensitiveCompare(right.name)
        case .year:
            comparison = compare(left.year ?? 0, right.year ?? 0)
        case .dateAdded:
            comparison = compare(left.dateAdded ?? .distantPast, right.dateAdded ?? .distantPast)
        }

        if comparison != .orderedSame {
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }

        let nameComparison = left.name.localizedCaseInsensitiveCompare(right.name)
        if nameComparison != .orderedSame {
            return ascending ? nameComparison == .orderedAscending : nameComparison == .orderedDescending
        }

        let leftID = String(describing: left.id)
        let rightID = String(describing: right.id)
        return ascending ? leftID < rightID : leftID > rightID
    }

    private static func compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }
}
