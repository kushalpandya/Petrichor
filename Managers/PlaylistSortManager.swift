//
// PlaylistSortManager class
//
// This class handles playlist sorting.
//

import SwiftUI

/// Manages playlist-specific sorting preferences
class PlaylistSortManager: ObservableObject {
    static let shared = PlaylistSortManager()

    // Store sort preferences per playlist
    @AppStorage("playlistSortFields")
    private var sortFieldsData: Data = Data()

    @AppStorage("playlistSortAscending")
    private var sortAscendingData: Data = Data()

    private var sortFields: [UUID: String] = [:] {
        didSet { savePreferences() }
    }

    private var sortAscending: [UUID: Bool] = [:] {
        didSet { savePreferences() }
    }

    init() {
        migrateFromLegacyKey()
        loadPreferences()
    }

    // MARK: - Public Methods

    func getSortField(for playlistID: UUID) -> TrackSortField {
        guard let rawValue = sortFields[playlistID],
              let field = TrackSortField(rawValue: rawValue) else {
            return .dateAdded
        }
        return field
    }

    func hasSortPreference(for playlistID: UUID) -> Bool {
        sortFields[playlistID] != nil
    }

    func getSortAscending(for playlistID: UUID) -> Bool {
        sortAscending[playlistID] ?? true
    }

    func setSortField(_ field: TrackSortField, for playlistID: UUID) {
        sortFields[playlistID] = field.rawValue
        objectWillChange.send()
    }

    func setSortAscending(_ ascending: Bool, for playlistID: UUID) {
        sortAscending[playlistID] = ascending
        objectWillChange.send()
    }

    // MARK: - Migration

    /// Migrate from the old "playlistSortCriteria" key to "playlistSortFields".
    /// The old format stored SortCriteria raw values ("dateAdded", "title", "custom")
    /// which are valid TrackSortField raw values, so the data is compatible as-is.
    private func migrateFromLegacyKey() {
        let legacyKey = "playlistSortCriteria"
        guard sortFieldsData.isEmpty,
              let legacyData = UserDefaults.standard.data(forKey: legacyKey),
              !legacyData.isEmpty else { return }

        sortFieldsData = legacyData
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    // MARK: - Persistence

    private func loadPreferences() {
        if let decoded = try? JSONDecoder().decode([String: String].self, from: sortFieldsData) {
            sortFields = decoded.reduce(into: [:]) { result, pair in
                if let uuid = UUID(uuidString: pair.key) {
                    result[uuid] = pair.value
                }
            }
        }

        if let decoded = try? JSONDecoder().decode([String: Bool].self, from: sortAscendingData) {
            sortAscending = decoded.reduce(into: [:]) { result, pair in
                if let uuid = UUID(uuidString: pair.key) {
                    result[uuid] = pair.value
                }
            }
        }
    }

    private func savePreferences() {
        let fieldsDict = sortFields.reduce(into: [String: String]()) { result, pair in
            result[pair.key.uuidString] = pair.value
        }
        if let encoded = try? JSONEncoder().encode(fieldsDict) {
            sortFieldsData = encoded
        }

        let ascendingDict = sortAscending.reduce(into: [String: Bool]()) { result, pair in
            result[pair.key.uuidString] = pair.value
        }
        if let encoded = try? JSONEncoder().encode(ascendingDict) {
            sortAscendingData = encoded
        }
    }
}
