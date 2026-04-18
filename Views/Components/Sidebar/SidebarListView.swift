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

    // Reordering
    let reorderableFromIndex: Int?
    let onReorder: (([Item]) -> Void)?

    // External editing trigger
    @Binding var externalEditingItemID: UUID?

    @State private var hoveredItemID: UUID?
    @State private var editingItemID: UUID?
    @State private var editingText: String = ""
    @FocusState private var isEditingFieldFocused: Bool
    @State private var lastClickTime = Date()
    @State private var lastClickedItemID: UUID?
    @State private var draggedItemID: UUID?
    @State private var dropTargetItemID: UUID?

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
        trailingContent: ((Item) -> AnyView)? = nil,
        reorderableFromIndex: Int? = nil,
        onReorder: (([Item]) -> Void)? = nil,
        externalEditingItemID: Binding<UUID?> = .constant(nil)
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
        self.reorderableFromIndex = reorderableFromIndex
        self.onReorder = onReorder
        self._externalEditingItemID = externalEditingItemID
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
        .onChange(of: externalEditingItemID) { _, newID in
            if let id = newID, let item = items.first(where: { $0.id == id }) {
                startEditing(item)
                externalEditingItemID = nil
            }
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 1) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let isDraggable = isItemDraggable(at: index)

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
                    .opacity(draggedItemID == item.id ? 0.4 : 1.0)
                    .overlay(alignment: .top) {
                        if dropTargetItemID == item.id && draggedItemID != item.id && isDraggable {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                                .padding(.horizontal, 8)
                        }
                    }
                    .if(isDraggable) { view in
                        view.onDrag {
                            draggedItemID = item.id
                            return NSItemProvider(object: item.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: SidebarReorderDropDelegate(
                                targetItem: item,
                                targetIndex: index,
                                items: items,
                                reorderableFromIndex: reorderableFromIndex ?? 0,
                                draggedItemID: $draggedItemID,
                                dropTargetItemID: $dropTargetItemID,
                                onReorder: onReorder ?? { _ in }
                            )
                        )
                    }
                    .contextMenu {
                        if let menuItems = contextMenuItems?(item) {
                            ForEach(Array(menuItems.enumerated()), id: \.offset) { _, menuItem in
                                if case .button(let title, _, _, _) = menuItem,
                                   title == "Rename", item.isEditable, onRename != nil {
                                    Button("Rename") { startEditing(item) }
                                } else {
                                    contextMenuItem(menuItem)
                                }
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

    // MARK: - Reordering Helpers

    private func isItemDraggable(at index: Int) -> Bool {
        guard let fromIndex = reorderableFromIndex, onReorder != nil else { return false }
        return index >= fromIndex
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
        ContextMenuItemView(item: item)
    }

    // MARK: - Editing Helpers

    private func startEditing(_ item: Item) {
        editingItemID = item.id
        editingText = item.title
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

// MARK: - Reorder Drop Delegate

private struct SidebarReorderDropDelegate<Item: SidebarItem>: DropDelegate {
    let targetItem: Item
    let targetIndex: Int
    let items: [Item]
    let reorderableFromIndex: Int
    @Binding var draggedItemID: UUID?
    @Binding var dropTargetItemID: UUID?
    let onReorder: ([Item]) -> Void

    func dropEntered(info: DropInfo) {
        guard draggedItemID != targetItem.id else { return }
        dropTargetItemID = targetItem.id
    }

    func dropExited(info: DropInfo) {
        if dropTargetItemID == targetItem.id {
            dropTargetItemID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID = draggedItemID else { return false }
        guard let fromIndex = items.firstIndex(where: { $0.id == draggedID }) else { return false }
        guard fromIndex >= reorderableFromIndex else { return false }
        guard targetIndex >= reorderableFromIndex else { return false }

        var reordered = items
        let movedItem = reordered.remove(at: fromIndex)

        let toIndex = fromIndex < targetIndex ? targetIndex - 1 : targetIndex
        let clampedIndex = max(reorderableFromIndex, min(toIndex, reordered.count))
        reordered.insert(movedItem, at: clampedIndex)

        draggedItemID = nil
        dropTargetItemID = nil
        onReorder(reordered)
        return true
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
