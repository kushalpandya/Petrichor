//
// LibraryManager extension: coordinates manual merging of duplicate entities.
//

import Foundation
import SwiftUI

extension LibraryManager {
    // MARK: - Request Plumbing

    func requestMerge(_ request: MergeRequest) {
        pendingMergeRequest = request
    }

    // MARK: - Context Menu Items

    /// Pin + (when mergeable) "Merge with…" items for a Home-grid entity.
    func contextMenuItems(for entity: any Entity) -> [ContextMenuItem] {
        var items = [createPinContextMenuItem(for: entity)]
        if let merge = createMergeContextMenuItem(for: entity) { items.append(merge) }
        return items
    }

    /// Pin + (when mergeable) "Merge with…" items for a Library-sidebar filter item.
    func contextMenuItems(filterType: LibraryFilterType, filterValue: String, albumId: Int64? = nil) -> [ContextMenuItem] {
        var items = [createPinContextMenuItem(for: filterType, filterValue: filterValue, albumId: albumId)]
        if let merge = createMergeContextMenuItem(filterType: filterType, filterValue: filterValue, albumId: albumId) {
            items.append(merge)
        }
        return items
    }

    private func createMergeContextMenuItem(for entity: any Entity) -> ContextMenuItem? {
        let request: MergeRequest
        if entity is ArtistEntity {
            guard entity.name != LibraryFilterType.artists.unknownPlaceholder else { return nil }
            request = MergeRequest(kind: .artist, name: entity.name)
        } else if let album = entity as? AlbumEntity {
            guard album.name != LibraryFilterType.albums.unknownPlaceholder else { return nil }
            request = MergeRequest(kind: .album, name: album.name, albumId: album.albumId)
        } else {
            return nil
        }
        return mergeButton(for: request)
    }

    private func createMergeContextMenuItem(filterType: LibraryFilterType, filterValue: String, albumId: Int64?) -> ContextMenuItem? {
        guard filterValue != filterType.unknownPlaceholder,
              let request = MergeRequest(filterType: filterType, name: filterValue, albumId: albumId) else { return nil }
        return mergeButton(for: request)
    }

    private func mergeButton(for request: MergeRequest) -> ContextMenuItem {
        .button(title: String(localized: "Merge with..."), role: nil) {
            self.requestMerge(request)
        }
    }

    // MARK: - Candidates

    /// Same-type candidates, excluding the invoked entity and the Unknown placeholder.
    func mergeCandidates(for request: MergeRequest, winnerAlbumId: Int64?) -> [MergeCandidate] {
        switch request.kind {
        case .album:
            return databaseManager.getAlbumMergeCandidates()
                .filter { $0.id != winnerAlbumId }
                .map { candidate in
                    MergeCandidate(
                        id: "album:\(candidate.id)",
                        name: candidate.title,
                        subtitle: candidate.artistName,
                        trackCount: candidate.trackCount,
                        artistName: nil,
                        albumId: candidate.id
                    )
                }
        case .artist, .albumArtist, .composer:
            let items: [LibraryFilterItem]
            switch request.kind {
            case .albumArtist: items = databaseManager.getAlbumArtistFilterItems()
            case .composer: items = databaseManager.getComposerFilterItems()
            default: items = databaseManager.getArtistFilterItems()
            }
            let placeholder = request.kind.filterType.unknownPlaceholder
            return items
                .filter { $0.name != placeholder && $0.name != request.name }
                .map { item in
                    MergeCandidate(
                        id: "artist:\(item.name)",
                        name: item.name,
                        subtitle: nil,
                        trackCount: item.count,
                        artistName: item.name,
                        albumId: nil
                    )
                }
        }
    }

    /// Resolve the winner album id: explicit from the Home grid, else the best title match.
    func albumWinnerId(for request: MergeRequest) -> Int64? {
        if let id = request.albumId { return id }
        return databaseManager.getAlbumMergeCandidates()
            .filter { $0.title == request.name }
            .max { $0.trackCount < $1.trackCount }?
            .id
    }

    // MARK: - Execution

    /// Perform the merge, then refresh cached entities/categories/pins and notify.
    @MainActor
    func performMerge(_ request: MergeRequest, selected: [MergeCandidate], newName: String, winnerAlbumId: Int64?) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let renameTo: String? = trimmed.isEmpty ? nil : trimmed

        do {
            let result: DatabaseManager.EntityMergeResult
            switch request.kind {
            case .album:
                guard let winnerId = winnerAlbumId else {
                    throw EntityMergeError.entityNotFound(request.name)
                }
                let loserIds = selected.compactMap { $0.albumId }
                result = try await databaseManager.mergeAlbums(winnerId: winnerId, loserIds: loserIds, newTitle: renameTo)
                // Rewriting tracks.album may create new duplicate keys; recompute flags.
                await databaseManager.detectAndMarkDuplicates()
            case .artist, .albumArtist, .composer:
                let loserNames = selected.compactMap { $0.artistName }
                result = try await databaseManager.mergeArtists(winnerName: request.name, loserNames: loserNames, newName: renameTo)
            }

            pendingMergeRequest = nil
            refreshEntities()
            refreshLibraryCategories()
            await loadPinnedItems()
            NotificationCenter.default.post(name: .libraryDataDidChange, object: nil)

            NotificationManager.shared.addMessage(
                .info,
                String(localized: "Merged \(result.mergedCount) into \(result.canonicalName)")
            )
        } catch {
            Logger.error("Merge failed: \(error)")
            NotificationManager.shared.addMessage(
                .error,
                String(localized: "Merge failed: \(error.localizedDescription)")
            )
        }
    }
}
