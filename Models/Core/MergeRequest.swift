import Foundation

/// Describes a user-initiated request to merge duplicate entities, published by a
/// context menu and consumed by the merge sheet. Artists, album artists, and composers
/// are all backed by the `artists` table and identified by their (unique) name; albums
/// are identified by id because album titles are not unique.
struct MergeRequest: Identifiable, Equatable {
    enum Kind: Equatable {
        case artist
        case albumArtist
        case composer
        case album

        var filterType: LibraryFilterType {
            switch self {
            case .artist: return .artists
            case .albumArtist: return .albumArtists
            case .composer: return .composers
            case .album: return .albums
            }
        }

        var isArtistRole: Bool { self != .album }
    }

    let id = UUID()
    let kind: Kind
    let name: String
    /// Identifies the exact album to merge (titles are not unique). Set for album
    /// requests from both the Home grid and the Library sidebar.
    var albumId: Int64?

    init(kind: Kind, name: String, albumId: Int64? = nil) {
        self.kind = kind
        self.name = name
        self.albumId = albumId
    }

    /// Build a request from a library sidebar filter type; returns nil for the
    /// non-mergeable categories (genres, decades, years).
    init?(filterType: LibraryFilterType, name: String, albumId: Int64? = nil) {
        switch filterType {
        case .artists: self.init(kind: .artist, name: name, albumId: nil)
        case .albumArtists: self.init(kind: .albumArtist, name: name, albumId: nil)
        case .composers: self.init(kind: .composer, name: name, albumId: nil)
        case .albums: self.init(kind: .album, name: name, albumId: albumId)
        case .genres, .decades, .years: return nil
        }
    }
}

/// Candidate row; carries artistName for artist-role merges, albumId for album merges.
struct MergeCandidate: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String?
    let trackCount: Int
    let artistName: String?
    let albumId: Int64?
}
