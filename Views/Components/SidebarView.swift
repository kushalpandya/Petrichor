import SwiftUI

// MARK: - SidebarView Wrapper

struct SidebarView<Item: SidebarItem>: View {
    let items: [Item]
    @Binding var selectedItem: Item?
    let onItemTap: (Item) -> Void
    let contextMenuItems: ((Item) -> [ContextMenuItem])?
    let onRename: ((Item, String) -> Void)?
    let trailingContent: ((Item) -> AnyView)?
    
    // Header configuration
    let headerTitle: String?
    let headerControls: AnyView?
    
    // Customization
    let showIcon: Bool
    let iconColor: Color
    let showCount: Bool
    
    init(
        items: [Item],
        selectedItem: Binding<Item?>,
        onItemTap: @escaping (Item) -> Void,
        contextMenuItems: ((Item) -> [ContextMenuItem])? = nil,
        onRename: ((Item, String) -> Void)? = nil,
        headerTitle: String? = nil,
        headerControls: AnyView? = nil,
        showIcon: Bool = true,
        iconColor: Color = .secondary,
        showCount: Bool = false,
        trailingContent: ((Item) -> AnyView)? = nil
    ) {
        self.items = items
        self._selectedItem = selectedItem
        self.onItemTap = onItemTap
        self.contextMenuItems = contextMenuItems
        self.onRename = onRename
        self.headerTitle = headerTitle
        self.headerControls = headerControls
        self.showIcon = showIcon
        self.iconColor = iconColor
        self.showCount = showCount
        self.trailingContent = trailingContent
    }
    
    var body: some View {
        SidebarListView(
            items: items,
            selectedItem: $selectedItem,
            onItemTap: onItemTap,
            contextMenuItems: contextMenuItems,
            onRename: onRename,
            headerTitle: headerTitle,
            headerControls: headerControls,
            showIcon: showIcon,
            iconColor: iconColor,
            showCount: showCount,
            trailingContent: trailingContent
        )
    }
}

// MARK: - Convenience Initializer for Library

extension SidebarView where Item == LibrarySidebarItem {
    init(
        filterItems: [LibraryFilterItem],
        filterType: LibraryFilterType,
        totalTracksCount: Int,
        selectedItem: Binding<LibrarySidebarItem?>,
        showAllItem: Bool = true,
        onItemTap: @escaping (LibrarySidebarItem) -> Void,
        contextMenuItems: ((LibrarySidebarItem) -> [ContextMenuItem])? = nil,
    ) {
        // Create items list
        var items: [LibrarySidebarItem] = []
        
        // Conditionally add "All" item first
        if showAllItem {
            let allItem = LibrarySidebarItem(allItemFor: filterType, count: totalTracksCount)
            items.append(allItem)
        }
        
        // Filter items should already be sorted, but we need to ensure Unknown items are at the end
        let sidebarItems = filterItems.map { LibrarySidebarItem(filterItem: $0) }
        
        // Separate unknown and regular items
        let unknownItems = sidebarItems.filter { $0.title == filterType.unknownPlaceholder }
        let regularItems = sidebarItems.filter { $0.title != filterType.unknownPlaceholder }
        
        // Add regular items first, then unknown items
        items.append(contentsOf: regularItems)
        items.append(contentsOf: unknownItems)
        
        self.init(
            items: items,
            selectedItem: selectedItem,
            onItemTap: onItemTap,
            contextMenuItems: contextMenuItems,
            onRename: nil,
            headerTitle: nil,
            headerControls: nil,
            showIcon: true,
            iconColor: .secondary,
            showCount: false,
            trailingContent: nil
        )
    }
}
