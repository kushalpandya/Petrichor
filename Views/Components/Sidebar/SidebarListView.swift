import SwiftUI

// MARK: - Sidebar List View

struct SidebarListView<Item: SidebarItem>: View {
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

    @State private var hoveredItemID: UUID?
    @State private var editingItemID: UUID?
    @State private var editingText: String = ""
    @FocusState private var isEditingFieldFocused: Bool
    @State private var lastClickTime = Date()
    @State private var lastClickedItemID: UUID?

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
        VStack(spacing: 0) {
            // Header
            if headerTitle != nil || headerControls != nil {
                HStack {
                    if let title = headerTitle {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }
                    
                    Spacer()
                    
                    if let controls = headerControls {
                        controls
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                Divider()
            }

            // Content
            if items.isEmpty {
                emptyView
            } else {
                itemsList
            }
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 1) {
                ForEach(items) { item in
                    SidebarItemRow(
                        item: item,
                        isSelected: selectedItem?.id == item.id,
                        isHovered: hoveredItemID == item.id,
                        isEditing: editingItemID == item.id,
                        editingText: $editingText,
                        isEditingFieldFocused: _isEditingFieldFocused,
                        showIcon: showIcon,
                        iconColor: iconColor,
                        trailingContent: trailingContent,
                        onTap: {
                            handleItemTap(item)
                        },
                        onHover: { isHovered in
                            hoveredItemID = isHovered ? item.id : nil
                        },
                        onStartEditing: {
                            startEditing(item)
                        },
                        onCommitEditing: {
                            commitEditing(for: item)
                        },
                        onCancelEditing: {
                            cancelEditing()
                        }
                    )
                    .contextMenu {
                        if let menuItems = contextMenuItems?(item) {
                            ForEach(Array(menuItems.enumerated()), id: \.offset) { _, menuItem in
                                contextMenuItem(menuItem)
                            }
                        }
                    }
                    .onTapGesture {
                        // Handle single click
                        let now = Date()
                        if lastClickedItemID == item.id && now.timeIntervalSince(lastClickTime) < 0.5 {
                            // Double click detected
                            if item.isEditable, onRename != nil {
                                startEditing(item)
                            }
                        } else {
                            // Single click
                            selectedItem = item
                            onItemTap(item)
                            lastClickTime = now
                            lastClickedItemID = item.id
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.gray)

            Text("No Items")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Context Menu Helper

    @ViewBuilder
    private func contextMenuItem(_ item: ContextMenuItem) -> some View {
        switch item {
        case .button(let title, let role, let action):
            if title == "Rename" {
                // Special handling for rename action
                Button(title, role: role) {
                    if let selectedItem = selectedItem, selectedItem.isEditable {
                        startEditing(selectedItem)
                    }
                }
            } else {
                Button(title, role: role, action: action)
            }
        case .menu(let title, let items):
            Menu(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, subItem in
                    if case .button(let subTitle, let subRole, let subAction) = subItem {
                        Button(subTitle, role: subRole, action: subAction)
                    }
                }
            }
        case .divider:
            Divider()
        }
    }

    // MARK: - Editing Helpers

    private func startEditing(_ item: Item) {
        editingItemID = item.id
        editingText = item.title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isEditingFieldFocused = true
        }
    }

    private func commitEditing(for item: Item) {
        let trimmedText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty && trimmedText != item.title {
            onRename?(item, trimmedText)
        }
        cancelEditing()
    }

    private func cancelEditing() {
        editingItemID = nil
        editingText = ""
        isEditingFieldFocused = false
    }

    private func handleItemTap(_ item: Item) {
        selectedItem = item
        onItemTap(item)
    }
}

// MARK: - Convenience Extensions

extension SidebarListView where Item == LibrarySidebarItem {
    init(
        filterItems: [LibraryFilterItem],
        filterType: LibraryFilterType,
        totalTracksCount: Int,
        selectedItem: Binding<LibrarySidebarItem?>,
        onItemTap: @escaping (LibrarySidebarItem) -> Void,
        contextMenuItems: ((LibrarySidebarItem) -> [ContextMenuItem])? = nil
    ) {
        // Create items list
        var items: [LibrarySidebarItem] = []

        // Add "All" item first
        let allItem = LibrarySidebarItem(allItemFor: filterType, count: totalTracksCount)
        items.append(allItem)

        // Convert filter items to sidebar items
        let sidebarItems = filterItems.map { LibrarySidebarItem(filterItem: $0) }
        
        // Separate unknown and regular items
        let unknownItems = sidebarItems.filter { item in
            item.filterName == filterType.unknownPlaceholder ||
            item.title == filterType.unknownPlaceholder
        }
        let regularItems = sidebarItems.filter { item in
            item.filterName != filterType.unknownPlaceholder &&
            item.title != filterType.unknownPlaceholder
        }
        
        // Add regular items first, then unknown items at the end
        items.append(contentsOf: regularItems)
        items.append(contentsOf: unknownItems)

        self.init(
            items: items,
            selectedItem: selectedItem,
            onItemTap: onItemTap,
            contextMenuItems: contextMenuItems,
            showIcon: true,
            iconColor: .secondary,
            showCount: false
        )
    }
}
