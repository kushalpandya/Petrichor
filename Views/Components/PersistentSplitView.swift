import SwiftUI

// MARK: - Split View Configuration

enum SplitViewType {
    case leftOnly
    case rightOnly
    case both
}

// MARK: - Split View Sizes

enum SplitViewConstants {
    // Default widths
    static let leftSidebarDefaultWidth: CGFloat = 250
    static let rightSidebarDefaultWidth: CGFloat = 350

    // Left sidebar constraints
    static let leftSidebarMinWidth: CGFloat = 250
    static let leftSidebarMaxWidth: CGFloat = 500

    // Right sidebar constraints
    static let rightSidebarMinWidth: CGFloat = 300
    static let rightSidebarMaxWidth: CGFloat = 500

    // Colors
    static let backgroundColor = Color(NSColor.controlBackgroundColor)
}

// MARK: - Simple Persistent Split View

struct PersistentSplitView<Left: View, Center: View, Right: View>: View {
    let type: SplitViewType
    let storageKeyLeft: String
    let storageKeyRight: String?

    @ViewBuilder let left: () -> Left
    @ViewBuilder let center: () -> Center
    @ViewBuilder let right: () -> Right

    @State private var leftWidth: CGFloat
    @State private var rightWidth: CGFloat
    @State private var isRightSidebarVisible: Bool

    // MARK: - Initializers

    // Left sidebar only
    init(
        left: @escaping () -> Left,
        main: @escaping () -> Center,
        leftStorageKey: String = "leftSidebarSplitPosition"
    ) where Right == EmptyView {
        self.type = .leftOnly
        self.storageKeyLeft = leftStorageKey
        self.storageKeyRight = nil
        self.left = left
        self.center = main
        self.right = { EmptyView() }

        let storedValue = UserDefaults.standard.double(forKey: leftStorageKey)
        self._leftWidth = State(initialValue: storedValue > 0 ? CGFloat(storedValue) : SplitViewConstants.leftSidebarDefaultWidth)
        self._rightWidth = State(initialValue: 0)
        self._isRightSidebarVisible = State(initialValue: false)
    }

    // Right sidebar only
    init(
        main: @escaping () -> Center,
        right: @escaping () -> Right,
        rightStorageKey: String = "rightSidebarSplitPosition"
    ) where Left == EmptyView {
        self.type = .rightOnly
        self.storageKeyLeft = ""
        self.storageKeyRight = rightStorageKey
        self.left = { EmptyView() }
        self.center = main
        self.right = right

        let storedValue = UserDefaults.standard.double(forKey: rightStorageKey)
        self._leftWidth = State(initialValue: 0)
        self._rightWidth = State(initialValue: storedValue > 0 ? CGFloat(storedValue) : SplitViewConstants.rightSidebarDefaultWidth)
        self._isRightSidebarVisible = State(initialValue: true)
    }

    // Both sidebars
    init(
        leftStorageKey: String = "leftSidebarSplitPosition",
        rightStorageKey: String = "rightSidebarSplitPosition",
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder center: @escaping () -> Center,
        @ViewBuilder right: @escaping () -> Right
    ) {
        self.type = .both
        self.storageKeyLeft = leftStorageKey
        self.storageKeyRight = rightStorageKey
        self.left = left
        self.center = center
        self.right = right

        let leftStored = UserDefaults.standard.double(forKey: leftStorageKey)
        let rightStored = UserDefaults.standard.double(forKey: rightStorageKey)
        self._leftWidth = State(initialValue: leftStored > 0 ? CGFloat(leftStored) : SplitViewConstants.leftSidebarDefaultWidth)
        self._rightWidth = State(initialValue: rightStored > 0 ? CGFloat(rightStored) : SplitViewConstants.rightSidebarDefaultWidth)
        self._isRightSidebarVisible = State(initialValue: true)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar
            if type == .leftOnly || type == .both {
                left()
                    .frame(width: leftWidth)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)

                SplitDivider(
                    splitWidth: $leftWidth,
                    minWidth: SplitViewConstants.leftSidebarMinWidth,
                    maxWidth: SplitViewConstants.leftSidebarMaxWidth
                ) {
                    UserDefaults.standard.set(Double(leftWidth), forKey: storageKeyLeft)
                }
            }

            // Center content
            center()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(0)

            if (type == .rightOnly || type == .both) && hasRightContent() {
                SplitDivider(
                    splitWidth: $rightWidth,
                    minWidth: 0, // Allow collapsing to 0
                    maxWidth: SplitViewConstants.rightSidebarMaxWidth,
                    isLeading: false
                ) {
                    if let key = storageKeyRight {
                        UserDefaults.standard.set(Double(rightWidth), forKey: key)
                    }
                }

                right()
                    .frame(width: rightWidth)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            updateWidthsFromStorage()
        }
    }
    
    private func hasRightContent() -> Bool {
        !(Right.self == EmptyView.self)
    }

    private func updateWidthsFromStorage() {
        if type == .leftOnly || type == .both {
            let storedLeft = UserDefaults.standard.double(forKey: storageKeyLeft)
            if storedLeft > 0 {
                leftWidth = CGFloat(storedLeft)
            }
        }

        if let key = storageKeyRight, type == .rightOnly || type == .both {
            let storedRight = UserDefaults.standard.double(forKey: key)
            if storedRight > 0 {
                rightWidth = CGFloat(storedRight)
            }
        }
    }
}

// MARK: - Split Divider Component (simplified)

private struct SplitDivider: View {
    @Binding var splitWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let isLeading: Bool
    let onDragEnded: () -> Void

    @State private var isHovering = false

    init(
        splitWidth: Binding<CGFloat>,
        minWidth: CGFloat,
        maxWidth: CGFloat,
        isLeading: Bool = true,
        onDragEnded: @escaping () -> Void = {}
    ) {
        self._splitWidth = splitWidth
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.isLeading = isLeading
        self.onDragEnded = onDragEnded
    }

    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHovering = hovering
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let delta = isLeading ? value.translation.width : -value.translation.width
                                let newWidth = splitWidth + delta
                                splitWidth = min(max(minWidth, newWidth), maxWidth)
                            }
                            .onEnded { _ in
                                onDragEnded()
                            }
                    )
            )
    }
}
