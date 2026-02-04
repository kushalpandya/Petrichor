import SwiftUI

// MARK: - List Header Style View Modifier

struct ListHeaderStyle: ViewModifier {
    let height: CGFloat
    let padding: EdgeInsets

    init(height: CGFloat = 36, padding: EdgeInsets? = nil) {
        self.height = height
        self.padding = padding ?? EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color(NSColor.clear))
    }
}

// MARK: - View Extension

extension View {
    func listHeaderStyle(height: CGFloat = 36, padding: EdgeInsets? = nil) -> some View {
        modifier(ListHeaderStyle(height: height, padding: padding))
    }
}

// MARK: - List Header Container

struct ListHeader<Content: View>: View {
    enum HeaderType {
        case simple
        case expanded
    }

    let type: HeaderType
    let height: CGFloat?
    let padding: EdgeInsets?
    let content: () -> Content

    init(
        type: HeaderType = .simple,
        height: CGFloat? = nil,
        padding: EdgeInsets? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.type = type
        self.height = height
        self.padding = padding
        self.content = content
    }

    var body: some View {
        HStack {
            content()
        }
        .listHeaderStyle(
            height: height ?? (type == .simple ? 36 : 120),
            padding: padding
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

struct TrackListHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trackCount: Int
    let trailing: (() -> Trailing)?

    init(
        title: String,
        subtitle: String? = nil,
        trackCount: Int,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trackCount = trackCount
        self.trailing = trailing
    }

    init(
        title: String,
        subtitle: String? = nil,
        trackCount: Int
    ) where Trailing == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.trackCount = trackCount
        self.trailing = nil
    }

    var body: some View {
        ListHeader {
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
            } else {
                Text("\(trackCount) tracks")
                    .headerSubtitleStyle()
            }
        }
    }
}

struct TrackListHeaderWithOptions<TrailingContent: View>: View {
    let title: String
    let subtitle: String?
    @Binding var sortOrder: [KeyPathComparator<Track>]
    @Binding var tableRowSize: TableRowSize
    let trailingContent: TrailingContent

    init(
        title: String,
        subtitle: String? = nil,
        sortOrder: Binding<[KeyPathComparator<Track>]>,
        tableRowSize: Binding<TableRowSize>,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self._sortOrder = sortOrder
        self._tableRowSize = tableRowSize
        self.trailingContent = trailingContent()
    }
    
    init(
        title: String,
        subtitle: String? = nil,
        sortOrder: Binding<[KeyPathComparator<Track>]>,
        tableRowSize: Binding<TableRowSize>
    ) where TrailingContent == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self._sortOrder = sortOrder
        self._tableRowSize = tableRowSize
        self.trailingContent = EmptyView()
    }

    var body: some View {
        ListHeader {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .headerTitleStyle()

                if let subtitle = subtitle {
                    Text(subtitle)
                        .headerSubtitleStyle()
                }
            }

            Spacer()
            
            trailingContent

            TrackTableOptionsDropdown(
                sortOrder: $sortOrder,
                tableRowSize: $tableRowSize
            )
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

// MARK: - Divider Extension for Headers

extension Divider {
    static var headerDivider: some View {
        Divider()
            .frame(height: 1)
            .overlay(Color(NSColor.separatorColor).opacity(0.3))
    }
}
