import SwiftUI

// MARK: - Sidebar Item Row

struct SidebarItemRow<Item: SidebarItem>: View {
    let item: Item
    let isSelected: Bool
    let isHovered: Bool
    let isEditing: Bool
    @Binding var editingText: String
    @FocusState var isEditingFieldFocused: Bool
    let showIcon: Bool
    let iconColor: Color
    let showCount: Bool
    let trailingContent: ((Item) -> AnyView)?
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    let onStartEditing: () -> Void
    let onCommitEditing: () -> Void
    let onCancelEditing: () -> Void
    
    init(
        item: Item,
        isSelected: Bool,
        isHovered: Bool,
        isEditing: Bool,
        editingText: Binding<String>,
        isEditingFieldFocused: FocusState<Bool>,
        showIcon: Bool = true,
        iconColor: Color = .secondary,
        showCount: Bool = true,
        trailingContent: ((Item) -> AnyView)? = nil,
        onTap: @escaping () -> Void,
        onHover: @escaping (Bool) -> Void,
        onStartEditing: @escaping () -> Void,
        onCommitEditing: @escaping () -> Void,
        onCancelEditing: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.isEditing = isEditing
        self._editingText = editingText
        self._isEditingFieldFocused = isEditingFieldFocused
        self.showIcon = showIcon
        self.iconColor = iconColor
        self.showCount = showCount
        self.trailingContent = trailingContent
        self.onTap = onTap
        self.onHover = onHover
        self.onStartEditing = onStartEditing
        self.onCommitEditing = onCommitEditing
        self.onCancelEditing = onCancelEditing
    }
    
    @State private var isTitleTruncated = false
    @State private var isSubtitleTruncated = false
    
    private func checkIfTruncated(text: String, width: CGFloat, font: Font) -> Bool {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        return size.width > width
    }

    var body: some View {
        HStack(spacing: 10) {
            iconView
            contentView
            Spacer(minLength: 0)
            trailingView
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(rowBackground)
        .onTapGesture {
            if !isEditing {
                onTap()
            }
        }
        .onHover { hovering in
            onHover(hovering)
        }
        .contextMenu {
            // Handled in parent view
        }
    }
    
    // MARK: - Icon View
    
    @ViewBuilder
    private var iconView: some View {
        if showIcon, let icon = item.icon {
            Image(systemName: icon)
                .foregroundColor(isSelected ? .white : iconColor)
                .font(.system(size: 16))
                .frame(width: 16, height: 16)
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        if isEditing {
            editingField
        } else {
            displayContent
        }
    }
    
    private var editingField: some View {
        TextField("", text: $editingText)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            .foregroundColor(isSelected ? .white : .primary)
            .focused($isEditingFieldFocused)
            .onSubmit {
                onCommitEditing()
            }
            .onExitCommand {
                onCancelEditing()
            }
    }
    
    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            titleView
            
            if showCount, let subtitle = item.subtitle {
                subtitleView(subtitle: subtitle)
            }
        }
    }
    
    private var titleView: some View {
        Text(item.title)
            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            .italic(isUnknownItem)
            .lineLimit(1)
            .foregroundColor(isSelected ? .white : .primary)
            .help(isTitleTruncated ? item.title : "")
            .background(truncationDetector(for: item.title, isTruncated: $isTitleTruncated))
    }
    
    private var isUnknownItem: Bool {
        if let librarySidebarItem = item as? LibrarySidebarItem {
            return librarySidebarItem.title == librarySidebarItem.filterType.unknownPlaceholder
        }
        return false
    }
    
    private func subtitleView(subtitle: String) -> some View {
        Text(subtitle)
            .font(.system(size: 11))
            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            .lineLimit(1)
            .help(isSubtitleTruncated ? subtitle : "")
            .background(truncationDetector(for: subtitle, isTruncated: $isSubtitleTruncated, fontSize: 11))
    }
    
    // MARK: - Truncation Detection
    
    private func truncationDetector(for text: String, isTruncated: Binding<Bool>, fontSize: CGFloat = 13) -> some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    isTruncated.wrappedValue = checkIfTruncated(
                        text: text,
                        width: geometry.size.width,
                        font: .system(size: fontSize)
                    )
                }
                .onChange(of: text) {
                    isTruncated.wrappedValue = checkIfTruncated(
                        text: text,
                        width: geometry.size.width,
                        font: .system(size: fontSize)
                    )
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    isTruncated.wrappedValue = checkIfTruncated(
                        text: text,
                        width: newWidth,
                        font: .system(size: fontSize)
                    )
                }
        }
    }
    
    // MARK: - Trailing View
    
    @ViewBuilder
    private var trailingView: some View {
        if let trailing = trailingContent?(item) {
            trailing
        }
    }

    // MARK: - Background

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
            .animation(.easeInOut(duration: 0.05), value: isSelected)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isHovered {
            return Color.accentColor.opacity(0.1)
        } else {
            return Color.clear
        }
    }
}
