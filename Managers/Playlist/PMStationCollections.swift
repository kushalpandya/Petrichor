//
// PlaylistManager class extension
//
// This extension contains CRUD operations for station collections.
//

import Foundation

extension PlaylistManager {
    /// Present the name-only dialog (used by the station context menu's "New Collection...").
    func showCreateStationCollectionModal(with stations: [RadioStation] = []) {
        stationsToAddToNewCollection = stations
        newStationCollectionName = ""
        showingCreateStationCollectionModal = true
    }

    /// Present the unified editor (name + station selection) to create a new collection.
    func showCreateStationCollectionEditor() {
        stationCollectionToEdit = nil
        showingStationCollectionEditor = true
    }

    func showEditStationCollectionModal(_ playlist: Playlist) {
        guard playlist.type == .stations else { return }
        stationCollectionToEdit = playlist
        showingStationCollectionEditor = true
    }

    func createStationCollectionFromModal() {
        guard !newStationCollectionName.isEmpty, !isCreatingStationCollection else { return }
        isCreatingStationCollection = true

        let name = newStationCollectionName
        let stationIds = stationsToAddToNewCollection.compactMap(\.id)

        Task {
            let created = await createStationCollection(name: name, stationIds: stationIds)
            await MainActor.run {
                self.isCreatingStationCollection = false
                guard created != nil else { return }
                self.newStationCollectionName = ""
                self.stationsToAddToNewCollection = []
                self.showingCreateStationCollectionModal = false
            }
        }
    }

    var stationCollections: [Playlist] {
        playlists.filter { $0.type == .stations }
    }

    /// Only collections holding *every* one of `stations`, so a selection gets one checkmark.
    func collections(containing stations: [RadioStation]) -> Set<UUID> {
        guard let dbManager = libraryManager?.databaseManager else { return [] }
        let ids = stations.compactMap(\.id)
        guard !ids.isEmpty else { return [] }
        return dbManager.collectionIds(containingAll: ids)
    }

    func stations(in playlist: Playlist) -> [RadioStation] {
        guard let dbManager = libraryManager?.databaseManager else { return [] }
        return dbManager.loadStations(forPlaylist: playlist.id)
    }

    /// Awaited and published only once it commits: an optimistic append would leave a
    /// phantom collection on screen when the write failed, and the staged input gone.
    @discardableResult
    func createStationCollection(name: String, stationIds: [Int64]) async -> Playlist? {
        guard let dbManager = libraryManager?.databaseManager else { return nil }

        var collection = Playlist(stationCollectionNamed: name)
        collection.sortOrder = nextUserPlaylistSortOrder()

        do {
            try await dbManager.createStationCollection(collection, orderedStationIds: stationIds)
        } catch {
            Logger.error("Failed to save new station collection: \(error)")
            NotificationManager.shared.addMessage(.error, String(localized: "Couldn't save the collection"))
            return nil
        }

        collection.trackCount = stationIds.count

        await MainActor.run {
            self.playlists.append(collection)
            NotificationCenter.default.post(
                name: .navigateToPlaylists,
                object: nil,
                userInfo: ["playlistID": collection.id]
            )
        }

        return collection
    }

    /// Metadata and membership commit together, and in-memory state follows only on
    /// success: a failed membership write must not leave a renamed collection behind.
    @discardableResult
    func updateStationCollection(_ playlist: Playlist, name: String, stationIds: [Int64]) async -> Bool {
        guard let dbManager = libraryManager?.databaseManager else { return false }

        do {
            try await dbManager.updateStationCollection(
                playlistId: playlist.id,
                name: name,
                orderedStationIds: stationIds
            )
        } catch {
            Logger.error("Failed to update station collection '\(playlist.name)': \(error)")
            NotificationManager.shared.addMessage(.error, String(localized: "Couldn't save the collection"))
            return false
        }

        await MainActor.run {
            if let index = self.playlists.firstIndex(where: { $0.id == playlist.id }) {
                self.playlists[index].name = name
                self.playlists[index].dateModified = Date()
            }
            if let pinnedIndex = self.libraryManager?.pinnedItems.firstIndex(where: {
                $0.itemType == .playlist && $0.playlistId == playlist.id
            }) {
                self.libraryManager?.pinnedItems[pinnedIndex].displayName = name
            }
        }
        await refreshStationCollectionCount(playlist.id)

        return true
    }

    func addStations(_ stations: [RadioStation], to playlist: Playlist) async {
        guard let dbManager = libraryManager?.databaseManager else { return }

        let ids = stations.compactMap(\.id)
        guard !ids.isEmpty else { return }

        do {
            try await dbManager.addStations(ids, toCollection: playlist.id)
            await refreshStationCollectionCount(playlist.id)
        } catch {
            Logger.error("Failed to add stations to collection '\(playlist.name)': \(error)")
        }
    }

    func removeStations(_ stations: [RadioStation], from playlist: Playlist) async {
        guard let dbManager = libraryManager?.databaseManager else { return }

        let ids = stations.compactMap(\.id)
        guard !ids.isEmpty else { return }

        do {
            try await dbManager.removeStations(ids, fromCollection: playlist.id)
            await refreshStationCollectionCount(playlist.id)
        } catch {
            Logger.error("Failed to remove stations from collection '\(playlist.name)': \(error)")
        }
    }

    /// Off the main thread: this follows a write, and `dbQueue` is serialized.
    private func stationCollectionCounts() async -> [UUID: Int]? {
        guard let dbManager = libraryManager?.databaseManager else { return nil }

        return await Task.detached(priority: .userInitiated) {
            dbManager.getStationCollectionCounts()
        }.value
    }

    private func refreshStationCollectionCount(_ playlistID: UUID) async {
        guard let counts = await stationCollectionCounts() else { return }

        await MainActor.run {
            guard let index = self.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
            self.playlists[index].trackCount = counts[playlistID] ?? 0
            // Bumped even when the count holds: an edit can change contents without changing
            // the count, and `PlaylistDetailView` reloads off `dateModified`.
            self.playlists[index].dateModified = Date()
        }
    }

    /// Deleting a station cascades its `playlist_stations` rows, so counts can change with no
    /// collection edited. Home re-queries its own pinned counts; `playlists` is what's left.
    func refreshAllStationCollectionCounts() async {
        guard let counts = await stationCollectionCounts() else { return }

        await MainActor.run {
            for index in self.playlists.indices where self.playlists[index].type == .stations {
                let updated = counts[self.playlists[index].id] ?? 0
                guard self.playlists[index].trackCount != updated else { continue }
                self.playlists[index].trackCount = updated
                self.playlists[index].dateModified = Date()
            }
        }
    }
}
