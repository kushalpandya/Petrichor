import Foundation

struct LibraryFilterItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let count: Int
    let filterType: LibraryFilterType
    let isAllItem: Bool

    init(name: String, count: Int, filterType: LibraryFilterType, isAllItem: Bool = false) {
        self.name = name.isEmpty ? "Unknown \(filterType.rawValue.dropLast())" : name
        self.count = count
        self.filterType = filterType
        self.isAllItem = isAllItem
    }

    static func allItem(for filterType: LibraryFilterType, totalCount: Int) -> LibraryFilterItem {
        LibraryFilterItem(
            name: "All \(filterType.rawValue)",
            count: totalCount,
            filterType: filterType,
            isAllItem: true
        )
    }

    // Equality and hashing deliberately exclude `id` so that two items with the same content
    // compare equal. This lets callers like `LibrarySidebarView.sortCache` actually hit.
    static func == (lhs: LibraryFilterItem, rhs: LibraryFilterItem) -> Bool {
        lhs.name == rhs.name
            && lhs.count == rhs.count
            && lhs.filterType == rhs.filterType
            && lhs.isAllItem == rhs.isAllItem
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(count)
        hasher.combine(filterType)
        hasher.combine(isAllItem)
    }
}
