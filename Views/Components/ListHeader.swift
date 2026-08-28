import SwiftUI

// MARK: - List Header Style View Modifier

struct ListHeaderStyle: ViewModifier {
    let height: CGFloat
    let padding: EdgeInsets
    let opaque: Bool

    init(height: CGFloat = 36, padding: EdgeInsets? = nil, opaque: Bool = false) {
        self.height = height
        self.padding = padding ?? EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        self.opaque = opaque
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(opaque ? Color(NSColor.controlBackgroundColor) : Color(NSColor.clear))
    }
}

// MARK: - View Extension

extension View {
    func listHeaderStyle(height: CGFloat = 36, padding: EdgeInsets? = nil, opaque: Bool = false) -> some View {
        modifier(ListHeaderStyle(height: height, padding: padding, opaque: opaque))
    }
}

// MARK: - List Header Container

struct ListHeader<Content: View>: View {
    enum HeaderType {
        case simple
    }

    let type: HeaderType
    let height: CGFloat?
    let padding: EdgeInsets?
    let opaque: Bool
    let content: () -> Content

    init(
        type: HeaderType = .simple,
        height: CGFloat? = nil,
        padding: EdgeInsets? = nil,
        opaque: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.type = type
        self.height = height
        self.padding = padding
        self.opaque = opaque
        self.content = content
    }

    var body: some View {
        HStack {
            content()
        }
        .listHeaderStyle(
            height: height ?? 36,
            padding: padding,
            opaque: opaque
        )
    }
}

// MARK: - Specialized Header Components

struct PlaylistHeader<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
    }
}

struct EntityHeader<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
    }
}

/// Back chevron for full-screen detail overlays (entity + playlist), so the two
/// headers can't drift apart.
struct DetailBackButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Image(systemName: Icons.chevronLeft)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .help("Back")
        } else {
            Button(action: action) {
                Image(systemName: Icons.chevronLeft)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered ? Color(NSColor.controlAccentColor).opacity(0.15) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isHovered ? Color(NSColor.controlAccentColor).opacity(0.3) : Color.clear,
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .help("Back")
        }
    }
}

struct TrackListHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trackCount: Int?
    let sortOrder: Binding<[KeyPathComparator<Track>]>?
    let tableRowSize: Binding<TableRowSize>?
    let usesGlobalSortOrder: Bool
    let trailing: (() -> Trailing)?

    // With sort options + trailing content
    init(
        title: String,
        subtitle: String? = nil,
        sortOrder: Binding<[KeyPathComparator<Track>]>,
        tableRowSize: Binding<TableRowSize>,
        usesGlobalSortOrder: Bool = true,
        @ViewBuilder trailingContent: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trackCount = nil
        self.sortOrder = sortOrder
        self.tableRowSize = tableRowSize
        self.usesGlobalSortOrder = usesGlobalSortOrder
        self.trailing = trailingContent
    }

    // With sort options, no trailing content
    init(
        title: String,
        subtitle: String? = nil,
        sortOrder: Binding<[KeyPathComparator<Track>]>,
        tableRowSize: Binding<TableRowSize>,
        usesGlobalSortOrder: Bool = true
    ) where Trailing == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.trackCount = nil
        self.sortOrder = sortOrder
        self.tableRowSize = tableRowSize
        self.usesGlobalSortOrder = usesGlobalSortOrder
        self.trailing = nil
    }

    // With track count + trailing content, no sort options
    init(
        title: String,
        subtitle: String? = nil,
        trackCount: Int,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trackCount = trackCount
        self.sortOrder = nil
        self.tableRowSize = nil
        self.usesGlobalSortOrder = true
        self.trailing = trailing
    }

    // With track count only, no sort options, no trailing
    init(
        title: String,
        subtitle: String? = nil,
        trackCount: Int
    ) where Trailing == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.trackCount = trackCount
        self.sortOrder = nil
        self.tableRowSize = nil
        self.usesGlobalSortOrder = true
        self.trailing = nil
    }

    var body: some View {
        ListHeader(opaque: true) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .headerTitleStyle()

                if let subtitle = subtitle {
                    Text(subtitle)
                        .headerSubtitleStyle()
                }
            }

            Spacer()

            if let trailing = trailing {
                trailing()
            } else if let trackCount = trackCount {
                Text("\(trackCount) tracks")
                    .headerSubtitleStyle()
            }

            if let sortOrder = sortOrder, let tableRowSize = tableRowSize {
                TrackTableOptionsDropdown(
                    sortOrder: sortOrder,
                    tableRowSize: tableRowSize,
                    usesGlobalSortOrder: usesGlobalSortOrder
                )
            }
        }
    }
}

// MARK: - Common Header Text Styles

struct HeaderTitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
    }
}

struct HeaderSubtitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

extension View {
    func headerTitleStyle() -> some View {
        modifier(HeaderTitleStyle())
    }

    func headerSubtitleStyle() -> some View {
        modifier(HeaderSubtitleStyle())
    }
}
