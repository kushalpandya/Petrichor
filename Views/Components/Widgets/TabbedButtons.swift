import SwiftUI

// MARK: - Animation Type
enum TabbedButtonAnimation {
    case fade
    case transform
}

// MARK: - Animation Constants
private struct AnimationConstants {
    static let transformDuration: Double = 0.2
    static let transformTextDelay: Double = 0.1
    static let fadeDuration: Double = 0.15
    static let hoverDuration: Double = 0.1
}

// MARK: - Generic Tab Protocol
protocol TabbedItem: Hashable {
    var title: String { get }
    var icon: String { get }
    var selectedIcon: String { get }
    var tooltip: String? { get }
}

// MARK: - Default implementation for selectedIcon
extension TabbedItem {
    var selectedIcon: String { icon }
    var tooltip: String? { nil }
}

// MARK: - Reusable Tabbed Buttons Component
struct TabbedButtons<Item: TabbedItem>: View {
    let items: [Item]
    @Binding var selection: Item
    let style: TabbedButtonStyle
    let animation: TabbedButtonAnimation
    let isDisabled: Bool

    init(
        items: [Item],
        selection: Binding<Item>,
        style: TabbedButtonStyle = .standard,
        animation: TabbedButtonAnimation = .fade,
        isDisabled: Bool = false
    ) {
        self.items = items
        self._selection = selection
        self.style = style
        self.animation = animation
        self.isDisabled = isDisabled
    }

    // Namespace for the sliding selection highlight (transform animation).
    // Using matchedGeometryEffect keeps the highlight perfectly aligned to the
    // selected button regardless of its (content-driven) width.
    @Namespace private var highlightNamespace

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(items.enumerated()), id: \.element) { _, item in
                TabbedButton(
                    item: item,
                    isSelected: selection == item,
                    style: style,
                    animation: animation,
                    isDisabled: isDisabled,
                    highlightNamespace: highlightNamespace
                ) {
                    if !isDisabled {
                        selection = item
                    }
                }
            }
        }
        .animation(.easeInOut(duration: AnimationConstants.transformDuration), value: selection)
        .padding(4)
        .background(
            Group {
                if style != .modern {
                    // Container background
                    RoundedRectangle(cornerRadius: style == .moderncompact ? 16 : 8)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
        )
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// MARK: - Individual Tab Button
private struct TabbedButton<Item: TabbedItem>: View {
    let item: Item
    let isSelected: Bool
    let style: TabbedButtonStyle
    let animation: TabbedButtonAnimation
    let isDisabled: Bool
    let highlightNamespace: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if !isDisabled {
                action()
            }
        }) {
            HStack(spacing: style.iconTextSpacing) {
                if style.showIcon {
                    iconImage(for: isSelected ? item.selectedIcon : item.icon)
                        .font(.system(size: style.iconSize, weight: .medium))
                        .foregroundStyle(foregroundStyle)
                        .animation(
                            .easeInOut(duration: AnimationConstants.transformDuration)
                                .delay(animation == .transform && isSelected
                                    ? AnimationConstants.transformTextDelay
                                    : 0),
                            value: isSelected
                        )
                }

                if style.showTitle {
                    Text(LocalizedStringKey(item.title))
                        .font(.system(size: style.textSize, weight: .medium))
                        .foregroundColor(foregroundColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .animation(
                            .easeInOut(duration: AnimationConstants.transformDuration)
                                .delay(animation == .transform && isSelected
                                    ? AnimationConstants.transformTextDelay
                                    : 0),
                            value: isSelected
                        )
                }
            }
            .padding(.horizontal, style.horizontalPadding)
            .frame(
                minWidth: style.buttonWidth,
                maxWidth: style.expandButtons ? .infinity : nil,
                minHeight: style.buttonHeight,
                maxHeight: style.buttonHeight
            )
            .padding(.vertical, style.buttonHeight == nil ? style.verticalPadding : 0)
            .background(backgroundView)
            .contentShape(RoundedRectangle(cornerRadius: style.contentShapeRadius ?? 6))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .background(WindowDragPreventer())
        .onHover { hovering in
            if !isDisabled {
                isHovered = hovering
            }
        }
        .if(item.tooltip != nil) { view in
            view.help(LocalizedStringKey(item.tooltip!))
        }
    }

    @ViewBuilder
    private func iconImage(for iconName: String) -> some View {
        if iconName.hasPrefix("custom.") {
            Image(iconName)
        } else {
            Image(systemName: iconName)
        }
    }

    private var foregroundStyle: AnyShapeStyle {
        if animation == .transform {
            // For transform animation, delay white text until background is in position
            if isSelected {
                return AnyShapeStyle(Color.white)
            } else if isHovered {
                return AnyShapeStyle(Color.primary)
            } else {
                return AnyShapeStyle(Color.secondary)
            }
        } else {
            // Original fade animation behavior
            if isSelected {
                return AnyShapeStyle(Color.white)
            } else if isHovered {
                return AnyShapeStyle(Color.primary)
            } else {
                return AnyShapeStyle(Color.secondary)
            }
        }
    }

    private var foregroundColor: Color {
        if animation == .transform {
            // For transform animation, delay white text until background is in position
            if isSelected {
                return .white
            } else if isHovered {
                return .primary
            } else {
                return .secondary
            }
        } else {
            // Original fade animation behavior
            if isSelected {
                return .white
            } else if isHovered {
                return .primary
            } else {
                return .secondary
            }
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if animation == .fade {
            // Original fade animation
            RoundedRectangle(cornerRadius: style.backgroundViewRadius ?? 6)
                .fill(
                    isSelected ? Color.accentColor :
                        isHovered ? Color.primary.opacity(0.06) :
                        Color.clear
                )
                .animation(.easeOut(duration: AnimationConstants.fadeDuration), value: isSelected)
                .animation(.easeOut(duration: AnimationConstants.hoverDuration), value: isHovered)
        } else {
            // Transform animation: the sliding accent highlight lives here, at
            // the content level, so it stays aligned with the icon + label
            // regardless of the button's (content-driven) width.
            // matchedGeometryEffect animates it between buttons on selection.
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: style.backgroundViewRadius ?? 6)
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "tabSelectionHighlight", in: highlightNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: style.backgroundViewRadius ?? 6)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .animation(.easeOut(duration: AnimationConstants.hoverDuration), value: isHovered)
        }
    }
}

// MARK: - Styling Options
struct TabbedButtonStyle {
    let showIcon: Bool
    let showTitle: Bool
    let iconSize: CGFloat
    let textSize: CGFloat
    let iconTextSpacing: CGFloat
    let buttonWidth: CGFloat?
    let verticalPadding: CGFloat
    let contentShapeRadius: CGFloat?
    let backgroundViewRadius: CGFloat?
    let expandButtons: Bool

    var buttonHeight: CGFloat? {
        (self.iconSize == 14 && !self.showTitle && self.verticalPadding == 0) ? 24 : nil
    }

    // Consistent horizontal padding around the label so buttons can size to
    // their (possibly longer, localized) text without the label touching the
    // edges. Icon-only styles need none.
    var horizontalPadding: CGFloat {
        showTitle ? 10 : 0
    }

    static let standard = TabbedButtonStyle(
        showIcon: true,
        showTitle: true,
        iconSize: 13,
        textSize: 12,
        iconTextSpacing: 5,
        buttonWidth: 90,
        verticalPadding: 5,
        contentShapeRadius: 6,
        backgroundViewRadius: 6,
        expandButtons: false
    )
    
    static let modern = TabbedButtonStyle(
        showIcon: true,
        showTitle: true,
        iconSize: 13,
        textSize: 12,
        iconTextSpacing: 5,
        buttonWidth: 90,
        verticalPadding: 5,
        contentShapeRadius: 16,
        backgroundViewRadius: 16,
        expandButtons: false
    )

    static let compact = TabbedButtonStyle(
        showIcon: true,
        showTitle: true,
        iconSize: 11,
        textSize: 10,
        iconTextSpacing: 4,
        buttonWidth: 80,
        verticalPadding: 5,
        contentShapeRadius: 6,
        backgroundViewRadius: 6,
        expandButtons: false
    )
    
    static let moderncompact = TabbedButtonStyle(
        showIcon: true,
        showTitle: true,
        iconSize: 11,
        textSize: 10,
        iconTextSpacing: 4,
        buttonWidth: 80,
        verticalPadding: 5,
        contentShapeRadius: 16,
        backgroundViewRadius: 16,
        expandButtons: false
    )

    static let iconOnly = TabbedButtonStyle(
        showIcon: true,
        showTitle: false,
        iconSize: 14,
        textSize: 12,
        iconTextSpacing: 0,
        buttonWidth: 32,
        verticalPadding: 5,
        contentShapeRadius: 6,
        backgroundViewRadius: 6,
        expandButtons: false
    )

    static let flexible = TabbedButtonStyle(
        showIcon: true,
        showTitle: true,
        iconSize: 12,
        textSize: 11,
        iconTextSpacing: 4,
        buttonWidth: nil,
        verticalPadding: 4,
        contentShapeRadius: 6,
        backgroundViewRadius: 6,
        expandButtons: true
    )

    static let viewToggle = TabbedButtonStyle(
        showIcon: true,
        showTitle: false,
        iconSize: 14,
        textSize: 12,
        iconTextSpacing: 0,
        buttonWidth: 32,
        verticalPadding: 0,
        contentShapeRadius: 6,
        backgroundViewRadius: 6,
        expandButtons: false
    )
}


extension TabbedButtonStyle: Equatable {
    static func == (lhs: TabbedButtonStyle, rhs: TabbedButtonStyle) -> Bool {
        lhs.showIcon == rhs.showIcon &&
               lhs.showTitle == rhs.showTitle &&
               lhs.iconSize == rhs.iconSize &&
               lhs.textSize == rhs.textSize &&
               lhs.iconTextSpacing == rhs.iconTextSpacing &&
               lhs.buttonWidth == rhs.buttonWidth &&
               lhs.verticalPadding == rhs.verticalPadding &&
               lhs.contentShapeRadius == rhs.contentShapeRadius &&
               lhs.backgroundViewRadius == rhs.backgroundViewRadius &&
               lhs.expandButtons == rhs.expandButtons
    }
}

extension Sections: TabbedItem {
    var title: String { self.label }
}

extension SettingsView.SettingsTab: TabbedItem {
    var title: String { self.rawValue }
}

struct WindowDragPreventer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NonDraggableView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    class NonDraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            false
        }
    }
}
