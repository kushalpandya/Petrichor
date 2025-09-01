import SwiftUI

struct EntityGridView<T: Entity>: View {
    let entities: [T]
    let onSelectEntity: (T) -> Void
    let contextMenuItems: (T) -> [ContextMenuItem]

    @State private var hoveredEntityID: UUID?
    @State private var isScrolling = false
    @State private var scrollWorkItem: DispatchWorkItem?

    private let columns = [
        GridItem(.adaptive(minimum: ViewDefaults.gridArtworkSize, maximum: 200), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(entities) { entity in
                    EntityGridItem(
                        entity: entity,
                        isHovered: isScrolling ? false : (hoveredEntityID == entity.id),
                        isScrolling: isScrolling,
                        onSelect: {
                            onSelectEntity(entity)
                        },
                        onHover: { isHovered in
                            if !isScrolling {
                                hoveredEntityID = isHovered ? entity.id : nil
                            }
                        }
                    )
                    .contextMenu {
                        ForEach(contextMenuItems(entity), id: \.id) { item in
                            contextMenuItem(item)
                        }
                    }
                    .id(entity.id)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometry.frame(in: .named("scroll")).origin.y
                    )
                }
            )
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { _ in
            handleScrollChange()
        }
    }
    
    private func handleScrollChange() {
        isScrolling = true
        hoveredEntityID = nil
        
        scrollWorkItem?.cancel()
        
        scrollWorkItem = DispatchWorkItem {
            isScrolling = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: scrollWorkItem!)
    }

    @ViewBuilder
    private func contextMenuItem(_ item: ContextMenuItem) -> some View {
        switch item {
        case .button(let title, let role, let action):
            Button(title, role: role, action: action)
        case .menu(let title, let items):
            Menu(title) {
                ForEach(items, id: \.id) { subItem in
                    if case .button(let subTitle, let subRole, let subAction) = subItem {
                        Button(subTitle, role: subRole, action: subAction)
                    }
                }
            }
        case .divider:
            Divider()
        }
    }
}

// MARK: - Entity Grid Item
private struct EntityGridItem<T: Entity>: View {
    let entity: T
    let isHovered: Bool
    let isScrolling: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var artworkImage: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            artworkSection
            textSection
        }
        .padding(8)
        .background(backgroundView)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover(perform: onHover)
        .animation(.easeInOut(duration: AnimationDuration.quickDuration), value: isHovered)
    }
    
    @ViewBuilder
    private var artworkSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(1, contentMode: .fit)

            if let image = artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: ViewDefaults.gridArtworkSize, height: ViewDefaults.gridArtworkSize)
                    .clipped()
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: Icons.entityIcon(for: entity))
                        .font(.system(size: 48))
                        .foregroundColor(.gray)

                    Text(entity.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: ViewDefaults.gridArtworkSize, height: ViewDefaults.gridArtworkSize)
        .task(id: entity.id) {
            await loadEntityArtwork()
        }
        .onDisappear {
            artworkImage = nil
        }
    }
    
    private var textSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entity.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(.primary)
                .help(entity.name)

            if let subtitle = entity.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .help(subtitle)
            }

            if entity is AlbumEntity {
                Text("\(entity.trackCount) \(entity.trackCount == 1 ? "song" : "songs")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: ViewDefaults.gridArtworkSize, alignment: .leading)
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
            .animation(.easeInOut(duration: AnimationDuration.quickDuration), value: isHovered)
    }

    private func loadEntityArtwork() async {
        let delay = isScrolling ? TimeConstants.oneFiftyMilliseconds : TimeConstants.fiftyMilliseconds
        
        await loadEntityArtworkAsync(
            from: entity.artworkLarge,
            into: $artworkImage,
            delay: delay
        )
    }
}

// MARK: - Supporting Types

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
