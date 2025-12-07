//
// PlaylistSortManager class
//
// This class handles playlist sorting.
//

import SwiftUI

/// Manages playlist-specific sorting preferences
class PlaylistSortManager: ObservableObject {
    static let shared = PlaylistSortManager()
    
    enum SortCriteria: String, CaseIterable {
        case dateAdded
        case title
        case custom
        
        var displayName: String {
            switch self {
            case .dateAdded: return "Date added"
            case .title: return "Title"
            case .custom: return "Custom"
            }
        }
    }
    
    // Store sort preferences per playlist
    @AppStorage("playlistSortCriteria")
    private var sortCriteriaData: Data = Data()
    
    @AppStorage("playlistSortAscending")
    private var sortAscendingData: Data = Data()
    
    // Cache for current table sort column (when custom is selected)
    private var customSortColumns: [UUID: String] = [:]
    
    private var sortCriteria: [UUID: SortCriteria] = [:] {
        didSet {
            savePreferences()
        }
    }
    
    private var sortAscending: [UUID: Bool] = [:] {
        didSet {
            savePreferences()
        }
    }
    
    init() {
        loadPreferences()
    }
    
    // MARK: - Public Methods
    
    func getSortCriteria(for playlistID: UUID) -> SortCriteria {
        sortCriteria[playlistID] ?? .dateAdded
    }
    
    func getSortAscending(for playlistID: UUID) -> Bool {
        sortAscending[playlistID] ?? true
    }
    
    func setSortCriteria(_ criteria: SortCriteria, for playlistID: UUID) {
        sortCriteria[playlistID] = criteria
        objectWillChange.send()
    }
    
    func setSortAscending(_ ascending: Bool, for playlistID: UUID) {
        sortAscending[playlistID] = ascending
        objectWillChange.send()
    }
    
    func setCustomSortColumn(_ column: String, for playlistID: UUID) {
        customSortColumns[playlistID] = column
        setSortCriteria(.custom, for: playlistID)
    }
    
    func getCustomSortColumn(for playlistID: UUID) -> String? {
        customSortColumns[playlistID]
    }
    
    // MARK: - Persistence
    
    private func loadPreferences() {
        // Load sort criteria
        if let decoded = try? JSONDecoder().decode([String: String].self, from: sortCriteriaData) {
            sortCriteria = decoded.compactMapValues { rawValue in
                SortCriteria(rawValue: rawValue)
            }
            .reduce(into: [:]) { result, pair in
                if let uuid = UUID(uuidString: pair.key) {
                    result[uuid] = pair.value
                }
            }
        }
        
        // Load sort ascending
        if let decoded = try? JSONDecoder().decode([String: Bool].self, from: sortAscendingData) {
            sortAscending = decoded.reduce(into: [:]) { result, pair in
                if let uuid = UUID(uuidString: pair.key) {
                    result[uuid] = pair.value
                }
            }
        }
    }
    
    private func savePreferences() {
        // Save sort criteria
        let criteriaDict = sortCriteria.reduce(into: [String: String]()) { result, pair in
            result[pair.key.uuidString] = pair.value.rawValue
        }
        if let encoded = try? JSONEncoder().encode(criteriaDict) {
            sortCriteriaData = encoded
        }
        
        // Save sort ascending
        let ascendingDict = sortAscending.reduce(into: [String: Bool]()) { result, pair in
            result[pair.key.uuidString] = pair.value
        }
        if let encoded = try? JSONEncoder().encode(ascendingDict) {
            sortAscendingData = encoded
        }
    }
}
