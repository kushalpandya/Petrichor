import SwiftUI

struct LibrarySidebarView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Binding var selectedFilterType: LibraryFilterType
    @Binding var selectedFilterItem: LibraryFilterItem?
    @Binding var pendingSearchText: String?

    @State private var filteredItems: [LibraryFilterItem] = []
    @State private var selectedSidebarItem: LibrarySidebarItem?
    @State private var searchText = ""
    @State private var localSearchText = ""
    @State private var sortAscending = true

    var body: some View {
        VStack(spacing: 0) {
            // Header with filter type and search
            headerSection

            Divider()

            // Sidebar content
            SidebarView(
                filterItems: filteredItems,
                filterType: selectedFilterType,
                totalTracksCount: libraryManager.globalSearchText.isEmpty ?
                    libraryManager.totalTrackCount :
                    libraryManager.searchResults.count,
                selectedItem: $selectedSidebarItem,
                showAllItem: !libraryManager.globalSearchText.isEmpty,
                onItemTap: { item in
                    handleItemSelection(item)
                },
                contextMenuItems: { item in
                    createContextMenuItems(for: item)
                }
            )
        }
        .onAppear {
            // First update the filtered items
            updateFilteredItems()

            // Then initialize selection after items are available
            DispatchQueue.main.async {
               initializeSelection()
            }
        }
        .onChange(of: searchText) {
            updateFilteredItems()
        }
        .onChange(of: selectedFilterType) { _, newType in
            handleFilterTypeChange(newType)
        }
        .onChange(of: libraryManager.tracks) {
            updateFilteredItems()
        }
        .onChange(of: sortAscending) {
            // Re-sort items when sort order changes
            updateFilteredItems()
        }
        .onChange(of: libraryManager.globalSearchText) { oldValue, newValue in
            updateFilteredItems()
            
            // Handle transition between search and non-search modes
            if oldValue.isEmpty && !newValue.isEmpty {
                // Entering search mode - select "All" item
                let totalCount = libraryManager.searchResults.count
                let allItem = LibraryFilterItem.allItem(for: selectedFilterType, totalCount: totalCount)
                selectedFilterItem = allItem
                selectedSidebarItem = LibrarySidebarItem(allItemFor: selectedFilterType, count: totalCount)
            } else if !oldValue.isEmpty && newValue.isEmpty {
                // Exiting search mode - select first available item if current selection is "All"
                if let currentSelection = selectedFilterItem, currentSelection.isAllItem {
                    if !filteredItems.isEmpty {
                        selectedFilterItem = filteredItems.first
                        if let filterItem = selectedFilterItem {
                            selectedSidebarItem = LibrarySidebarItem(filterItem: filterItem)
                        }
                    } else {
                        selectedFilterItem = nil
                        selectedSidebarItem = nil
                    }
                }
            }
        }
        .onChange(of: pendingSearchText) { _, newValue in
            if let searchValue = newValue {
                // Clear the pending search first
                pendingSearchText = nil
                
                // Wait for tab switch to complete if needed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Apply the search text first
                    searchText = searchValue
                    localSearchText = searchValue
                    
                    // Wait a bit more for the filtered items to update
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        // Now find the item in the filtered list
                        if let exactMatch = filteredItems.first(where: { $0.name == searchValue }) {
                            // Create the sidebar item for selection
                            let sidebarItem = LibrarySidebarItem(filterItem: exactMatch)
                            
                            // Use handleItemSelection to properly set both
                            handleItemSelection(sidebarItem)
                        } else {
                            // If not in filtered items, try to get from all items
                            let allItems = libraryManager.getLibraryFilterItems(for: selectedFilterType)
                            if let exactMatch = allItems.first(where: { $0.name == searchValue }) {
                                // Create the sidebar item for selection
                                let sidebarItem = LibrarySidebarItem(filterItem: exactMatch)
                                
                                // Use handleItemSelection
                                handleItemSelection(sidebarItem)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: selectedFilterType) { _, newType in
            handleFilterTypeChange(newType)
        }
        .onChange(of: libraryManager.searchResults) {
            updateFilteredItems()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        ListHeader {
            // Filter type dropdown - now icons-only
            IconOnlyDropdown(
                items: LibraryFilterType.allCases,
                selection: $selectedFilterType,
                iconProvider: { $0.icon },
                tooltipProvider: { $0.rawValue }
            )

            // Filter bar
            SearchInputField(
                text: $localSearchText,
                placeholder: "Filter \(selectedFilterType.rawValue.lowercased())...",
                fontSize: 11
            )
            .onChange(of: localSearchText) { _, newValue in
                searchText = newValue
            }

            // Sort button
            Button(action: { sortAscending.toggle() }) {
                Image(Icons.sortIcon(for: sortAscending))
                    .renderingMode(.template)
                    .scaleEffect(0.8)
            }
            .buttonStyle(.borderless)
            .help("Sort \(sortAscending ? "descending" : "ascending")")
        }
    }

    // MARK: - Helper Methods

    private func initializeSelection() {
        // When not in search mode and no selection exists, select the first item if available
        if selectedFilterItem == nil {
            if !libraryManager.globalSearchText.isEmpty {
                // In search mode, we can still use the "All" item
                let allItem = LibraryFilterItem.allItem(for: selectedFilterType, totalCount: libraryManager.searchResults.count)
                selectedFilterItem = allItem
            } else if !filteredItems.isEmpty {
                // Not in search mode, select the first available item
                selectedFilterItem = filteredItems.first
            } else {
                // If filtered items aren't ready yet, get them directly
                let items = libraryManager.getLibraryFilterItems(for: selectedFilterType)
                if !items.isEmpty {
                    selectedFilterItem = items.first
                }
            }
        }

        // Always sync the sidebar selection with the filter selection
        if let filterItem = selectedFilterItem {
            if filterItem.isAllItem {
                selectedSidebarItem = LibrarySidebarItem(allItemFor: selectedFilterType, count: libraryManager.searchResults.count)
            } else {
                selectedSidebarItem = LibrarySidebarItem(filterItem: filterItem)
            }
        }
    }

    private func handleItemSelection(_ item: LibrarySidebarItem) {
        // Update the selected sidebar item
        selectedSidebarItem = item

        if item.filterName.isEmpty {
            // "All" item selected - use appropriate track count based on search state
            let totalCount = libraryManager.searchResults.count
            selectedFilterItem = LibraryFilterItem.allItem(for: selectedFilterType, totalCount: totalCount)
        } else {
            // Regular filter item - calculate actual count based on current search
            let tracksToFilter = libraryManager.searchResults
            let matchingTracks = tracksToFilter.filter { track in
                selectedFilterType.trackMatches(track, filterValue: item.filterName)
            }

            selectedFilterItem = LibraryFilterItem(
                name: item.filterName,
                count: matchingTracks.count,
                filterType: selectedFilterType
            )
        }
    }

    private func handleFilterTypeChange(_ newType: LibraryFilterType) {
        // Update filtered items first to get the available items
        updateFilteredItems()
        
        // Reset selection when filter type changes
        if !libraryManager.globalSearchText.isEmpty {
            // In search mode, select "All"
            let totalCount = libraryManager.searchResults.count
            let allItem = LibraryFilterItem.allItem(for: newType, totalCount: totalCount)
            selectedFilterItem = allItem
            selectedSidebarItem = LibrarySidebarItem(allItemFor: newType, count: totalCount)
        } else if !filteredItems.isEmpty {
            // Not in search mode, select the first available item
            selectedFilterItem = filteredItems.first
            if let filterItem = selectedFilterItem {
                selectedSidebarItem = LibrarySidebarItem(filterItem: filterItem)
            }
        } else {
            // No items available
            selectedFilterItem = nil
            selectedSidebarItem = nil
        }

        // Clear local search when switching filter types
        searchText = ""
        localSearchText = ""
    }

    private func updateFilteredItems() {
        // Get items based on whether we're in search mode or not
        var items: [LibraryFilterItem]
        
        if !libraryManager.globalSearchText.isEmpty {
            items = selectedFilterType.getFilterItems(from: libraryManager.searchResults)
        } else {
            items = libraryManager.getLibraryFilterItems(for: selectedFilterType)
        }

        // Apply local sidebar search filter if present
        if !searchText.isEmpty {
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            items = items.filter { item in
                item.name.localizedCaseInsensitiveContains(trimmedSearch)
            }
        }

        // Apply custom sorting
        filteredItems = sortItemsWithUnknownLast(items)
    }

    private func isValidFilterItem(_ item: LibraryFilterItem) -> Bool {
        // Check if this filter item exists in the current (non-searched) data
        let allItems = getFilterItems(for: selectedFilterType)
        return allItems.contains { $0.name == item.name }
    }

    // MARK: - Custom Sorting

    private func sortItemsWithUnknownLast(_ items: [LibraryFilterItem]) -> [LibraryFilterItem] {
        var unknownItems: [LibraryFilterItem] = []
        var regularItems: [LibraryFilterItem] = []

        for item in items {
            if isUnknownItem(item) {
                unknownItems.append(item)
            } else {
                regularItems.append(item)
            }
        }

        // Sort regular items based on sortAscending state
        regularItems.sort { item1, item2 in
            let comparison = item1.name.localizedCaseInsensitiveCompare(item2.name)
            return sortAscending ?
                comparison == .orderedAscending :
                comparison == .orderedDescending
        }

        return regularItems + unknownItems
    }

    private func isUnknownItem(_ item: LibraryFilterItem) -> Bool {
        item.name == selectedFilterType.unknownPlaceholder
    }

    private func getFilterItems(for filterType: LibraryFilterType) -> [LibraryFilterItem] {
        libraryManager.getLibraryFilterItems(for: filterType)
    }

    private func getArtistItemsForSearch(_ searchTerm: String) -> [LibraryFilterItem] {
        let trimmedSearch = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return getFilterItems(for: .artists) }

        var artistTrackMap: [String: Set<Track>] = [:]

        for track in libraryManager.tracks {
            let artists = ArtistParser.parse(track.artist)
            for artist in artists {
                if artist.localizedCaseInsensitiveContains(trimmedSearch) {
                    if artistTrackMap[artist] == nil {
                        artistTrackMap[artist] = []
                    }
                    artistTrackMap[artist]?.insert(track)
                }
            }
        }

        return artistTrackMap.map { artist, trackSet in
            LibraryFilterItem(name: artist, count: trackSet.count, filterType: .artists)
        }
    }

    private func createContextMenuItems(for item: LibrarySidebarItem) -> [ContextMenuItem] {
        // Don't show context menu for "All" items
        guard !item.filterName.isEmpty else { return [] }
        
        return [libraryManager.createPinContextMenuItem(
            for: item.filterType,
            filterValue: item.filterName
        )]
    }
}

#Preview {
    @Previewable @State var selectedFilterType: LibraryFilterType = .artists
    @Previewable @State var selectedFilterItem: LibraryFilterItem?
    @Previewable @State var pendingSearchText: String?

    LibrarySidebarView(
        selectedFilterType: $selectedFilterType,
        selectedFilterItem: $selectedFilterItem,
        pendingSearchText: $pendingSearchText
    )
    .environmentObject(LibraryManager())
    .frame(width: 250, height: 500)
}
